// Workaround: expo-modules-autolinking@55.x doesn't follow symlinks in node_modules
// when resolving local Expo modules (the kind made via `create-expo-module --local`).
// npm's `file:` protocol creates symlinks. So after every `npm install`, we delete
// the symlink and replace it with a real copy. The autolinker then sees it as a
// regular dependency and registers it in ExpoModulesProvider.swift.
//
// Trade-off: edits to modules/echo-lidar/ are NOT reflected in node_modules/echo-lidar
// until you re-run `npm install` (or this script). Native (Swift) edits are picked up
// at the next Xcode build regardless. JS/TS edits to the module require re-copy.

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const modulesDir = path.join(projectRoot, 'modules');
const nodeModulesDir = path.join(projectRoot, 'node_modules');

if (!fs.existsSync(modulesDir)) process.exit(0);

for (const moduleName of fs.readdirSync(modulesDir)) {
  const sourceDir = path.join(modulesDir, moduleName);
  if (!fs.statSync(sourceDir).isDirectory()) continue;

  const targetDir = path.join(nodeModulesDir, moduleName);
  const stat = fs.lstatSync(targetDir, { throwIfNoEntry: false });
  if (stat?.isSymbolicLink()) {
    fs.unlinkSync(targetDir);
  } else if (stat?.isDirectory()) {
    fs.rmSync(targetDir, { recursive: true, force: true });
  }

  fs.cpSync(sourceDir, targetDir, { recursive: true, dereference: true });
  console.log(`[link-local-modules] copied ${moduleName} → node_modules/`);
}

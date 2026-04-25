# Running On iPhone

## Overview

This project should be run on a real iPhone, not just the iOS Simulator.

For the LiDAR features to work, you need:

- a Mac
- `Xcode`
- a real iPhone connected to the Mac
- an iPhone model with a `LiDAR Scanner`
- `Developer Mode` enabled on the iPhone if prompted

## Where To Run Commands

Run commands from the app folder:

```bash
cd /Users/k3vinwvng/Documents/echolocation/echolocation
```

## First-Time Setup

Install dependencies:

```bash
npm install
```

Open the iOS project if you need to fix signing:

```bash
xed ios
```

## Simplest Way To Install The App On Your iPhone

Connect your iPhone to your Mac with a cable, then run:

```bash
npx expo run:ios --device
```

What this does:

- builds the iOS app locally
- installs it on your connected iPhone
- starts the Metro bundler for development

If Expo asks you to choose a device, select your iPhone.

## If Code Signing Fails

If the build fails because of signing, do this in `Xcode`:

1. Open `ios` in Xcode.
2. Select the app target.
3. Open `Signing & Capabilities`.
4. Choose your Apple team.
5. Change the bundle identifier from the default if needed.
6. Run the app to your phone once from Xcode.

After that, `npx expo run:ios --device` is usually enough.

## Normal Development Loop

Once the development build is installed on the phone:

```bash
npx expo start
```

Then:

- open the app on the iPhone
- connect it to the Metro bundler
- reload after JavaScript changes

If your phone and Mac are on the same Wi-Fi, this is usually enough.

If local networking is flaky, use:

```bash
npx expo start --tunnel
```

## When You Need To Rebuild

You need to rebuild the iPhone app when you change:

- Swift code
- native iOS config
- native dependencies
- `app.json`
- Expo plugins that affect native code

Rebuild with:

```bash
npx expo run:ios --device
```

If you only change JavaScript or TypeScript, you usually do not need a full rebuild.

## How To Tell If Your iPhone Has LiDAR

There are three good ways to check.

### Option 1: Check The iPhone Model Name

On the iPhone:

1. Open `Settings`
2. Go to `General`
3. Go to `About`
4. Look at `Model Name`

As of `April 24, 2026`, the iPhones Apple lists with a `LiDAR Scanner` are the `Pro` and `Pro Max` lines starting with the iPhone 12 generation:

- `iPhone 12 Pro`
- `iPhone 12 Pro Max`
- `iPhone 13 Pro`
- `iPhone 13 Pro Max`
- `iPhone 14 Pro`
- `iPhone 14 Pro Max`
- `iPhone 15 Pro`
- `iPhone 15 Pro Max`
- `iPhone 16 Pro`
- `iPhone 16 Pro Max`

If your phone is a non-`Pro` model such as:

- `iPhone 12`
- `iPhone 13`
- `iPhone 14`
- `iPhone 15`
- `iPhone 16`
- `iPhone SE`

you should assume it does **not** have the rear LiDAR scanner needed for this project.

### Option 2: Check The Camera Area

On supported Pro models, the rear camera cluster has a small extra sensor for `LiDAR` near the cameras and flash.

This is a quick visual clue, but the model-name check is more reliable.

### Option 3: Check In Code

This is the best technical check for the app itself.

Use `ARKit` support checks at runtime:

```swift
let arSupported = ARWorldTrackingConfiguration.isSupported
let depthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
```

Interpretation:

- if `arSupported` is `false`, the device cannot run the AR session you need
- if `depthSupported` is `false`, the device does not support LiDAR scene depth for this feature
- if `meshSupported` is `false`, you may still have depth, but not full mesh classification

For this app, the most important check is:

```swift
ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
```

If that returns `true`, your phone supports the LiDAR depth feature the app needs.

## Recommended Practical Check

Use this order:

1. check the phone model in `Settings > General > About`
2. confirm it is a `Pro` or `Pro Max` model from the supported generations
3. confirm in code with `supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])`

That gives you both a quick answer and the real runtime truth.

## What To Expect On A Non-LiDAR iPhone

If the phone does not support LiDAR scene depth:

- the app can still run as a normal React Native app
- ARKit LiDAR depth features will not work
- obstacle distance estimation for this project will not work as intended
- you should show a clear `device not supported` message in the app

## Recommended Next Step

Before writing more app logic, verify this on your phone:

```swift
ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
```

If it returns `true`, you can move forward confidently.

## Sources

- Expo local app development: https://docs.expo.dev/guides/local-app-development/
- Expo development builds: https://docs.expo.dev/develop/development-builds/use-development-builds/
- Expo switch to development builds: https://docs.expo.dev/develop/development-builds/expo-go-to-dev-build
- Expo iOS Developer Mode: https://docs.expo.dev/guides/ios-developer-mode/
- Apple ARKit support checks: https://developer.apple.com/documentation/arkit/arconfiguration/supportsframesemantics%28_%3A%29
- Apple `sceneDepth`: https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth
- Apple `smoothedSceneDepth`: https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/smoothedscenedepth
- Apple device support and permission: https://developer.apple.com/documentation/arkit/verifying-device-support-and-user-permission
- Apple scene reconstruction support: https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction%28_%3A%29
- Apple iPhone 12 Pro tech specs: https://support.apple.com/kb/SP831
- Apple iPhone 13 Pro tech specs: https://support.apple.com/en-us/111871
- Apple iPhone 14 Pro user guide: https://support.apple.com/guide/iphone/iphone-14-pro-iph6928b4ea3/ios
- Apple iPhone 15 Pro tech specs: https://support.apple.com/en-lamr/111829
- Apple iPhone 16 Pro tech specs: https://support.apple.com/en-us/121031

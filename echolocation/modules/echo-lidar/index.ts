// Reexport the native module. On web, it will be resolved to EchoLidarModule.web.ts
// and on native platforms to EchoLidarModule.ts
export { default } from './src/EchoLidarModule';
export { default as EchoLidarView } from './src/EchoLidarView';
export * from  './src/EchoLidar.types';

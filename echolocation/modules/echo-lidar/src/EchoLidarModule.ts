import { EventEmitter, requireNativeModule } from 'expo-modules-core';

import type {
  EchoLidarModuleEvents,
  EchoMode,
  EchoSupportStatus,
  SceneLabelResult,
  SnapshotCapture,
} from './EchoLidar.types';

type NativeEchoLidarModule = {
  isSupported(): boolean;
  supportsDepth(): boolean;
  supportsMeshClassification(): boolean;
  getSupportStatus(): EchoSupportStatus;
  start(mode?: EchoMode): Promise<void>;
  stop(): Promise<void>;
  startVoiceCommands(): Promise<void>;
  stopVoiceCommands(): Promise<void>;
  captureSnapshot(): Promise<SnapshotCapture>;
  captureAndLabelScene(): Promise<SceneLabelResult>;
};

// requireNativeModule throws in Expo Go / simulator without a dev build.
// Fall back to a no-op stub so the JS bundle still loads.
let EchoLidarModule: NativeEchoLidarModule;
try {
  EchoLidarModule = requireNativeModule<NativeEchoLidarModule>('EchoLidar');
} catch {
  EchoLidarModule = {
    isSupported: () => false,
    supportsDepth: () => false,
    supportsMeshClassification: () => false,
    getSupportStatus: () => ({ isARSupported: false, supportsDepth: false, supportsMeshClassification: false }),
    start: async () => { throw new Error('EchoLidar native module not available — use a development build'); },
    stop: async () => {},
    startVoiceCommands: async () => { throw new Error('Voice commands require a development build on iOS'); },
    stopVoiceCommands: async () => {},
    captureSnapshot: async () => { throw new Error('Snapshot capture requires a development build on iOS'); },
    captureAndLabelScene: async () => { throw new Error('ML Kit scene labeling requires a development build on iOS'); },
  };
}

export const EchoLidarEmitter = new EventEmitter<EchoLidarModuleEvents>(
  EchoLidarModule as never
);

export default EchoLidarModule;

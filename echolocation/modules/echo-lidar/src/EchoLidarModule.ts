import { EventEmitter, requireNativeModule } from 'expo-modules-core';

import type { EchoLidarModuleEvents, EchoMode, EchoSupportStatus } from './EchoLidar.types';

type NativeEchoLidarModule = {
  isSupported(): boolean;
  supportsDepth(): boolean;
  supportsMeshClassification(): boolean;
  getSupportStatus(): EchoSupportStatus;
  start(mode?: EchoMode): Promise<void>;
  stop(): Promise<void>;
};

const EchoLidarModule = requireNativeModule<NativeEchoLidarModule>('EchoLidar');

export const EchoLidarEmitter = new EventEmitter<EchoLidarModuleEvents>(
  EchoLidarModule as never
);

export default EchoLidarModule;

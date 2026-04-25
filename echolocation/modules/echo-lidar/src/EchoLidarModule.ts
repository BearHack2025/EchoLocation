import { NativeModule, requireNativeModule } from 'expo';

import { EchoLidarModuleEvents } from './EchoLidar.types';

declare class EchoLidarModule extends NativeModule<EchoLidarModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<EchoLidarModule>('EchoLidar');

import { registerWebModule, NativeModule } from 'expo';

import { ChangeEventPayload } from './EchoLidar.types';

type EchoLidarModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
}

class EchoLidarModule extends NativeModule<EchoLidarModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
};

export default registerWebModule(EchoLidarModule, 'EchoLidarModule');

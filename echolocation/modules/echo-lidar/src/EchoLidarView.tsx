import { requireNativeView } from 'expo';
import * as React from 'react';

import { EchoLidarViewProps } from './EchoLidar.types';

const NativeView: React.ComponentType<EchoLidarViewProps> =
  requireNativeView('EchoLidar');

export default function EchoLidarView(props: EchoLidarViewProps) {
  return <NativeView {...props} />;
}

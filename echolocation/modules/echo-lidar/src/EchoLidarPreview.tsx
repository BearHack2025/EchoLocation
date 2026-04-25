import { requireNativeViewManager } from 'expo-modules-core';
import type { ComponentType } from 'react';
import { View, type ViewProps } from 'react-native';

let NativePreview: ComponentType<ViewProps>;
try {
  NativePreview = requireNativeViewManager<ViewProps>('EchoLidar');
} catch {
  NativePreview = (props: ViewProps) => <View {...props} />;
}

export function EchoLidarPreview(props: ViewProps) {
  return <NativePreview {...props} />;
}

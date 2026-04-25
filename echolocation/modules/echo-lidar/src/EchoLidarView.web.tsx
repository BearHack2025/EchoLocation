import * as React from 'react';

import { EchoLidarViewProps } from './EchoLidar.types';

export default function EchoLidarView(props: EchoLidarViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}

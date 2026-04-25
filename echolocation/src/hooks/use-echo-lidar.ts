import { useEffect, useRef, useState } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate } from 'echo-lidar';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  const start = async (mode: 'echo' | 'describe' | 'quiet' = 'describe') => {
    setError(null);
    try {
      await EchoLidarModule.start(mode);
      setRunning(true);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const stop = async () => {
    await EchoLidarModule.stop();
    setRunning(false);
  };

  useEffect(() => {
    const sub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });
    return () => sub.remove();
  }, []);

  return { latest, running, error, isSupported, supportsDepth, start, stop };
}

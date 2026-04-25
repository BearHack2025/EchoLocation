import { useEffect, useState } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent } from 'echo-lidar';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  const start = async (mode: 'echo' | 'describe' | 'quiet' = 'describe') => {
    setError(null);
    try {
      await EchoLidarModule.start(mode);
      setRunning(true);
      try {
        await EchoLidarModule.startVoiceCommands();
        setListening(true);
      } catch (voiceError: unknown) {
        setListening(false);
        setError(voiceError instanceof Error ? voiceError.message : String(voiceError));
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const stop = async () => {
    await EchoLidarModule.stopVoiceCommands();
    setListening(false);
    await EchoLidarModule.stop();
    setRunning(false);
  };

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    return () => {
      echoSub.remove();
      voiceSub.remove();
    };
  }, []);

  return { latest, latestCommand, running, listening, error, isSupported, supportsDepth, start, stop };
}

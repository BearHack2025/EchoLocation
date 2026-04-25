import { useEffect, useState, useCallback } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent } from 'echo-lidar';
import { speakWithFallback, type SpeechMode } from '@/services/audio-service';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  const handleSpeechRequest = useCallback(async (event: { text: string; mode: string }) => {
    const { text, mode } = event;

    try {
      const audioUrl = await speakWithFallback(text, mode as SpeechMode);

      if (audioUrl === 'fallback') {
        EchoLidarModule.onSpeechFailed('Builtin TTS fallback');
        return;
      }

      await EchoLidarModule.onSpeechReady(audioUrl, (success, err) => {
        if (!success) {
          console.warn('[Audio] Audio playback failed:', err);
          EchoLidarModule.onSpeechFailed(err ?? 'Playback failed');
        }
      });
    } catch (e) {
      console.warn('[Audio] TTS failed, using builtin TTS:', e);
      EchoLidarModule.onSpeechFailed(e instanceof Error ? e.message : String(e));
    }
  }, []);

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

    const speechSub = EchoLidarEmitter.addListener('onSpeechRequest', handleSpeechRequest);

    return () => {
      echoSub.remove();
      voiceSub.remove();
      speechSub.remove();
    };
  }, [handleSpeechRequest]);

  return { latest, latestCommand, running, listening, error, isSupported, supportsDepth, start, stop };
}
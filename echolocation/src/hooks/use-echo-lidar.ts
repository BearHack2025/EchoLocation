import { useEffect, useState } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type {
  EchoUpdate,
  GemmaModelStatus,
  ThermalStateEvent,
  VoiceCommandEvent,
} from 'echo-lidar';

import { elevenLabsPlayer } from '@/services/elevenlabs-player';

export type { EchoUpdate };

/// Manual Start/Stop control for the LiDAR session.
/// - `start()` runs the AR session AND unmutes the danger-speech path so the
///   event-driven Gemma detector can dispatch warnings via ElevenLabs.
/// - `stop()` cancels in-flight TTS, mutes the speech path, and pauses the
///   AR session — the app goes fully silent.
///
/// Speech itself is handled by `danger-speech-bridge.ts` which subscribes to
/// `onDangerSpeech` events and plays via ElevenLabs only.
export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [modelStatus, setModelStatus] = useState<GemmaModelStatus>(() =>
    EchoLidarModule.getModelStatus()
  );
  const [thermal, setThermal] = useState<ThermalStateEvent>(() => ({
    state: (EchoLidarModule.getThermalState() as ThermalStateEvent['state']) ?? 'nominal',
    throttled: false,
  }));

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  const start = async (mode: 'echo' | 'describe' | 'quiet' = 'describe') => {
    setError(null);
    // Defensive: cancel any leftover playback from a prior session.
    elevenLabsPlayer.stop();
    try {
      await EchoLidarModule.start(mode);
      // Unmute so the event-driven danger detector can dispatch summaries
      // (which the danger-speech bridge plays via ElevenLabs).
      try {
        (EchoLidarModule as unknown as { setVoiceModeMuted?: (m: boolean) => void })
          .setVoiceModeMuted?.(false);
      } catch {}
      setRunning(true);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const stop = async () => {
    // Order: cancel TTS first → mute the speech path → pause LiDAR.
    // This keeps an in-flight summary from sneaking through after stop().
    elevenLabsPlayer.stop();
    try {
      (EchoLidarModule as unknown as { setVoiceModeMuted?: (m: boolean) => void })
        .setVoiceModeMuted?.(true);
    } catch {}
    await EchoLidarModule.stop();
    setRunning(false);
  };

  const downloadModel = async () => {
    try {
      await EchoLidarModule.downloadModel();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const cancelModelDownload = async () => {
    await EchoLidarModule.cancelDownload();
  };

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    const modelSub = EchoLidarEmitter.addListener('onModelStatus', (event) => {
      setModelStatus(event);
    });

    const thermalSub = EchoLidarEmitter.addListener('onThermalState', (event) => {
      setThermal(event);
    });

    return () => {
      echoSub.remove();
      voiceSub.remove();
      modelSub.remove();
      thermalSub.remove();
    };
  }, []);

  return {
    latest,
    latestCommand,
    running,
    error,
    isSupported,
    supportsDepth,
    modelStatus,
    thermal,
    start,
    stop,
    downloadModel,
    cancelModelDownload,
  };
}

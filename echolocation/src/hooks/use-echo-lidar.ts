import { useEffect, useState } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, SceneLabelResult, SnapshotCapture, VoiceCommandEvent } from 'echo-lidar';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [latestSnapshot, setLatestSnapshot] = useState<SnapshotCapture | null>(null);
  const [latestSceneLabels, setLatestSceneLabels] = useState<SceneLabelResult['labels']>([]);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [capturing, setCapturing] = useState(false);
  const [analyzing, setAnalyzing] = useState(false);
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

  const captureSnapshot = async () => {
    setError(null);
    setCapturing(true);
    try {
      const snapshot = await EchoLidarModule.captureSnapshot();
      setLatestSnapshot(snapshot);
      setLatestSceneLabels([]);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setCapturing(false);
    }
  };

  const analyzeScene = async () => {
    setError(null);
    setAnalyzing(true);
    try {
      const result = await EchoLidarModule.captureAndLabelScene();
      setLatestSnapshot(result.snapshot);
      setLatestSceneLabels(result.labels);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setAnalyzing(false);
    }
  };

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
      setLatestSceneLabels(event.visionLabels ?? []);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    return () => {
      echoSub.remove();
      voiceSub.remove();
    };
  }, []);

  return {
    latest,
    latestCommand,
    latestSnapshot,
    latestSceneLabels,
    running,
    listening,
    capturing,
    analyzing,
    error,
    isSupported,
    supportsDepth,
    start,
    stop,
    captureSnapshot,
    analyzeScene,
  };
}

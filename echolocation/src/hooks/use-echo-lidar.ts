import { useEffect, useState, useCallback, useRef } from 'react';
import { createAudioPlayer, type AudioPlayer } from 'expo-audio';
import * as Speech from 'expo-speech';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent, EchoMode } from 'echo-lidar';
import {
  configureAudioService,
  speakWithFallback,
  isElevenLabsConfigured,
  type SpeechMode,
} from '@/services/audio-service';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [mode, setMode] = useState<EchoMode>('describe');
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [useBuiltin, setUseBuiltin] = useState(false);

  const playerRef = useRef<AudioPlayer | null>(null);
  const speechReleaseRef = useRef<((ok: boolean, message?: string) => void) | null>(null);
  const lastSpokenTextRef = useRef<string | null>(null);
  const lastHandledCommandTimestampRef = useRef<number>(0);
  const autoStartAttemptedRef = useRef(false);

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  useEffect(() => {
    configureAudioService({
      useElevenLabs: true,
      useFallback: false,
      preferBuiltinForContinuous: false,
    });

    return () => {
      const releaseSpeech = speechReleaseRef.current;
      speechReleaseRef.current = null;
      if (releaseSpeech) {
        releaseSpeech(false, 'Playback interrupted');
      }
      if (playerRef.current) {
        playerRef.current.remove();
        playerRef.current = null;
      }
    };
  }, []);

  const playAudioUrl = useCallback(async (audioUrl: string): Promise<void> => {
    const previousRelease = speechReleaseRef.current;
    speechReleaseRef.current = null;
    if (previousRelease) {
      previousRelease(false, 'Playback interrupted');
    }
    if (playerRef.current) {
      playerRef.current.remove();
      playerRef.current = null;
    }

    const player = createAudioPlayer(audioUrl);
    playerRef.current = player;

    let released = false;
    const releaseGate = (ok: boolean, message?: string) => {
      if (released) return;
      released = true;
      if (speechReleaseRef.current === releaseGate) {
        speechReleaseRef.current = null;
      }
      if (ok) {
        EchoLidarModule.onSpeechReady(audioUrl).catch(() => {});
      } else {
        EchoLidarModule.onSpeechFailed(message).catch(() => {});
      }
    };
    speechReleaseRef.current = releaseGate;

    player.addListener('playbackStatusUpdate', (status) => {
      const playbackStatus = status as {
        isLoaded?: boolean;
        didJustFinish?: boolean;
        error?: string;
      };

      if (playbackStatus.error) {
        console.error('[Audio] ElevenLabs playback failed:', playbackStatus.error);
        setError(`ElevenLabs playback failed: ${playbackStatus.error}`);
        releaseGate(false, playbackStatus.error);
        if (playerRef.current === player) {
          playerRef.current.remove();
          playerRef.current = null;
        } else {
          player.remove();
        }
      }

      if (playbackStatus.isLoaded && playbackStatus.didJustFinish) {
        releaseGate(true);
        if (playerRef.current === player) {
          playerRef.current.remove();
          playerRef.current = null;
        } else {
          player.remove();
        }
      }
    });

    try {
      await player.play();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setError(`ElevenLabs playback failed: ${message}`);
      releaseGate(false, message);
      if (playerRef.current === player) {
        playerRef.current.remove();
        playerRef.current = null;
      } else {
        player.remove();
      }
    }
  }, []);

  const handleSpeechRequest = useCallback(async (event: { text: string; mode: string }) => {
    const { text, mode } = event;
    lastSpokenTextRef.current = text;

    try {
      const audioUrl = await speakWithFallback(text, mode as SpeechMode);
      await playAudioUrl(audioUrl);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn('[Audio] ElevenLabs TTS failed:', e);
      setError(`ElevenLabs voice failed: ${message}`);
      EchoLidarModule.onSpeechFailed(message).catch(() => {});
    }
  }, [playAudioUrl]);

  const buildLatestSummary = useCallback((update: EchoUpdate | null): string => {
    if (!update || update.nearestDistanceMeters == null) {
      return 'Nothing detected right now.';
    }

    if (update.recognizedText) {
      const dir = update.direction === 'center' ? 'ahead' : `to your ${update.direction}`;
      return `Text ${dir}. ${update.recognizedText}`;
    }

    let distance = 'unknown distance';
    if (update.nearestDistanceMeters < 1.0) {
      distance = 'very close';
    } else if (update.nearestDistanceMeters < 2.0) {
      distance = `${Math.round(update.nearestDistanceMeters * 10) / 10} meters`;
    } else {
      distance = `${Math.round(update.nearestDistanceMeters)} meters`;
    }

    if (update.direction === 'center') {
      return `${update.label} ahead, ${distance}`;
    }

    return `${update.label} to your ${update.direction}, ${distance}`;
  }, []);

  const stopSession = useCallback(async () => {
    await EchoLidarModule.stopVoiceCommands();
    setListening(false);
    const releaseSpeech = speechReleaseRef.current;
    speechReleaseRef.current = null;
    if (releaseSpeech) {
      releaseSpeech(false, 'Playback interrupted');
    }
    if (playerRef.current) {
      playerRef.current.remove();
      playerRef.current = null;
    }
    await EchoLidarModule.stop();
  }, []);

  const start = useCallback(async (nextMode: EchoMode = 'describe') => {
    const shouldUseBuiltin = !isElevenLabsConfigured();
    setError(null);
    setUseBuiltin(shouldUseBuiltin);
    try {
      if (running) {
        await stopSession();
      }

      await EchoLidarModule.start(nextMode, shouldUseBuiltin);
      setMode(nextMode);
      setRunning(true);

      if (nextMode === 'describe') {
        try {
          await EchoLidarModule.startVoiceCommands(true);
          setListening(true);
        } catch (voiceError: unknown) {
          setListening(false);
          setError(voiceError instanceof Error ? voiceError.message : String(voiceError));
        }
      } else {
        await EchoLidarModule.stopVoiceCommands();
        setListening(false);
      }
    } catch (e: unknown) {
      setMode('describe');
      setRunning(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [running, stopSession]);

  const stop = useCallback(async () => {
    await stopSession();
    setRunning(false);
    setMode('describe');
  }, [stopSession]);

  const speakCommand = useCallback(async (text: string): Promise<boolean> => {
    lastSpokenTextRef.current = text;
    if (useBuiltin || !isElevenLabsConfigured()) {
      Speech.stop();
      Speech.speak(text, { language: 'en-US', rate: 0.5, pitch: 1.0 });
      return true;
    }

    try {
      const audioUrl = await speakWithFallback(text, 'describe');
      await playAudioUrl(audioUrl);
      return true;
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn('[Audio] Voice command TTS failed:', e);
      Speech.stop();
      Speech.speak(text, { language: 'en-US', rate: 0.5, pitch: 1.0 });
      setError(`ElevenLabs voice failed: ${message}`);
      return true;
    }
  }, [playAudioUrl, useBuiltin]);

  useEffect(() => {
    if (!latestCommand) {
      return;
    }

    if (latestCommand.timestampMs <= lastHandledCommandTimestampRef.current) {
      return;
    }

    lastHandledCommandTimestampRef.current = latestCommand.timestampMs;

    void (async () => {
      switch (latestCommand.command) {
      case 'repeat': {
        const phrase = lastSpokenTextRef.current ?? 'Nothing to repeat yet.';
        await speakCommand(phrase);
        break;
      }
      case 'ahead':
        await speakCommand(buildLatestSummary(latest));
        break;
      case 'describe_mode':
        if (!running || mode !== 'describe') {
          await start('describe');
        }
        await speakCommand('Describe mode enabled.');
        break;
      case 'quiet_mode':
        if (!running || mode !== 'quiet') {
          await start('quiet');
        }
        await speakCommand('Quiet mode enabled.');
        break;
      case 'stop':
        await stop();
        break;
      default:
        break;
      }
    })();
  }, [latestCommand, latest, mode, running, speakCommand, start, stop, buildLatestSummary]);

  useEffect(() => {
    if (autoStartAttemptedRef.current || running || !isSupported || !supportsDepth) {
      return;
    }

    autoStartAttemptedRef.current = true;
    void start('describe');
  }, [isSupported, running, start, supportsDepth]);

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    if (!useBuiltin) {
      const speechSub = EchoLidarEmitter.addListener('onSpeechRequest', handleSpeechRequest);
      return () => {
        echoSub.remove();
        voiceSub.remove();
        speechSub.remove();
      };
    }

    return () => {
      echoSub.remove();
      voiceSub.remove();
    };
  }, [handleSpeechRequest, useBuiltin]);

  return { latest, latestCommand, mode, running, listening, error, isSupported, supportsDepth, start, stop, speakCommand, useBuiltin };
}

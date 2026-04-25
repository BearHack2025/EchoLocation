import { useEffect, useState, useCallback, useRef } from 'react';
import { createAudioPlayer, type AudioPlayer } from 'expo-audio';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent, AudioChunkEvent, VoiceCommandName } from 'echo-lidar';
import {
  configureAudioService,
  speakWithFallback,
  startRealtimeSTT,
  stopRealtimeSTT,
  sendSTTAudioChunk,
  commitSTT,
  isElevenSttConfigured,
  isElevenLabsConfigured,
  type SpeechMode,
} from '@/services/audio-service';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [useBuiltin, setUseBuiltin] = useState(false);
  const [elevenSttActive, setElevenSttActive] = useState(false);

  const sttReadyRef = useRef(false);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playerRef = useRef<AudioPlayer | null>(null);
  const SILENCE_THRESHOLD_MS = 800;

  const isSupported = EchoLidarModule.isSupported();
  const supportsDepth = EchoLidarModule.supportsDepth();

  useEffect(() => {
    configureAudioService({
      useElevenLabs: true,
      useFallback: false,
      preferBuiltinForContinuous: false,
    });

    return () => {
      if (playerRef.current) {
        playerRef.current.remove();
        playerRef.current = null;
      }
    };
  }, []);

  const playAudioUrl = useCallback(async (audioUrl: string): Promise<void> => {
    if (playerRef.current) {
      playerRef.current.remove();
      playerRef.current = null;
    }

    const player = createAudioPlayer(audioUrl);
    playerRef.current = player;

    player.addListener('playbackStatusUpdate', (status) => {
      const playbackStatus = status as {
        isLoaded?: boolean;
        didJustFinish?: boolean;
        error?: string;
      };

      if (playbackStatus.error) {
        console.error('[Audio] ElevenLabs playback failed:', playbackStatus.error);
        setError(`ElevenLabs playback failed: ${playbackStatus.error}`);
      }

      if (playbackStatus.isLoaded && playbackStatus.didJustFinish) {
        playerRef.current?.remove();
        playerRef.current = null;
      }
    });

    player.play();
  }, []);

  const handleSpeechRequest = useCallback(async (event: { text: string; mode: string }) => {
    const { text, mode } = event;

    try {
      const audioUrl = await speakWithFallback(text, mode as SpeechMode);
      await playAudioUrl(audioUrl);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn('[Audio] ElevenLabs TTS failed:', e);
      setError(`ElevenLabs voice failed: ${message}`);
      EchoLidarModule.onSpeechFailed(message);
    }
  }, [playAudioUrl]);

  const startElevenStt = useCallback(async () => {
    if (!isElevenSttConfigured()) {
      setError('ElevenLabs speech-to-text is not configured. Set EXPO_PUBLIC_ELEVENLABS_API_KEY.');
      return false;
    }

    try {
      await startRealtimeSTT({
        onTranscript: (text, isFinal) => {
          if (isFinal && text.trim()) {
            const command = extractCommand(text);
            if (command) {
              console.log('[STT] ElevenLabs command:', command, 'from:', text);
              setLatestCommand({
                command,
                transcript: text.toLowerCase().trim(),
                timestampMs: Date.now(),
                source: 'elevenlabs',
              });
            }
          }
        },
        onError: (error) => {
          console.warn('[STT] ElevenLabs error:', error);
          setElevenSttActive(false);
          setError(`ElevenLabs speech-to-text failed: ${error}`);
        },
        onConnected: () => {
          console.log('[STT] ElevenLabs connected');
          setElevenSttActive(true);
          sttReadyRef.current = true;
        },
        onDisconnected: () => {
          console.log('[STT] ElevenLabs disconnected');
          setElevenSttActive(false);
          sttReadyRef.current = false;
        },
      });
      return true;
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn('[STT] Failed to start ElevenLabs:', e);
      setError(`ElevenLabs speech-to-text failed: ${message}`);
      return false;
    }
  }, []);

  const extractCommand = (text: string): VoiceCommandName | null => {
    const lower = text.toLowerCase();
    if (lower.includes('repeat')) return 'repeat';
    if (lower.includes('left')) return 'left';
    if (lower.includes('right')) return 'right';
    if (lower.includes('ahead') || lower.includes("what's ahead") || lower.includes('what is ahead') || lower.includes('in front')) return 'ahead';
    return null;
  };

  const start = async (mode: 'echo' | 'describe' | 'quiet' = 'describe') => {
    if (!isElevenLabsConfigured() || !isElevenSttConfigured()) {
      setError('ElevenLabs is required. Set EXPO_PUBLIC_ELEVENLABS_API_KEY to enable voice and speech-to-text.');
      setUseBuiltin(false);
      return;
    }

    setError(null);
    setUseBuiltin(false);
    try {
      await EchoLidarModule.start(mode, false);
      setRunning(true);
      try {
        await EchoLidarModule.startVoiceCommands(false);
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
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }
    await EchoLidarModule.stopVoiceCommands();
    setListening(false);
    stopRealtimeSTT();
    setElevenSttActive(false);
    sttReadyRef.current = false;
    if (playerRef.current) {
      playerRef.current.remove();
      playerRef.current = null;
    }
    await EchoLidarModule.stop();
    setRunning(false);
  };

  const speakCommand = useCallback(async (text: string): Promise<boolean> => {
    try {
      const audioUrl = await speakWithFallback(text, 'describe');
      await playAudioUrl(audioUrl);
      return true;
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn('[Audio] Voice command TTS failed:', e);
      setError(`ElevenLabs voice failed: ${message}`);
      return false;
    }
  }, [playAudioUrl]);

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    const audioChunkSub = EchoLidarEmitter.addListener('onAudioChunk', (event: AudioChunkEvent) => {
      if (sttReadyRef.current && elevenSttActive) {
        const byteArray = Uint8Array.from(event.data);
        const int16Array = new Int16Array(
          byteArray.buffer,
          byteArray.byteOffset,
          Math.floor(byteArray.byteLength / Int16Array.BYTES_PER_ELEMENT)
        );
        sendSTTAudioChunk(int16Array);

        if (silenceTimerRef.current) {
          clearTimeout(silenceTimerRef.current);
        }
        silenceTimerRef.current = setTimeout(() => {
          commitSTT();
        }, SILENCE_THRESHOLD_MS);
      }
    });

    let sttStartupTimeout: ReturnType<typeof setTimeout> | null = null;

    const startSttIfConfigured = async () => {
      if (!useBuiltin && isElevenSttConfigured()) {
        sttStartupTimeout = setTimeout(async () => {
          await startElevenStt();
        }, 500);
      }
    };

    startSttIfConfigured();

    if (!useBuiltin) {
      const speechSub = EchoLidarEmitter.addListener('onSpeechRequest', handleSpeechRequest);
      return () => {
        echoSub.remove();
        voiceSub.remove();
        audioChunkSub.remove();
        speechSub.remove();
        if (sttStartupTimeout) clearTimeout(sttStartupTimeout);
      };
    }

    return () => {
      echoSub.remove();
      voiceSub.remove();
      audioChunkSub.remove();
      if (sttStartupTimeout) clearTimeout(sttStartupTimeout);
    };
  }, [handleSpeechRequest, useBuiltin, elevenSttActive, startElevenStt]);

  return { latest, latestCommand, running, listening, error, isSupported, supportsDepth, start, stop, speakCommand, useBuiltin };
}

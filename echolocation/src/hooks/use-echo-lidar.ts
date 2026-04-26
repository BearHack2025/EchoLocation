import { useEffect, useState, useCallback, useRef } from 'react';
import { createAudioPlayer, type AudioPlayer } from 'expo-audio';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent, AudioChunkEvent, VoiceCommandName, EchoMode } from 'echo-lidar';
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
  const [mode, setMode] = useState<EchoMode | null>(null);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [useBuiltin, setUseBuiltin] = useState(false);
  const [elevenSttActive, setElevenSttActive] = useState(false);

  const sttReadyRef = useRef(false);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playerRef = useRef<AudioPlayer | null>(null);
  const speechReleaseRef = useRef<((ok: boolean, message?: string) => void) | null>(null);
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

  const stopSession = useCallback(async () => {
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }
    await EchoLidarModule.stopVoiceCommands();
    setListening(false);
    stopRealtimeSTT();
    setElevenSttActive(false);
    sttReadyRef.current = false;
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

  const start = async (nextMode: EchoMode = 'echo') => {
    if (!isElevenLabsConfigured() || !isElevenSttConfigured()) {
      setError('ElevenLabs is required. Set EXPO_PUBLIC_ELEVENLABS_API_KEY to enable voice and speech-to-text.');
      setUseBuiltin(false);
      return;
    }

    setError(null);
    setUseBuiltin(false);
    try {
      if (running) {
        await stopSession();
      }

      await EchoLidarModule.start(nextMode, false);
      setMode(nextMode);
      setRunning(true);
      try {
        await EchoLidarModule.startVoiceCommands(false);
        setListening(true);
      } catch (voiceError: unknown) {
        setListening(false);
        setError(voiceError instanceof Error ? voiceError.message : String(voiceError));
      }
    } catch (e: unknown) {
      setMode(null);
      setRunning(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const stop = async () => {
    await stopSession();
    setRunning(false);
    setMode(null);
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

  return { latest, latestCommand, mode, running, listening, error, isSupported, supportsDepth, start, stop, speakCommand, useBuiltin };
}

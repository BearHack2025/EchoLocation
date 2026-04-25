import { useEffect, useState, useCallback, useRef } from 'react';

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent, AudioChunkEvent, VoiceCommandName } from 'echo-lidar';
import { speakWithFallback, startRealtimeSTT, stopRealtimeSTT, sendSTTAudioChunk, commitSTT, isElevenSttConfigured, type SpeechMode } from '@/services/audio-service';
import * as Speech from 'expo-speech';

export type { EchoUpdate };

export function useEchoLidar() {
  const [latest, setLatest] = useState<EchoUpdate | null>(null);
  const [latestCommand, setLatestCommand] = useState<VoiceCommandEvent | null>(null);
  const [running, setRunning] = useState(false);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [useBuiltin, setUseBuiltin] = useState(true);
  const [elevenSttActive, setElevenSttActive] = useState(false);

  const sttReadyRef = useRef(false);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const SILENCE_THRESHOLD_MS = 800;

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

  const startElevenStt = useCallback(async () => {
    if (!isElevenSttConfigured()) {
      console.log('[STT] ElevenLabs not configured, using built-in');
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
      console.warn('[STT] Failed to start ElevenLabs:', e);
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

  const start = async (mode: 'echo' | 'describe' | 'quiet' = 'describe', useBuiltinSpeech: boolean = true) => {
    setError(null);
    setUseBuiltin(useBuiltinSpeech);
    try {
      await EchoLidarModule.start(mode, useBuiltinSpeech);
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
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }
    await EchoLidarModule.stopVoiceCommands();
    setListening(false);
    stopRealtimeSTT();
    setElevenSttActive(false);
    sttReadyRef.current = false;
    await EchoLidarModule.stop();
    setRunning(false);
  };

  const speakCommand = useCallback(async (text: string): Promise<boolean> => {
    try {
      const audioUrl = await speakWithFallback(text, 'describe');
      if (audioUrl === 'fallback') {
        await Speech.speak(text, { language: 'en-US', rate: 0.9 });
        return true;
      }
      await EchoLidarModule.onSpeechReady(audioUrl, () => {});
      return true;
    } catch (e) {
      console.warn('[Audio] Voice command TTS failed:', e);
      await Speech.speak(text, { language: 'en-US', rate: 0.9 });
      return false;
    }
  }, []);

  useEffect(() => {
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (event) => {
      setLatest(event);
    });

    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (event) => {
      setLatestCommand(event);
    });

    const audioChunkSub = EchoLidarEmitter.addListener('onAudioChunk', (event: AudioChunkEvent) => {
      if (sttReadyRef.current && elevenSttActive) {
        const int16Array = new Int16Array(event.data);
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
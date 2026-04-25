import * as Speech from 'expo-speech';

import {
  speak as elevenSpeak,
  isConfigured as isElevenTtsConfigured,
  clearCache as clearElevenCache,
  type ElevenLabsTTSConfig,
  type ElevenLabsTTSResponse,
} from './elevenlabsTts';
import {
  connectRealtimeSTT,
  isConnected,
  transcribe as elevenTranscribe,
  isConfigured as isElevenSttConfigured,
  type ElevenLabsSTTConfig,
  type ElevenLabsSTTResponse,
} from './elevenlabsStt';
import {
  logAudioSuccess,
  logAudioError,
  logFallback,
  logBuiltinFallback,
  logAudioRequest,
} from './audio-logger';

export { isConfigured as isElevenLabsConfigured } from './elevenlabsTts';
export { ElevenLabsError } from './elevenlabsTts';
export { isConfigured as isElevenSttConfigured } from './elevenlabsStt';
export type { ElevenLabsTTSConfig } from './elevenlabsTts';
export type { ElevenLabsSTTConfig } from './elevenlabsStt';

export type SpeechMode = 'echo' | 'describe';

const ELEVENLABS_VOICE_IDS: Record<SpeechMode, string> = {
  echo: '21m00Tcm4TlvDq8ikWAM',
  describe: 'EXw4nqY7xTfnS2A7P8xL',
};

const SPEECH_TIMEOUT_MS = 5000;

export interface AudioServiceConfig {
  useElevenLabs?: boolean;
  useFallback?: boolean;
  preferBuiltinForContinuous?: boolean;
}

const defaultConfig: AudioServiceConfig = {
  useElevenLabs: true,
  useFallback: true,
  preferBuiltinForContinuous: true,
};

let currentConfig: AudioServiceConfig = { ...defaultConfig };

export const configureAudioService = (config: Partial<AudioServiceConfig>): void => {
  currentConfig = { ...defaultConfig, ...config };
};

export const getAudioServiceConfig = (): AudioServiceConfig => {
  return { ...currentConfig };
};

export const shouldUseBuiltinForContinuous = (): boolean => {
  return currentConfig.preferBuiltinForContinuous ?? true;
};

export const shouldUseElevenLabs = (context: 'continuous' | 'command' | 'announcement' = 'continuous'): boolean => {
  if (!currentConfig.useElevenLabs || !isElevenTtsConfigured()) {
    return false;
  }

  if (currentConfig.preferBuiltinForContinuous && context === 'continuous') {
    return false;
  }

  return true;
};

export const speak = async (
  text: string,
  config?: Partial<ElevenLabsTTSConfig>
): Promise<ElevenLabsTTSResponse | null> => {
  if (currentConfig.useElevenLabs && isElevenTtsConfigured()) {
    try {
      const startTime = Date.now();
      logAudioRequest('elevenlabs-tts', text);
      const result = await elevenSpeak(text, config);
      const latency = Date.now() - startTime;
      logAudioSuccess('elevenlabs-tts', text, latency);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logAudioError('elevenlabs-tts', message, text);
      console.warn('ElevenLabs TTS failed, trying fallback:', error);
    }
  }

  if (currentConfig.useFallback) {
    return null;
  }

  throw new Error('TTS failed and fallback disabled');
};

export const speakWithFallback = async (
  text: string,
  mode: SpeechMode = 'echo'
): Promise<string> => {
  const voiceId = ELEVENLABS_VOICE_IDS[mode];

  if (currentConfig.useElevenLabs && isElevenTtsConfigured()) {
    const startTime = Date.now();
    logAudioRequest('elevenlabs-tts', text, mode);

    try {
      const result = await withTimeout(
        elevenSpeak(text, { voiceId }),
        SPEECH_TIMEOUT_MS,
        'ElevenLabs request timeout'
      );

      if (result.audioUrl) {
        const latency = Date.now() - startTime;
        logAudioSuccess('elevenlabs-tts', text, latency, mode);
        return result.audioUrl;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logAudioError('elevenlabs-tts', message, text, mode);
      logFallback('elevenlabs-tts', text, message, mode);
      console.warn('ElevenLabs TTS failed, falling back to expo-speech:', error);
    }
  }

  if (currentConfig.useFallback) {
    logBuiltinFallback(text, 'ElevenLabs not configured or request failed', mode);
    return 'fallback';
  }

  throw new Error('All TTS methods failed');
};

export const speakBuiltinOnly = async (
  text: string,
  mode: SpeechMode = 'echo'
): Promise<string> => {
  logBuiltinFallback(text, 'explicit builtin request', mode);
  return 'fallback';
};

export const transcribe = async (
  audioBlob: Blob,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse | null> => {
  if (currentConfig.useElevenLabs && isElevenSttConfigured()) {
    try {
      const startTime = Date.now();
      logAudioRequest('elevenlabs-stt', 'audio transcription');
      const result = await elevenTranscribe(audioBlob, config);
      const latency = Date.now() - startTime;
      logAudioSuccess('elevenlabs-stt', result.text, latency);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logAudioError('elevenlabs-stt', message);
      console.warn('ElevenLabs STT failed, trying fallback:', error);
    }
  }

  if (currentConfig.useFallback) {
    return null;
  }

  throw new Error('STT failed and fallback disabled');
};

export const stopSpeaking = async (): Promise<void> => {
  Speech.stop();
};

export const clearAudioCache = (): void => {
  clearElevenCache();
};

export interface RealtimeSTTCallbacks {
  onTranscript?: (text: string, isFinal: boolean) => void;
  onError?: (error: string) => void;
  onConnected?: () => void;
  onDisconnected?: () => void;
}

let sttConnection: Awaited<ReturnType<typeof connectRealtimeSTT>> | null = null;

export const startRealtimeSTT = async (
  callbacks: RealtimeSTTCallbacks
): Promise<boolean> => {
  if (!currentConfig.useElevenLabs || !isElevenSttConfigured()) {
    logBuiltinFallback('STT', 'ElevenLabs STT not configured', 'describe');
    return false;
  }

  try {
    sttConnection = await connectRealtimeSTT({
      callbacks: {
        onTranscript: callbacks.onTranscript,
        onError: (error) => {
          logAudioError('elevenlabs-stt', error);
          callbacks.onError?.(error);
        },
        onConnected: () => {
          logAudioSuccess('elevenlabs-stt', 'realtime connected', 0);
          callbacks.onConnected?.();
        },
        onDisconnected: () => {
          callbacks.onDisconnected?.();
        },
      },
    });
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logAudioError('elevenlabs-stt', message);
    logBuiltinFallback('STT', message, 'describe');
    return false;
  }
};

export const sendSTTAudioChunk = (audioData: Int16Array): void => {
  if (sttConnection) {
    sttConnection.sendAudioChunk(audioData);
  }
};

export const commitSTT = (): void => {
  if (sttConnection) {
    sttConnection.commit();
  }
};

export const stopRealtimeSTT = (): void => {
  if (sttConnection) {
    sttConnection.disconnect();
    sttConnection = null;
  }
};

export const isSTTConnected = (): boolean => {
  return isConnected();
};

function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  timeoutMessage: string
): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs)
    ),
  ]);
}

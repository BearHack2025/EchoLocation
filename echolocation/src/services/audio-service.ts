import * as Speech from 'expo-speech';

import {
  speak as elevenSpeak,
  isConfigured as isElevenTtsConfigured,
  clearCache as clearElevenCache,
  type ElevenLabsTTSConfig,
  type ElevenLabsTTSResponse,
} from './elevenlabsTts';
import {
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
}

const defaultConfig: AudioServiceConfig = {
  useElevenLabs: true,
  useFallback: true,
};

let currentConfig: AudioServiceConfig = { ...defaultConfig };

export const configureAudioService = (config: Partial<AudioServiceConfig>): void => {
  currentConfig = { ...defaultConfig, ...config };
};

export const getAudioServiceConfig = (): AudioServiceConfig => {
  return { ...currentConfig };
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
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

export { isConfigured as isElevenLabsConfigured } from './elevenlabsTts';
export { ElevenLabsError } from './elevenlabsTts';
export type { ElevenLabsTTSConfig } from './elevenlabsTts';
export type { ElevenLabsSTTConfig } from './elevenlabsStt';

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
      const result = await elevenSpeak(text, config);
      return result;
    } catch (error) {
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
  config?: Partial<ElevenLabsTTSConfig>
): Promise<string> => {
  if (currentConfig.useElevenLabs && isElevenTtsConfigured()) {
    try {
      const result = await elevenSpeak(text, config);
      if (result.audioUrl) {
        return result.audioUrl;
      }
    } catch (error) {
      console.warn('ElevenLabs TTS failed, falling back to expo-speech:', error);
    }
  }

  if (currentConfig.useFallback) {
    return new Promise<string>((resolve) => {
      Speech.speak(text, {
        language: 'en-US',
        pitch: 1.0,
        rate: 0.9,
        onDone: () => resolve('fallback'),
        onError: () => resolve('fallback'),
      });
    });
  }

  throw new Error('All TTS methods failed');
};

export const transcribe = async (
  audioBlob: Blob,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse | null> => {
  if (currentConfig.useElevenLabs && isElevenSttConfigured()) {
    try {
      const result = await elevenTranscribe(audioBlob, config);
      return result;
    } catch (error) {
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
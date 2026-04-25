import { logAudioError, logAudioRequest, logAudioSuccess } from './audio-logger';

const ELEVENLABS_API_BASE = 'https://api.elevenlabs.io/v1';

export class ElevenLabsError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'ElevenLabsError';
  }
}

export interface ElevenLabsTTSConfig {
  apiKey: string;
  voiceId?: string;
  modelId?: string;
}

export interface ElevenLabsTTSResponse {
  audioBlob: Blob;
  audioUrl?: string;
}

const DEFAULT_VOICE_ID = '21m00Tcm4TlvDq8ikWAM';
const DEFAULT_MODEL_ID = 'elevenMono_v1';

const cachedAudio: Map<string, string> = new Map();
const MAX_CACHE_SIZE = 20;

export const getApiKey = (): string => {
  return process.env.EXPO_PUBLIC_ELEVENLABS_API_KEY || '';
};

export const isConfigured = (): boolean => {
  const key = getApiKey();
  return !!key && key.length > 0;
};

export const speak = async (
  text: string,
  config?: Partial<ElevenLabsTTSConfig>
): Promise<ElevenLabsTTSResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsError('API key not configured');
  }

  const voiceId = config?.voiceId || DEFAULT_VOICE_ID;
  const modelId = config?.modelId || DEFAULT_MODEL_ID;
  const cacheKey = `${voiceId}:${text}`;
  const cachedUrl = cachedAudio.get(cacheKey);
  if (cachedUrl) {
    return { audioUrl: cachedUrl, audioBlob: new Blob([], { type: 'audio/mp3' }) };
  }

  const startTime = Date.now();
  logAudioRequest('elevenlabs-tts', text);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch(
      `${ELEVENLABS_API_BASE}/text-to-speech/${voiceId}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'xi-api-key': apiKey,
        },
        body: JSON.stringify({
          text,
          model_id: modelId,
          voice_settings: {
            stability: 0.5,
            similarity_boost: 0.75,
          },
        }),
        signal: controller.signal,
      }
    );

    clearTimeout(timeoutId);

    if (!response.ok) {
      const error = await response.text();
      logAudioError('elevenlabs-tts', `HTTP ${response.status}: ${error}`, text);
      throw new ElevenLabsError(`API error: ${error}`, response.status);
    }

    const audioBlob = await response.blob();
    const audioUrl = URL.createObjectURL(audioBlob);

    if (cachedAudio.size >= MAX_CACHE_SIZE) {
      const firstKey = cachedAudio.keys().next().value;
      if (firstKey) {
        const oldUrl = cachedAudio.get(firstKey);
        if (oldUrl) URL.revokeObjectURL(oldUrl);
        cachedAudio.delete(firstKey);
      }
    }
    cachedAudio.set(cacheKey, audioUrl);

    const latency = Date.now() - startTime;
    logAudioSuccess('elevenlabs-tts', text, latency);

    return { audioBlob, audioUrl };
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof ElevenLabsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : 'Unknown error';
    logAudioError('elevenlabs-tts', message, text);
    throw new ElevenLabsError(`Request failed: ${message}`);
  }
};

export const speakAndPlay = async (
  text: string,
  config?: Partial<ElevenLabsTTSConfig>
): Promise<string> => {
  const result = await speak(text, config);
  if (!result.audioUrl) {
    throw new ElevenLabsError('Failed to get audio URL');
  }
  return result.audioUrl;
};

export const clearCache = (): void => {
  cachedAudio.forEach((url) => URL.revokeObjectURL(url));
  cachedAudio.clear();
};

export const availableVoices = [
  { id: '21m00Tcm4TlvDq8ikWAM', name: 'Rachel' },
  { id: 'AZnzlk1XvdvchwBnXaMl', name: 'Domi' },
  { id: 'EXw4nqY7xTfnS2A7P8xL', name: 'Arnold' },
  { id: 'MF4bmhG2ZsrAZZ7fNpB', name: 'Adam' },
  { id: 'pNInz6ob2mDXGfyi2Xv', name: 'Sam' },
];
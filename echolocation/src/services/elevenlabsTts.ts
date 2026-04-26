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
  audioUrl?: string;
}

const DEFAULT_VOICE_ID = '21m00Tcm4TlvDq8ikWAM';
const DEFAULT_MODEL_ID = 'eleven_flash_v2_5';

const cachedAudio: Map<string, string> = new Map();
const MAX_CACHE_SIZE = 20;

const inFlight: Map<string, Promise<ElevenLabsTTSResponse>> = new Map();
const lastSpokenAt: Map<string, number> = new Map();
const SAME_TEXT_COOLDOWN_MS = 3000;

export const getApiKey = (): string => {
  return process.env.EXPO_PUBLIC_ELEVENLABS_API_KEY || '';
};

export const getModelId = (): string => {
  return process.env.EXPO_PUBLIC_ELEVENLABS_MODEL_ID || DEFAULT_MODEL_ID;
};

export const isConfigured = (): boolean => {
  const key = getApiKey();
  return !!key && key.length > 0;
};

export const speak = async (
  text: string,
  config?: Partial<ElevenLabsTTSConfig>,
  signal?: AbortSignal
): Promise<ElevenLabsTTSResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsError('API key not configured');
  }

  const voiceId = config?.voiceId || DEFAULT_VOICE_ID;
  const modelId = config?.modelId || getModelId();
  const cacheKey = `${voiceId}:${text}`;
  const cachedUrl = cachedAudio.get(cacheKey);
  if (cachedUrl) {
    lastSpokenAt.set(cacheKey, Date.now());
    return { audioUrl: cachedUrl };
  }

  const inFlightPromise = inFlight.get(cacheKey);
  if (inFlightPromise) {
    return inFlightPromise;
  }

  const lastAt = lastSpokenAt.get(cacheKey);
  if (lastAt && Date.now() - lastAt < SAME_TEXT_COOLDOWN_MS) {
    throw new ElevenLabsError('Cooldown: same text spoken too recently');
  }

  const startTime = Date.now();
  logAudioRequest('elevenlabs-tts', text);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000);
  const onExternalAbort = () => controller.abort();
  if (signal) {
    if (signal.aborted) controller.abort();
    else signal.addEventListener('abort', onExternalAbort);
  }

  const requestPromise = (async (): Promise<ElevenLabsTTSResponse> => {
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
      if (signal) signal.removeEventListener('abort', onExternalAbort);

      if (!response.ok) {
        const error = await response.text();
        logAudioError('elevenlabs-tts', `HTTP ${response.status}: ${error}`, text);
        throw new ElevenLabsError(`API error: ${error}`, response.status);
      }

      const audioArrayBuffer = await response.arrayBuffer();
      const audioBase64 = arrayBufferToBase64(audioArrayBuffer);
      const audioUrl = `data:audio/mpeg;base64,${audioBase64}`;

      if (cachedAudio.size >= MAX_CACHE_SIZE) {
        const firstKey = cachedAudio.keys().next().value;
        if (firstKey) cachedAudio.delete(firstKey);
      }
      cachedAudio.set(cacheKey, audioUrl);
      lastSpokenAt.set(cacheKey, Date.now());

      const latency = Date.now() - startTime;
      logAudioSuccess('elevenlabs-tts', text, latency);

      return { audioUrl };
    } catch (error) {
      clearTimeout(timeoutId);
      if (signal) signal.removeEventListener('abort', onExternalAbort);
      if (error instanceof ElevenLabsError) throw error;
      const message = error instanceof Error ? error.message : 'Unknown error';
      logAudioError('elevenlabs-tts', message, text);
      throw new ElevenLabsError(`Request failed: ${message}`);
    } finally {
      inFlight.delete(cacheKey);
    }
  })();

  inFlight.set(cacheKey, requestPromise);
  return requestPromise;
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
  cachedAudio.clear();
};

export const availableVoices = [
  { id: '21m00Tcm4TlvDq8ikWAM', name: 'Rachel' },
  { id: 'AZnzlk1XvdvchwBnXaMl', name: 'Domi' },
  { id: 'zmcVlqmyk3Jpn5AVYcAL', name: 'Arnold' },
  { id: 'MF4bmhG2ZsrAZZ7fNpB', name: 'Adam' },
  { id: 'pNInz6ob2mDXGfyi2Xv', name: 'Sam' },
];

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    const chunk = bytes.subarray(index, index + chunkSize);
    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

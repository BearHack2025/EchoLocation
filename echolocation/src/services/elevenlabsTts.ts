import { ELEVENLABS, elevenLabsApiKey } from './elevenlabs-config';

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

const cachedAudio: Map<string, string> = new Map();
const MAX_CACHE_SIZE = 20;

export const getApiKey = (): string => elevenLabsApiKey();

export const isConfigured = (): boolean => {
  const key = getApiKey();
  return !!key && key.length > 0;
};

/**
 * Convert a `Response`'s body to a `data:audio/mpeg;base64,...` URI.
 *
 * Why: React Native does not implement `URL.createObjectURL`, so the previous
 * `blob → URL.createObjectURL` path silently threw at runtime — the orchestrator
 * then fell through to native AVSpeechSynthesizer every time. Data URIs are
 * universally accepted by `expo-audio.createAudioPlayer` and avoid `expo-file-system`.
 */
async function responseToDataUri(response: Response, mime: string): Promise<string> {
  const buffer = await response.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  // Avoid String.fromCharCode(...bytes) — large buffers blow the call stack.
  // Chunked accumulation keeps this safe up to ~10 MB.
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const slice = bytes.subarray(i, Math.min(i + CHUNK, bytes.length));
    binary += String.fromCharCode.apply(null, slice as unknown as number[]);
  }
  // `btoa` exists in RN ≥ 0.69 via the URL polyfill / Hermes. If it ever
  // doesn't, swap to a Buffer-based encoder.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base64 = (globalThis as any).btoa(binary);
  return `data:${mime};base64,${base64}`;
}

export const speak = async (
  text: string,
  config?: Partial<ElevenLabsTTSConfig>
): Promise<ElevenLabsTTSResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsError('API key not configured');
  }

  const voiceId = config?.voiceId || ELEVENLABS.voiceId;
  const modelId = config?.modelId || ELEVENLABS.ttsModel;
  const cacheKey = `${voiceId}:${modelId}:${text}`;
  const cachedUrl = cachedAudio.get(cacheKey);
  if (cachedUrl) {
    return { audioUrl: cachedUrl, audioBlob: new Blob([], { type: 'audio/mpeg' }) };
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), ELEVENLABS.ttsTimeoutMs);

  try {
    const response = await fetch(
      `${ELEVENLABS.apiBase}/text-to-speech/${voiceId}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
          'xi-api-key': apiKey,
        },
        body: JSON.stringify({
          text,
          model_id: modelId,
          voice_settings: ELEVENLABS.ttsVoiceSettings,
          output_format: ELEVENLABS.ttsOutputFormat,
        }),
        signal: controller.signal,
      }
    );

    clearTimeout(timeoutId);

    if (!response.ok) {
      const error = await response.text().catch(() => '');
      throw new ElevenLabsError(`API error: ${error}`, response.status);
    }

    const audioUrl = await responseToDataUri(response, 'audio/mpeg');

    if (cachedAudio.size >= MAX_CACHE_SIZE) {
      const firstKey = cachedAudio.keys().next().value;
      if (firstKey) {
        cachedAudio.delete(firstKey);
      }
    }
    cachedAudio.set(cacheKey, audioUrl);

    return { audioBlob: new Blob([], { type: 'audio/mpeg' }), audioUrl };
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof ElevenLabsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : 'Unknown error';
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
  cachedAudio.clear();
};

export const availableVoices = [
  { id: '21m00Tcm4TlvDq8ikWAM', name: 'Rachel' },
  { id: 'AZnzlk1XvdvchwBnXaMl', name: 'Domi' },
  { id: 'EXw4nqY7xTfnS2A7P8xL', name: 'Arnold' },
  { id: 'pNInz6obPmFL5MwgYpzn', name: 'Adam' },
  { id: 'pNInz6ob2mDXGfyi2Xv', name: 'Sam' },
];

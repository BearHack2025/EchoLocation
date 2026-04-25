import { logAudioError, logAudioRequest, logAudioSuccess } from './audio-logger';

const ELEVENLABS_API_BASE = 'https://api.elevenlabs.io/v1';

export class ElevenLabsError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'ElevenLabsError';
  }
}

export interface ElevenLabsSTTConfig {
  apiKey: string;
  modelId?: string;
}

export interface ElevenLabsSTTResponse {
  text: string;
  confidence: number;
}

const DEFAULT_MODEL_ID = 'scribe_english_%s';

export const getApiKey = (): string => {
  return process.env.EXPO_PUBLIC_ELEVENLABS_API_KEY || '';
};

export const isConfigured = (): boolean => {
  const key = getApiKey();
  return !!key && key.length > 0;
};

export const transcribe = async (
  audioBlob: Blob,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsError('API key not configured');
  }

  const modelId = config?.modelId || DEFAULT_MODEL_ID;

  const startTime = Date.now();
  logAudioRequest('elevenlabs-stt', 'audio transcription');

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000);

  try {
    const formData = new FormData();
    formData.append('file', audioBlob, 'audio.mp3');
    formData.append('model_id', modelId);

    const response = await fetch(`${ELEVENLABS_API_BASE}/scribe`, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
      },
      body: formData,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const error = await response.text();
      logAudioError('elevenlabs-stt', `HTTP ${response.status}: ${error}`);
      throw new ElevenLabsError(`API error: ${error}`, response.status);
    }

    const data = await response.json();
    const latency = Date.now() - startTime;
    logAudioSuccess('elevenlabs-stt', data.text || '', latency);

    return {
      text: data.text || '',
      confidence: data.confidence || 0,
    };
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof ElevenLabsError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : 'Unknown error';
    logAudioError('elevenlabs-stt', message);
    throw new ElevenLabsError(`Request failed: ${message}`);
  }
};

export const transcribeFromArrayBuffer = async (
  audioData: ArrayBuffer,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const blob = new Blob([audioData], { type: 'audio/mp3' });
  return transcribe(blob, config);
};

export const transcribeFromBase64 = async (
  base64Audio: string,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const binaryString = atob(base64Audio);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  const blob = new Blob([bytes], { type: 'audio/mp3' });
  return transcribe(blob, config);
};
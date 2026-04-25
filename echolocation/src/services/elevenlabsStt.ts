import { logAudioError, logAudioRequest, logAudioSuccess } from './audio-logger';

const ELEVENLABS_WS_BASE = 'wss://api.elevenlabs.io';
const ELEVENLABS_HTTP_BASE = 'https://api.elevenlabs.io/v1';

export class ElevenLabsSTTError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'ElevenLabsSTTError';
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

export interface STTCallbacks {
  onTranscript?: (text: string, isFinal: boolean) => void;
  onError?: (error: string) => void;
  onConnected?: () => void;
  onDisconnected?: () => void;
}

const DEFAULT_MODEL_ID = 'scribe_v2_realtime';
const STT_TIMEOUT_MS = 10000;

export const getApiKey = (): string => {
  return process.env.EXPO_PUBLIC_ELEVENLABS_API_KEY || '';
};

export const isConfigured = (): boolean => {
  const key = getApiKey();
  return !!key && key.length > 0;
};

class ElevenLabsSTTConnection {
  private ws: WebSocket | null = null;
  private apiKey: string;
  private modelId: string;
  private callbacks: STTCallbacks;
  private connected = false;
  private sessionId: string | null = null;
  private timeoutId: ReturnType<typeof setTimeout> | null = null;

  constructor(apiKey: string, modelId: string, callbacks: STTCallbacks) {
    this.apiKey = apiKey;
    this.modelId = modelId;
    this.callbacks = callbacks;
  }

  async connect(): Promise<void> {
    const startTime = Date.now();
    logAudioRequest('elevenlabs-stt', 'connecting');

    return new Promise((resolve, reject) => {
      const url = `${ELEVENLABS_WS_BASE}?api_key=${this.apiKey}&model_id=${this.modelId}`;

      this.timeoutId = setTimeout(() => {
        reject(new ElevenLabsSTTError('Connection timeout'));
      }, STT_TIMEOUT_MS);

      this.ws = new WebSocket(url);

      this.ws.onopen = () => {
        if (this.timeoutId) {
          clearTimeout(this.timeoutId);
        }
        this.timeoutId = setTimeout(() => {
          if (!this.connected) {
            this.disconnect();
            reject(new Error('Connection timeout'));
          }
        }, STT_TIMEOUT_MS);
      };

      this.ws.onmessage = (event) => {
        this.handleMessage(event.data);
      };

      this.ws.onerror = (error) => {
        if (this.timeoutId) {
          clearTimeout(this.timeoutId);
        }
        const message = 'WebSocket error';
        logAudioError('elevenlabs-stt', message);
        this.callbacks.onError?.(message);
        reject(new ElevenLabsSTTError(message));
      };

      this.ws.onclose = (event) => {
        if (this.timeoutId) {
          clearTimeout(this.timeoutId);
          this.timeoutId = null;
        }
        this.connected = false;
        this.callbacks.onDisconnected?.();
        if (event.code !== 1000) {
          logAudioError('elevenlabs-stt', `Connection closed: ${event.code} ${event.reason}`);
        }
      };
    });
  }

  private handleMessage(data: string) {
    try {
      const message = JSON.parse(data);

      switch (message.type) {
        case 'session_start':
          this.connected = true;
          this.sessionId = message.session_id;
          const latency = Date.now();
          logAudioSuccess('elevenlabs-stt', 'connected', latency);
          this.callbacks.onConnected?.();
          break;

        case 'partial_transcript':
          this.callbacks.onTranscript?.(message.text, false);
          break;

        case 'transcript':
          this.callbacks.onTranscript?.(message.text, true);
          break;

        case 'error':
          logAudioError('elevenlabs-stt', message.error?.message || 'Unknown error');
          this.callbacks.onError?.(message.error?.message || 'Unknown error');
          break;

        case 'audio':
          break;

        default:
          break;
      }
    } catch (e) {
      console.warn('[ElevenLabs STT] Failed to parse message:', e);
    }
  }

  sendAudio(audioData: ArrayBuffer): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    const message = {
      type: 'audio',
      audio_data: Array.from(new Uint8Array(audioData)),
    };

    this.ws.send(JSON.stringify(message));
  }

  sendAudioChunk(audioChunk: Int16Array): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    const message = {
      type: 'audio',
      audio_data: Array.from(audioChunk),
    };

    this.ws.send(JSON.stringify(message));
  }

  commit(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    this.ws.send(JSON.stringify({ type: 'commit' }));
  }

  disconnect(): void {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }

    if (this.ws) {
      this.ws.close(1000, 'Client disconnect');
      this.ws = null;
    }

    this.connected = false;
    this.sessionId = null;
  }
}

export interface RealtimeSTTConfig {
  apiKey?: string;
  modelId?: string;
  callbacks: STTCallbacks;
}

let currentConnection: ElevenLabsSTTConnection | null = null;

export const connectRealtimeSTT = async (
  config: RealtimeSTTConfig
): Promise<ElevenLabsSTTConnection> => {
  const apiKey = config.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsSTTError('API key not configured');
  }

  const modelId = config.modelId || DEFAULT_MODEL_ID;

  if (currentConnection) {
    currentConnection.disconnect();
  }

  currentConnection = new ElevenLabsSTTConnection(apiKey, modelId, config.callbacks);
  await currentConnection.connect();

  return currentConnection;
};

export const disconnectRealtimeSTT = (): void => {
  if (currentConnection) {
    currentConnection.disconnect();
    currentConnection = null;
  }
};

export const isConnected = (): boolean => {
  return currentConnection?.['connected'] === true;
};

export const transcribe = async (
  audioBlob: Blob,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsSTTError('API key not configured');
  }

  const modelId = config?.modelId || DEFAULT_MODEL_ID;
  const startTime = Date.now();
  logAudioRequest('elevenlabs-stt', 'audio transcription');

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), STT_TIMEOUT_MS);

  try {
    const arrayBuffer = await audioBlob.arrayBuffer();
    const formData = new FormData();
    formData.append('file', new Blob([arrayBuffer]), 'audio.wav');
    formData.append('model_id', modelId);

    const response = await fetch(`${ELEVENLABS_HTTP_BASE}/scribe`, {
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
      throw new ElevenLabsSTTError(`API error: ${error}`, response.status);
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
    if (error instanceof ElevenLabsSTTError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : 'Unknown error';
    logAudioError('elevenlabs-stt', message);
    throw new ElevenLabsSTTError(`Request failed: ${message}`);
  }
};

export const transcribeFromArrayBuffer = async (
  audioData: ArrayBuffer,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const blob = new Blob([audioData], { type: 'audio/wav' });
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
  const blob = new Blob([bytes], { type: 'audio/wav' });
  return transcribe(blob, config);
};
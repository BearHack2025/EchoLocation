import { logAudioError, logAudioRequest, logAudioSuccess } from './audio-logger';

const ELEVENLABS_WS_BASE = 'wss://api.elevenlabs.io/v1/speech-to-text/realtime';
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
  private connectResolve: (() => void) | null = null;
  private connectReject: ((error: Error) => void) | null = null;

  constructor(apiKey: string, modelId: string, callbacks: STTCallbacks) {
    this.apiKey = apiKey;
    this.modelId = modelId;
    this.callbacks = callbacks;
  }

  async connect(): Promise<void> {
    logAudioRequest('elevenlabs-stt', 'connecting');

    return new Promise((resolve, reject) => {
      const query = new URLSearchParams({
        model_id: this.modelId,
        language_code: 'en',
        audio_format: 'pcm_16000',
        include_timestamps: 'false',
        include_language_detection: 'false',
        commit_strategy: 'manual',
      });
      const url = `${ELEVENLABS_WS_BASE}?${query.toString()}`;
      this.connectResolve = resolve;
      this.connectReject = reject;

      this.timeoutId = setTimeout(() => {
        this.failConnect(new ElevenLabsSTTError('Connection timeout'));
      }, STT_TIMEOUT_MS);

      const ReactNativeWebSocket = WebSocket as unknown as {
        new (
          url: string,
          protocols?: string | string[],
          options?: { headers?: Record<string, string> }
        ): WebSocket;
      };

      this.ws = new ReactNativeWebSocket(url, undefined, {
        headers: {
          'xi-api-key': this.apiKey,
        },
      });

      this.ws.onopen = () => {
        if (this.timeoutId) {
          clearTimeout(this.timeoutId);
        }
        this.timeoutId = setTimeout(() => {
          if (!this.connected) {
            this.disconnect();
            this.failConnect(new ElevenLabsSTTError('Connection timeout'));
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
        this.failConnect(new ElevenLabsSTTError(message));
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
      const messageType = message.message_type ?? message.type;

      switch (messageType) {
        case 'session_started':
          this.connected = true;
          this.sessionId = message.session_id;
          logAudioSuccess('elevenlabs-stt', 'connected', 0);
          this.resolveConnect();
          this.callbacks.onConnected?.();
          break;

        case 'partial_transcript':
          this.callbacks.onTranscript?.(message.text, false);
          break;

        case 'committed_transcript':
        case 'committed_transcript_with_timestamps':
          this.callbacks.onTranscript?.(message.text, true);
          break;

        case 'error':
          {
            const errorMessage = message.error?.message || message.message || 'Unknown error';
            logAudioError('elevenlabs-stt', errorMessage);
            this.failConnect(new ElevenLabsSTTError(errorMessage));
            this.callbacks.onError?.(errorMessage);
          }
          break;

        default:
          if (typeof message.text === 'string' && messageType?.includes('transcript')) {
            const isFinal = messageType.includes('committed');
            this.callbacks.onTranscript?.(message.text, isFinal);
            break;
          }
          if (typeof message.message === 'string' && messageType?.toLowerCase().includes('error')) {
            logAudioError('elevenlabs-stt', message.message);
            this.failConnect(new ElevenLabsSTTError(message.message));
            this.callbacks.onError?.(message.message);
          }
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
      message_type: 'input_audio_chunk',
      audio_base_64: uint8ArrayToBase64(new Uint8Array(audioData)),
      sample_rate: 16000,
    };

    this.ws.send(JSON.stringify(message));
  }

  sendAudioChunk(audioChunk: Int16Array): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    const message = {
      message_type: 'input_audio_chunk',
      audio_base_64: int16ArrayToBase64(audioChunk),
      sample_rate: 16000,
    };

    this.ws.send(JSON.stringify(message));
  }

  commit(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    this.ws.send(JSON.stringify({
      message_type: 'input_audio_chunk',
      audio_base_64: '',
      sample_rate: 16000,
      commit: true,
    }));
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
    this.connectResolve = null;
    this.connectReject = null;
  }

  private resolveConnect(): void {
    if (this.connectResolve) {
      this.connectResolve();
      this.connectResolve = null;
      this.connectReject = null;
    }
  }

  private failConnect(error: Error): void {
    if (this.connectReject) {
      this.connectReject(error);
      this.connectReject = null;
      this.connectResolve = null;
    }
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
    const formData = new FormData();
    formData.append('file', audioBlob, 'audio.wav');
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

export const transcribeFromBase64 = async (
  base64Audio: string,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const apiKey = config?.apiKey || getApiKey();
  if (!apiKey) {
    throw new ElevenLabsSTTError('API key not configured');
  }
  const modelId = config?.modelId || DEFAULT_MODEL_ID;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), STT_TIMEOUT_MS);

  try {
    const formData = new FormData();
    formData.append('file', {
      uri: `data:audio/wav;base64,${base64Audio}`,
      name: 'audio.wav',
      type: 'audio/wav',
    } as any);
    formData.append('model_id', modelId);

    const response = await fetch(`${ELEVENLABS_HTTP_BASE}/scribe`, {
      method: 'POST',
      headers: { 'xi-api-key': apiKey },
      body: formData,
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!response.ok) {
      const error = await response.text();
      throw new ElevenLabsSTTError(`API error: ${error}`, response.status);
    }
    const data = await response.json();
    return { text: data.text || '', confidence: data.confidence || 0 };
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof ElevenLabsSTTError) throw error;
    const message = error instanceof Error ? error.message : 'Unknown error';
    throw new ElevenLabsSTTError(`Request failed: ${message}`);
  }
};

export const transcribeFromArrayBuffer = async (
  audioData: ArrayBuffer,
  config?: Partial<ElevenLabsSTTConfig>
): Promise<ElevenLabsSTTResponse> => {
  const bytes = new Uint8Array(audioData);
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return transcribeFromBase64(btoa(binary), config);
};

function int16ArrayToBase64(audioChunk: Int16Array): string {
  const bytes = new Uint8Array(
    audioChunk.buffer,
    audioChunk.byteOffset,
    audioChunk.byteLength
  );
  return uint8ArrayToBase64(bytes);
}

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    const chunk = bytes.subarray(index, index + chunkSize);
    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

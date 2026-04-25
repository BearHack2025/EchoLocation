import { ELEVENLABS, elevenLabsApiKey } from './elevenlabs-config';

export class ScribeError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = 'ScribeError';
  }
}

export type ScribeResult = {
  text: string;
  latencyMs: number;
};

/**
 * Transcribe an audio file via ElevenLabs Scribe (STT).
 *
 * Caller passes the file URI from `EchoLidarModule.recordQueryAudio()`.
 * Returns trimmed transcription text + wall-clock latency.
 *
 * Throws `ScribeError` on auth / format / network / timeout failure.
 * Locked to English single-speaker for the wake-word query path.
 */
export async function transcribe(audioFileUri: string): Promise<ScribeResult> {
  const apiKey = elevenLabsApiKey();
  if (!apiKey) {
    throw new ScribeError('ElevenLabs API key not configured');
  }

  const t0 = Date.now();

  const form = new FormData();
  form.append('file', {
    uri: audioFileUri,
    type: 'audio/m4a',
    name: 'query.m4a',
  } as unknown as Blob);
  form.append('model_id', ELEVENLABS.sttModel);
  form.append('language_code', ELEVENLABS.sttLanguageCode);
  form.append('diarize', String(ELEVENLABS.sttDiarize));
  form.append('tag_audio_events', String(ELEVENLABS.sttTagAudioEvents));

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), ELEVENLABS.sttTimeoutMs);

  try {
    const res = await fetch(`${ELEVENLABS.apiBase}/speech-to-text`, {
      method: 'POST',
      headers: { 'xi-api-key': apiKey },
      body: form,
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new ScribeError(`Scribe ${res.status}: ${body}`, res.status);
    }
    const json = (await res.json()) as { text?: string };
    const text = (json.text ?? '').trim();
    return { text, latencyMs: Date.now() - t0 };
  } catch (e: unknown) {
    clearTimeout(timeoutId);
    if (e instanceof ScribeError) throw e;
    if (e instanceof Error && e.name === 'AbortError') {
      throw new ScribeError(`Scribe timeout after ${ELEVENLABS.sttTimeoutMs}ms`);
    }
    const msg = e instanceof Error ? e.message : String(e);
    throw new ScribeError(`Scribe request failed: ${msg}`);
  }
}

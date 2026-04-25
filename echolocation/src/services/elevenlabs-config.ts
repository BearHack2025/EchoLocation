/**
 * Single source of truth for ElevenLabs API configuration.
 * Both `elevenlabsTts.ts` (TTS) and `elevenlabs-scribe.ts` (STT) import from here.
 *
 * All values come from `phase-06-elevenlabs-config-reference.md` in the active
 * plan. Keep that doc in sync if you change anything here.
 */

export const ELEVENLABS = {
  apiBase: 'https://api.elevenlabs.io/v1',

  // TTS
  voiceId: '21m00Tcm4TlvDq8ikWAM', // Rachel (default)
  ttsModel: 'eleven_turbo_v2_5',
  ttsVoiceSettings: {
    stability: 0.4,
    similarity_boost: 0.7,
    style: 0.0,
    use_speaker_boost: true,
  },
  ttsOutputFormat: 'mp3_44100_128' as const,

  // STT (Scribe)
  sttModel: 'scribe_v1',
  sttLanguageCode: 'en',
  sttTagAudioEvents: false,
  sttDiarize: false,

  // Network timeouts
  ttsTimeoutMs: 8000,
  sttTimeoutMs: 5000,
} as const;

export function elevenLabsApiKey(): string {
  return process.env.EXPO_PUBLIC_ELEVENLABS_API_KEY || '';
}

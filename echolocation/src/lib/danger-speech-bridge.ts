import { EchoLidarEmitter } from 'echo-lidar';
import type { DangerSpeechEvent } from 'echo-lidar';

import { elevenLabsPlayer } from '@/services/elevenlabs-player';

/// Subscribes to `onDangerSpeech` events emitted by `EchoLidarSession` (Swift)
/// and plays each sentence via ElevenLabs only — no native fallback.
///
/// `EchoLidarSession` already gates emission on `voiceModeMuted`, so when the
/// user taps Stop on the sheet (which sets the flag true) no events fire and
/// any in-flight playback is cancelled by `useEchoLidar.stop()`.

let subscribed = false;
let sub: { remove: () => void } | null = null;

export function startDangerSpeechBridge(): void {
  if (subscribed) return;
  subscribed = true;
  sub = EchoLidarEmitter.addListener('onDangerSpeech', (e: DangerSpeechEvent) => {
    console.log('[danger-speech]', e.source, `(${e.latencyMs}ms):`, e.sentence);
    void elevenLabsPlayer.play(e.sentence).catch((err) => {
      console.warn('[danger-speech] ElevenLabs play failed:', err);
    });
  });
}

export function stopDangerSpeechBridge(): void {
  sub?.remove();
  sub = null;
  subscribed = false;
  elevenLabsPlayer.stop();
}

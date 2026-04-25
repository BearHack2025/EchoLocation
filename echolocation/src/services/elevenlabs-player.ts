import { createAudioPlayer, AudioPlayer } from 'expo-audio';

import {
  speak as elevenLabsSpeak,
  isConfigured as isElevenLabsConfigured,
  type ElevenLabsTTSConfig,
} from './elevenlabsTts';

export class ElevenLabsPlayerError extends Error {
  constructor(message: string, public reason: 'not-configured' | 'fetch' | 'playback' | 'aborted') {
    super(message);
    this.name = 'ElevenLabsPlayerError';
  }
}

/// Singleton player. The orchestrator owns the only call site, so a single shared
/// player is fine — concurrent plays would clobber each other anyway. New plays
/// stop the prior one. `stop()` is idempotent.
class ElevenLabsPlayer {
  private current: AudioPlayer | null = null;

  /// Play a sentence via ElevenLabs TTS. Resolves when playback finishes,
  /// rejects on fetch / playback / abort. Throws `not-configured` early so the
  /// caller can fall through without paying the network round-trip.
  ///
  /// `opts.onDidStart` fires the first time audio actually plays — caller can
  /// use this to suppress fallback TTS even if playback later errors mid-stream
  /// (otherwise the same sentence speaks twice).
  async play(
    text: string,
    opts?: {
      config?: Partial<ElevenLabsTTSConfig>;
      onDidStart?: () => void;
    }
  ): Promise<void> {
    if (!isElevenLabsConfigured()) {
      throw new ElevenLabsPlayerError('ElevenLabs API key not configured', 'not-configured');
    }

    this.stop();

    let result: Awaited<ReturnType<typeof elevenLabsSpeak>>;
    try {
      result = await elevenLabsSpeak(text, opts?.config);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      throw new ElevenLabsPlayerError(`TTS fetch failed: ${msg}`, 'fetch');
    }

    if (!result.audioUrl) {
      throw new ElevenLabsPlayerError('TTS returned no audio URL', 'fetch');
    }

    let player: AudioPlayer;
    try {
      player = createAudioPlayer(result.audioUrl);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      throw new ElevenLabsPlayerError(`Audio player init failed: ${msg}`, 'playback');
    }

    this.current = player;

    return new Promise<void>((resolve, reject) => {
      let settled = false;
      let didStart = false;
      const finish = (err?: Error) => {
        if (settled) return;
        settled = true;
        try { player.remove(); } catch {}
        if (this.current === player) this.current = null;
        if (err) reject(err); else resolve();
      };

      player.addListener('playbackStatusUpdate', (status) => {
        if (!status.isLoaded) return;
        if (status.playing && !didStart) {
          didStart = true;
          opts?.onDidStart?.();
        }
        if (status.didJustFinish) finish();
      });

      try {
        player.play();
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        finish(new ElevenLabsPlayerError(`Playback start failed: ${msg}`, 'playback'));
      }
    });
  }

  /// Stop and release the current sound. Safe to call when nothing is playing.
  stop(): void {
    if (!this.current) return;
    try {
      this.current.pause();
      this.current.remove();
    } catch {
      // Best-effort cleanup
    }
    this.current = null;
  }
}

export const elevenLabsPlayer = new ElevenLabsPlayer();

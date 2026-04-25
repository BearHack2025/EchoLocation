import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, WakeWordEvent } from 'echo-lidar';

import { elevenLabsPlayer } from '@/services/elevenlabs-player';

export type VoiceModeState =
  | 'idle'
  | 'waking'
  | 'thinking'
  | 'speaking'
  | 'error';

type Listener = (state: VoiceModeState) => void;

class VoiceModeOrchestrator {
  private state: VoiceModeState = 'idle';
  private listeners = new Set<Listener>();
  private wakeSub: { remove: () => void } | null = null;
  private echoSub: { remove: () => void } | null = null;
  private latestEcho: EchoUpdate | null = null;
  private running = false;

  /** Activate wake-word listening + mute always-on speech. */
  async start(): Promise<void> {
    console.log('[voice-mode] start() called; running=', this.running);
    if (this.running) return;

    // Defensive: if the native binary is older than the JS bundle, the new
    // AsyncFunctions can be undefined. Surface this concretely instead of
    // crashing with "X is not a function".
    const startFn = (EchoLidarModule as unknown as { startWakeListener?: () => Promise<void> })
      .startWakeListener;
    if (typeof startFn !== 'function') {
      console.warn('[voice-mode] startWakeListener missing on native module — rebuild needed');
      this.set('error');
      throw new Error('Native module missing startWakeListener — run `npx expo run:ios` to relink');
    }

    this.running = true;
    try { EchoLidarModule.setVoiceModeMuted(true); } catch {}

    this.echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (e: EchoUpdate) => {
      this.latestEcho = e;
    });
    this.wakeSub = EchoLidarEmitter.addListener('onWakeWord', (e: WakeWordEvent) => {
      console.log('[voice-mode] onWakeWord event received', e.phrase);
      void this.onWake(e.phrase);
    });

    try {
      console.log('[voice-mode] calling startWakeListener…');
      await EchoLidarModule.startWakeListener();
      console.log('[voice-mode] startWakeListener resolved');
      this.set('idle');
    } catch (err) {
      console.warn('[voice-mode] startWakeListener rejected:', err);
      this.set('error');
      this.running = false;
      throw err;
    }
  }

  async stop(): Promise<void> {
    if (!this.running) return;
    this.running = false;
    this.wakeSub?.remove(); this.wakeSub = null;
    this.echoSub?.remove(); this.echoSub = null;
    elevenLabsPlayer.stop();
    await EchoLidarModule.stopWakeListener().catch(() => {});
    try { EchoLidarModule.setVoiceModeMuted(false); } catch {}
    this.set('idle');
  }

  onState(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  getState(): VoiceModeState {
    return this.state;
  }

  // ----- pipeline -----

  /// Wake → snapshot context → Gemma briefing → ElevenLabs → idle.
  /// No question capture, no STT — the wake itself is the entire user input.
  /// Per user rule: "DO NOT say anything beside the guidance".
  private async onWake(phrase: string): Promise<void> {
    console.log('[voice-mode] onWake', phrase, 'currentState=', this.state, 'running=', this.running);
    if (this.state !== 'idle' || !this.running) return;

    this.set('waking');

    try {
      this.set('thinking');
      const ctx = this.echoContext();
      const sentence = await EchoLidarModule.wakeBriefing(
        ctx.distanceM, ctx.direction, ctx.label
      ).catch(() => this.lidarFallbackSentence(ctx));

      this.set('speaking');
      await this.speakElevenLabsOnly(sentence || this.lidarFallbackSentence(ctx));
    } catch {
      // Defensive: capture / unknown failure. Per user rule, stay silent —
      // surface error state so the UI shows "tap to retry" but make no sound.
      this.set('error');
      setTimeout(() => {
        if (this.state === 'error') this.set('idle');
      }, 1500);
      return;
    }

    // Successful path: return to idle so the wake listener (still running)
    // is ready for the next phrase.
    if (this.running) this.set('idle');
  }

  /// ElevenLabs ONLY — no native AVSpeechSynthesizer fallback.
  /// Per user choice: if ElevenLabs fails, the app stays silent. The state
  /// flips to 'error'; auto-resets to 'idle' after 1.5 s so the next wake works.
  private async speakElevenLabsOnly(text: string): Promise<void> {
    try {
      await elevenLabsPlayer.play(text);
    } catch {
      this.set('error');
      setTimeout(() => {
        if (this.state === 'error') this.set('idle');
      }, 1500);
    }
  }

  /// Mirrors `wakeBriefing`'s shape using only the cached EchoUpdate. Used
  /// when Gemma errors so the user always gets *something* spoken in the
  /// same format.
  private lidarFallbackSentence(ctx: ReturnType<typeof this.echoContext>): string {
    if (ctx.distanceM <= 0) return 'No obstacles detected. Go ahead.';
    const dist = ctx.distanceM.toFixed(1);
    const dir = ctx.direction === 'center' ? 'ahead' : `to your ${ctx.direction}`;
    let action: string;
    if (ctx.distanceM < 0.5) action = 'stop now';
    else if (ctx.direction === 'left') action = 'step right';
    else if (ctx.direction === 'right') action = 'step left';
    else if (ctx.distanceM < 1.0) action = 'stop now';
    else if (ctx.distanceM < 2.0) action = 'slow down';
    else action = 'go ahead';
    return `${capitalize(ctx.label)} ${dir}, ${dist} meters. ${capitalize(action)}.`;
  }

  private echoContext(): { distanceM: number; direction: string; label: string } {
    const e = this.latestEcho;
    return {
      distanceM: e?.nearestDistanceMeters ?? 0,
      direction: e?.direction ?? 'unknown',
      label: e?.label ?? 'obstacle',
    };
  }

  private set(s: VoiceModeState): void {
    if (this.state !== s) {
      console.log('[voice-mode]', this.state, '→', s);
    }
    this.state = s;
    this.listeners.forEach((l) => l(s));
  }
}

function capitalize(s: string): string {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// Module-scoped singleton — one orchestrator per app process.
export const voiceModeOrchestrator = new VoiceModeOrchestrator();

import EchoLidarModule, { EchoLidarEmitter } from 'echo-lidar';
import type { EchoUpdate, VoiceCommandEvent, VoiceCommandName } from 'echo-lidar';

import { elevenLabsPlayer } from '@/services/elevenlabs-player';

import { SCENE_DESCRIBE_PROMPT, buildDirectionPrompt } from './gemma-prompts';

export type VoiceState = {
  status: 'idle' | 'thinking' | 'speaking';
  lastSentence: string;
  lastError: string | null;
  lastSource: 'gemma' | 'lidar-fallback' | null;
};

type Listener = (state: VoiceState) => void;

const INFERENCE_TIMEOUT_MS = 8000;
const HARD_STOP_DISTANCE_M = 0.6;

class VoiceOrchestrator {
  private state: VoiceState = {
    status: 'idle',
    lastSentence: '',
    lastError: null,
    lastSource: null,
  };
  private listeners = new Set<Listener>();
  private latestEcho: EchoUpdate | null = null;
  private subs: Array<{ remove: () => void }> = [];
  private currentRun = 0;

  start() {
    this.stop();
    const echoSub = EchoLidarEmitter.addListener('onEchoUpdate', (e) => {
      this.latestEcho = e;
    });
    const voiceSub = EchoLidarEmitter.addListener('onVoiceCommand', (e: VoiceCommandEvent) => {
      void this.handle(e.command);
    });
    this.subs = [echoSub, voiceSub];
  }

  stop() {
    this.subs.forEach((s) => s.remove());
    this.subs = [];
    this.latestEcho = null;
    this.cancelInFlight();
  }

  onState(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  getState(): VoiceState {
    return this.state;
  }

  async handle(command: VoiceCommandName) {
    this.cancelInFlight();
    const runId = ++this.currentRun;

    if (command === 'repeat') {
      const sentence = this.state.lastSentence;
      if (!sentence) {
        this.setState({ lastError: 'Nothing to repeat yet.' });
        return;
      }
      await this.speak(sentence, runId);
      return;
    }

    this.setState({ status: 'thinking', lastError: null });

    try {
      let finalSentence: string;
      if (command === 'ahead' || command === 'left' || command === 'right') {
        finalSentence = await this.runScene(runId, command);
      } else if (command === 'where') {
        finalSentence = await this.runDirection(runId);
      } else {
        this.setState({ status: 'idle' });
        return;
      }

      if (runId !== this.currentRun) return;
      await this.speak(finalSentence, runId);
    } catch (e: unknown) {
      if (runId !== this.currentRun) return;
      const msg = e instanceof Error ? e.message : String(e);
      this.setState({ status: 'idle', lastError: msg });
      await EchoLidarModule.speak("I can't tell right now.").catch(() => {});
    }
  }

  // MARK: - Inference paths

  private async runScene(runId: number, command: VoiceCommandName): Promise<string> {
    const result = await this.withTimeout(
      EchoLidarModule.describeScene(SCENE_DESCRIBE_PROMPT)
    );
    if (runId !== this.currentRun) throw new Error('cancelled');

    let sentence = result.sentence;
    if (command === 'left' || command === 'right') {
      sentence = filterSentenceForDirection(sentence, command);
    }
    this.setState({ lastSource: 'gemma' });
    return sentence;
  }

  private async runDirection(runId: number): Promise<string> {
    const ctx = this.directionContext();
    const prompt = buildDirectionPrompt({
      distanceM: ctx.distanceM,
      lidarDirection: ctx.lidarDirection,
      lidarLabel: ctx.lidarLabel,
    });
    const result = await this.withTimeout(
      EchoLidarModule.recommendDirection(
        prompt,
        ctx.distanceM,
        ctx.lidarDirection,
        ctx.lidarLabel
      )
    );
    if (runId !== this.currentRun) throw new Error('cancelled');

    // Hard-stop override regardless of model output.
    let sentence = result.sentence;
    if (ctx.distanceM != null && ctx.distanceM < HARD_STOP_DISTANCE_M) {
      sentence = 'Stop. Obstacle very close.';
    }
    this.setState({ lastSource: result.source });
    return sentence;
  }

  // MARK: - Helpers

  private async speak(sentence: string, runId: number) {
    if (runId !== this.currentRun) return;
    this.setState({ status: 'speaking', lastSentence: sentence });

    // Reserve the native speech queue so the always-on `describe`-mode phrasing
    // doesn't talk over our voice-command response.
    await EchoLidarModule.beginVoiceSpeech().catch(() => {});

    let elevenLabsCommitted = false;
    try {
      // Primary: ElevenLabs TTS via expo-audio. Falls through silently on any
      // error (no key, network, decode, playback) so the demo never goes silent.
      try {
        await elevenLabsPlayer.play(sentence, {
          onDidStart: () => {
            elevenLabsCommitted = true;
          },
        });
        return;
      } catch {
        // If ElevenLabs already played some audio before erroring, do NOT speak
        // the same sentence again via native — that's the dup we're hunting.
        if (elevenLabsCommitted) return;
      }
      if (runId !== this.currentRun) return;
      await EchoLidarModule.speak(sentence);
    } finally {
      await EchoLidarModule.endVoiceSpeech().catch(() => {});
      if (runId === this.currentRun) {
        this.setState({ status: 'idle' });
      }
    }
  }

  private cancelInFlight() {
    this.currentRun++;
    elevenLabsPlayer.stop();
    EchoLidarModule.stopSpeaking().catch(() => {});
    EchoLidarModule.endVoiceSpeech().catch(() => {});
  }

  private async withTimeout<T>(p: Promise<T>): Promise<T> {
    return Promise.race([
      p,
      new Promise<T>((_, reject) =>
        setTimeout(() => reject(new Error('Inference timed out')), INFERENCE_TIMEOUT_MS)
      ),
    ]);
  }

  private directionContext() {
    const e = this.latestEcho;
    return {
      distanceM: e?.nearestDistanceMeters ?? null,
      lidarDirection: (e?.direction ?? 'unknown') as 'left' | 'center' | 'right' | 'unknown',
      lidarLabel: e?.label ?? 'unknown',
    };
  }

  private setState(patch: Partial<VoiceState>) {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((l) => l(this.state));
  }
}

function filterSentenceForDirection(sentence: string, dir: 'left' | 'right'): string {
  // Best-effort: if the sentence mentions the requested direction, prefer the clause
  // that does; otherwise return the original sentence (still informative).
  const lower = sentence.toLowerCase();
  if (!lower.includes(dir)) return sentence;
  const clauses = sentence.split(/[,.;]/).map((c) => c.trim()).filter(Boolean);
  const match = clauses.find((c) => c.toLowerCase().includes(dir));
  return match ? match.endsWith('.') ? match : `${match}.` : sentence;
}

// Module-scoped singleton — one orchestrator per app process.
export const voiceOrchestrator = new VoiceOrchestrator();

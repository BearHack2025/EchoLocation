import { EventEmitter, requireNativeModule } from 'expo-modules-core';

import type { EchoLidarModuleEvents, EchoMode, EchoSupportStatus } from './EchoLidar.types';
import type {
  GemmaDirectionResult,
  GemmaModelStatus,
  GemmaSceneResult,
} from './Gemma.types';

type NativeEchoLidarModule = {
  // Capability checks
  isSupported(): boolean;
  supportsDepth(): boolean;
  supportsMeshClassification(): boolean;
  getSupportStatus(): EchoSupportStatus;

  // Session lifecycle
  start(mode?: EchoMode): Promise<void>;
  stop(): Promise<void>;
  startVoiceCommands(): Promise<void>;
  stopVoiceCommands(): Promise<void>;

  // Native speech (orchestrator)
  speak(text: string): Promise<void>;
  stopSpeaking(): Promise<void>;
  beginVoiceSpeech(): Promise<void>;
  endVoiceSpeech(): Promise<void>;

  // Gemma provisioning
  getModelStatus(): GemmaModelStatus;
  downloadModel(): Promise<void>;
  cancelDownload(): Promise<void>;
  setUseMockInference(mock: boolean): void;

  // Gemma inference
  describeScene(prompt: string): Promise<GemmaSceneResult>;
  recommendDirection(
    prompt: string,
    distanceM: number | null,
    lidarDirection: string,
    lidarLabel: string
  ): Promise<GemmaDirectionResult>;

  // Label source toggle (Gemma vs MeshClassifier)
  setLabelSource(useGemma: boolean): void;
  getLabelSource(): string;

  // Event-driven summarized speech toggle (vs template loop)
  setEventDrivenSpeech(enabled: boolean): void;
  getEventDrivenSpeech(): boolean;

  // Thermal state
  getThermalState(): string;
};

const noopStub: NativeEchoLidarModule = {
  isSupported: () => false,
  supportsDepth: () => false,
  supportsMeshClassification: () => false,
  getSupportStatus: () => ({
    isARSupported: false,
    supportsDepth: false,
    supportsMeshClassification: false,
  }),
  start: async () => {
    throw new Error('EchoLidar native module not available — use a development build');
  },
  stop: async () => {},
  startVoiceCommands: async () => {
    throw new Error('Voice commands require a development build on iOS');
  },
  stopVoiceCommands: async () => {},
  speak: async () => {},
  stopSpeaking: async () => {},
  beginVoiceSpeech: async () => {},
  endVoiceSpeech: async () => {},
  getModelStatus: () => ({ state: 'idle', progressBytes: 0, totalBytes: 0 }),
  downloadModel: async () => {
    throw new Error('Model download requires a development build on iOS');
  },
  cancelDownload: async () => {},
  setUseMockInference: () => {},
  describeScene: async () => ({ sentence: '', objects: [], latencyMs: 0 }),
  recommendDirection: async () => ({
    direction: 'stop',
    confidence: 0,
    reason: 'native module unavailable',
    sentence: '',
    source: 'lidar-fallback',
    latencyMs: 0,
  }),
  setLabelSource: () => {},
  getLabelSource: () => 'init',
  setEventDrivenSpeech: () => {},
  getEventDrivenSpeech: () => true,
  getThermalState: () => 'nominal',
};

let EchoLidarModule: NativeEchoLidarModule;
try {
  EchoLidarModule = requireNativeModule<NativeEchoLidarModule>('EchoLidar');
} catch {
  EchoLidarModule = noopStub;
}

export const EchoLidarEmitter = new EventEmitter<EchoLidarModuleEvents>(
  EchoLidarModule as never
);

export default EchoLidarModule;

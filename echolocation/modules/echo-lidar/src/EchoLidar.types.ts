export type EchoDirection = 'left' | 'center' | 'right' | 'unknown';

export type EchoMode = 'echo' | 'describe' | 'quiet';

export type EchoLabel =
  | 'obstacle'
  | 'wall'
  | 'floor'
  | 'table'
  | 'seat'
  | 'door'
  | 'window'
  | 'unknown';

export type EchoUpdate = {
  nearestDistanceMeters: number | null;
  direction: EchoDirection;
  label: EchoLabel;
  confidence: number;
  mode: EchoMode;
  timestampMs: number;
  source: 'mock' | 'arkit';
};

export type EchoSupportStatus = {
  isARSupported: boolean;
  supportsDepth: boolean;
  supportsMeshClassification: boolean;
};

export type VoiceCommandName = 'ahead' | 'left' | 'right' | 'repeat' | 'where';

export type VoiceCommandEvent = {
  command: VoiceCommandName;
  transcript: string;
  timestampMs: number;
  source: 'speech';
};

export type ThermalStateName = 'nominal' | 'fair' | 'serious' | 'critical' | 'unknown';

export type ThermalStateEvent = {
  state: ThermalStateName;
  throttled: boolean;
};

export type WakeWordEvent = {
  phrase: string;        // "hey echo" | "echo"
  timestampMs: number;
};

export type DangerSpeechEvent = {
  sentence: string;
  source: 'gemma' | 'lidar-fallback';
  latencyMs: number;
};

export type EchoLidarModuleEvents = {
  onEchoUpdate: (event: EchoUpdate) => void;
  onVoiceCommand: (event: VoiceCommandEvent) => void;
  onModelStatus: (event: import('./Gemma.types').GemmaModelStatus) => void;
  onThermalState: (event: ThermalStateEvent) => void;
  onWakeWord: (event: WakeWordEvent) => void;
  onDangerSpeech: (event: DangerSpeechEvent) => void;
};

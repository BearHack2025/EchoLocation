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
  label: string;
  meshLabel?: EchoLabel;
  visionLabel?: string;
  visionConfidence?: number;
  visionLabels?: SceneLabel[];
  confidence: number;
  mode: EchoMode;
  timestampMs: number;
  source: 'mock' | 'arkit';
};

export type SnapshotCapture = {
  jpegBase64: string;
  width: number;
  height: number;
  timestampMs: number;
  source: 'arkit';
};

export type SceneLabel = {
  text: string;
  confidence: number;
  index: number;
};

export type SceneLabelResult = {
  snapshot: SnapshotCapture;
  labels: SceneLabel[];
};

export type EchoSupportStatus = {
  isARSupported: boolean;
  supportsDepth: boolean;
  supportsMeshClassification: boolean;
};

export type VoiceCommandName = 'ahead' | 'left' | 'right' | 'repeat';

export type VoiceCommandEvent = {
  command: VoiceCommandName;
  transcript: string;
  timestampMs: number;
  source: 'speech';
};

export type EchoLidarModuleEvents = {
  onEchoUpdate: (event: EchoUpdate) => void;
  onVoiceCommand: (event: VoiceCommandEvent) => void;
};

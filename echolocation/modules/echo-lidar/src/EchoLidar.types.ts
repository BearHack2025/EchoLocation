export type EchoDirection = 'left' | 'center' | 'right' | 'unknown';

export type EchoMode = 'describe' | 'quiet';

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
  labelSource?: 'arkit-mesh' | 'mlkit';
  recognizedText?: string;
  textSource?: 'ocr';
};

export type EchoSupportStatus = {
  isARSupported: boolean;
  supportsDepth: boolean;
  supportsMeshClassification: boolean;
};

export type VoiceCommandName =
  | 'ahead'
  | 'repeat'
  | 'describe_mode'
  | 'quiet_mode'
  | 'stop';

export type VoiceCommandEvent = {
  command: VoiceCommandName;
  transcript: string;
  timestampMs: number;
  source: 'speech' | 'elevenlabs';
};

export type EchoLidarModuleEvents = {
  onEchoUpdate: (event: EchoUpdate) => void;
  onVoiceCommand: (event: VoiceCommandEvent) => void;
  onSpeechRequest: (event: SpeechRequestEvent) => void;
  onAudioChunk: (event: AudioChunkEvent) => void;
};

export type SpeechRequestEvent = {
  text: string;
  mode: EchoMode;
  timestamp: number;
};

export type AudioChunkEvent = {
  data: number[];
};

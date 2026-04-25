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

export type EchoLidarModuleEvents = {
  onEchoUpdate: (event: EchoUpdate) => void;
};

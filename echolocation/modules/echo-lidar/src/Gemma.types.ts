export type GemmaModelState = 'idle' | 'downloading' | 'ready' | 'error';

export type GemmaModelStatus = {
  state: GemmaModelState;
  progressBytes: number;
  totalBytes: number;
  error?: string | null;
};

export type GemmaSceneResult = {
  sentence: string;
  objects: string[];
  latencyMs: number;
};

export type GemmaDirectionName = 'left' | 'forward' | 'right' | 'stop';

export type GemmaDirectionResult = {
  direction: GemmaDirectionName;
  confidence: number;
  reason: string;
  sentence: string;
  source: 'gemma' | 'lidar-fallback';
  latencyMs: number;
};

export type GemmaDirectionContext = {
  distanceM: number | null;
  lidarDirection: 'left' | 'center' | 'right' | 'unknown';
  lidarLabel: string;
};

export type AudioLogSource = 'elevenlabs-tts' | 'elevenlabs-stt' | 'expo-speech' | 'builtin-ios';

export type AudioLogLevel = 'info' | 'warn' | 'error';

export interface AudioLogEntry {
  timestamp: Date;
  source: AudioLogSource;
  level: AudioLogLevel;
  text?: string;
  latencyMs?: number;
  status: 'success' | 'error';
  error?: string;
  mode?: 'echo' | 'describe';
}

const LOG_PREFIX = '[Audio]';

function formatTimestamp(date: Date): string {
  return date.toISOString();
}

function logEntry(entry: AudioLogEntry): void {
  const { timestamp, source, level, text, latencyMs, status, error, mode } = entry;

  const parts: string[] = [
    LOG_PREFIX,
    `source=${source}`,
    `level=${level}`,
    `status=${status}`,
  ];

  if (mode) parts.push(`mode=${mode}`);
  if (text !== undefined) parts.push(`text="${text}"`);
  if (latencyMs !== undefined) parts.push(`latency=${latencyMs}ms`);
  if (error) parts.push(`error="${error}"`);
  parts.push(`ts=${formatTimestamp(timestamp)}`);

  const message = parts.join(' ');

  switch (level) {
    case 'error':
      console.error(message);
      break;
    case 'warn':
      console.warn(message);
      break;
    default:
      console.log(message);
  }
}

export function logAudioRequest(
  source: AudioLogSource,
  text: string,
  mode?: 'echo' | 'describe'
): void {
  logEntry({
    timestamp: new Date(),
    source,
    level: 'info',
    text,
    status: 'success',
    mode,
  });
}

export function logAudioSuccess(
  source: AudioLogSource,
  text: string,
  latencyMs: number,
  mode?: 'echo' | 'describe'
): void {
  logEntry({
    timestamp: new Date(),
    source,
    level: 'info',
    text,
    latencyMs,
    status: 'success',
    mode,
  });
}

export function logAudioError(
  source: AudioLogSource,
  error: string,
  text?: string,
  mode?: 'echo' | 'describe'
): void {
  logEntry({
    timestamp: new Date(),
    source,
    level: 'error',
    text,
    status: 'error',
    error,
    mode,
  });
}

export function logFallback(
  fromSource: AudioLogSource,
  text: string,
  reason: string,
  mode?: 'echo' | 'describe'
): void {
  logEntry({
    timestamp: new Date(),
    source: fromSource,
    level: 'warn',
    text,
    status: 'error',
    error: `fallback triggered: ${reason}`,
    mode,
  });
}

export function logBuiltinFallback(
  text: string,
  reason: string,
  mode?: 'echo' | 'describe'
): void {
  logEntry({
    timestamp: new Date(),
    source: 'builtin-ios',
    level: 'warn',
    text,
    status: 'success',
    error: `ElevenLabs unavailable: ${reason}`,
    mode,
  });
}
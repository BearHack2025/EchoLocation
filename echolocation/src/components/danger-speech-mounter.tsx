import { useEffect } from 'react';

import { startDangerSpeechBridge, stopDangerSpeechBridge } from '@/lib/danger-speech-bridge';

/// Render-nothing component that subscribes to `onDangerSpeech` events for the
/// app's lifetime. Mounted once at the root layout.
export function DangerSpeechMounter(): null {
  useEffect(() => {
    startDangerSpeechBridge();
    return stopDangerSpeechBridge;
  }, []);
  return null;
}

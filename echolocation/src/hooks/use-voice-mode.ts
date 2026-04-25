import { useCallback, useEffect, useState } from 'react';

import EchoLidarModule from 'echo-lidar';

import {
  voiceModeOrchestrator,
  type VoiceModeState,
} from '@/lib/voice-mode-orchestrator';

export type { VoiceModeState };

/// Defensive: if the native binary is older than the JS bundle (e.g. JS reload
/// reached the device but `expo run:ios` hasn't relinked the module yet), new
/// Functions can be `undefined`. Guard each call so the screen still renders
/// instead of crashing with "X is not a function".
function safeGetMuted(): boolean {
  const fn = (EchoLidarModule as unknown as { getVoiceModeMuted?: () => boolean })
    .getVoiceModeMuted;
  return typeof fn === 'function' ? fn() : false;
}
function safeSetMuted(muted: boolean): void {
  const fn = (EchoLidarModule as unknown as { setVoiceModeMuted?: (m: boolean) => void })
    .setVoiceModeMuted;
  if (typeof fn === 'function') fn(muted);
}

/// Surfaces the wake-word voice-mode state to React.
/// `start()` mutes always-on speech and begins listening for "hey echo".
/// `stop()` unmutes and ends the loop.
export function useVoiceMode() {
  const [state, setState] = useState<VoiceModeState>(() =>
    voiceModeOrchestrator.getState()
  );
  const [muted, setMutedState] = useState<boolean>(() => safeGetMuted());

  useEffect(() => {
    const unsub = voiceModeOrchestrator.onState((s) => setState(s));
    return unsub;
  }, []);

  const start = useCallback(async () => {
    await voiceModeOrchestrator.start();
    setMutedState(safeGetMuted());
  }, []);

  const stop = useCallback(async () => {
    await voiceModeOrchestrator.stop();
    setMutedState(safeGetMuted());
  }, []);

  const setMuted = useCallback((next: boolean) => {
    safeSetMuted(next);
    setMutedState(next);
  }, []);

  return { state, muted, start, stop, setMuted };
}

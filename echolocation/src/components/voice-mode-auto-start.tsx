import { useEffect } from 'react';
import { AppState, type AppStateStatus } from 'react-native';

import EchoLidarModule from 'echo-lidar';

import { voiceModeOrchestrator } from '@/lib/voice-mode-orchestrator';

/// Drives the wake-only voice loop without any user interaction.
/// Mounted once at the root layout. Renders nothing.
///
/// Lifecycle:
/// - On mount → starts LiDAR session + voice-mode orchestrator
/// - On AppState 'active' → re-starts both (idempotent if already running)
/// - On unmount → stops both
export function VoiceModeAutoStart(): null {
  useEffect(() => {
    console.log('[VoiceModeAutoStart] mounting');
    // One-shot module surface dump so we can confirm the native binary has
    // the new AsyncFunctions. If `startWakeListener` is missing here, the
    // device is running a stale binary — `expo run:ios` needs to relink.
    try {
      const keys = Object.keys((EchoLidarModule as unknown) as Record<string, unknown>).sort();
      console.log('[VoiceModeAutoStart] EchoLidarModule keys:', keys.join(','));
      const hasWake = typeof (EchoLidarModule as unknown as { startWakeListener?: () => Promise<void> })
        .startWakeListener === 'function';
      console.log('[VoiceModeAutoStart] startWakeListener present?', hasWake);
    } catch (e) {
      console.warn('[VoiceModeAutoStart] keys probe failed:', e);
    }
    let cancelled = false;

    const startAll = async () => {
      try {
        console.log('[VoiceModeAutoStart] EchoLidarModule.start("describe")');
        await EchoLidarModule.start('describe');
        console.log('[VoiceModeAutoStart] LiDAR started');
      } catch (e) {
        console.warn('[VoiceModeAutoStart] LiDAR start failed:', e);
      }
      if (cancelled) return;
      try {
        console.log('[VoiceModeAutoStart] voiceModeOrchestrator.start()');
        await voiceModeOrchestrator.start();
        console.log('[VoiceModeAutoStart] orchestrator started');
      } catch (e) {
        console.warn('[VoiceModeAutoStart] orchestrator start failed:', e);
      }
    };

    void startAll();

    const onAppStateChange = (next: AppStateStatus) => {
      console.log('[VoiceModeAutoStart] AppState →', next);
      if (next === 'active') {
        void voiceModeOrchestrator.start().catch((e) => {
          console.warn('[VoiceModeAutoStart] resume failed:', e);
        });
      }
    };

    const sub = AppState.addEventListener('change', onAppStateChange);

    return () => {
      console.log('[VoiceModeAutoStart] unmounting');
      cancelled = true;
      sub.remove();
      void voiceModeOrchestrator.stop().catch(() => {});
      void EchoLidarModule.stop().catch(() => {});
    };
  }, []);

  return null;
}

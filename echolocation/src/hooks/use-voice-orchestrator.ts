import { useEffect, useState } from 'react';

import { voiceOrchestrator, type VoiceState } from '@/lib/voice-command-orchestrator';

export function useVoiceOrchestrator() {
  const [state, setState] = useState<VoiceState>(() => voiceOrchestrator.getState());

  useEffect(() => {
    const unsub = voiceOrchestrator.onState(setState);
    return unsub;
  }, []);

  return state;
}

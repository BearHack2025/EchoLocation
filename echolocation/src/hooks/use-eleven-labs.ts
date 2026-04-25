import { useCallback, useState } from 'react';
import { Audio } from 'expo-av';

import {
  speak,
  clearCache,
  isConfigured as isTtsConfigured,
  type ElevenLabsTTSConfig,
  ElevenLabsError,
} from '../services/elevenlabsTts';
import {
  transcribe,
  isConfigured as isSttConfigured,
  type ElevenLabsSTTConfig,
} from '../services/elevenlabsStt';

export interface ElevenLabsState {
  isPlaying: boolean;
  isRecording: boolean;
  lastSpokenText: string;
  lastTranscribedText: string;
  error: string | null;
}

export function useElevenLabs() {
  const [isPlaying, setIsPlaying] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [lastSpokenText, setLastSpokenText] = useState('');
  const [lastTranscribedText, setLastTranscribedText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [audioInstance, setAudioInstance] = useState<Audio.Sound | null>(null);

  const isConfigured = isTtsConfigured() && isSttConfigured();

  const speakText = useCallback(
    async (text: string, config?: Partial<ElevenLabsTTSConfig>): Promise<boolean> => {
      if (!isTtsConfigured()) {
        setError('ElevenLabs API key not configured');
        return false;
      }

      setError(null);
      setLastSpokenText(text);

      try {
        if (audioInstance) {
          await audioInstance.unloadAsync();
        }

        const result = await speak(text, config);
        if(result.audioUrl === undefined) {
          setError('No audio URL returned from ElevenLabs');
          return false;
        }
        const { sound } = await Audio.Sound.createAsync(
          { uri: result.audioUrl },
          { shouldPlay: true },
          (status) => {
            if (status.isLoaded && status.didJustFinish) {
              setIsPlaying(false);
            }
          }
        );

        setAudioInstance(sound);
        setIsPlaying(true);
        return true;
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        const elevenError = e as ElevenLabsError;
        if (elevenError.statusCode) {
          setError(`Speech failed (${elevenError.statusCode}): ${message}`);
        } else {
          setError(`Speech failed: ${message}`);
        }
        return false;
      }
    },
    [audioInstance]
  );

  const stopSpeaking = useCallback(async () => {
    if (audioInstance) {
      await audioInstance.stopAsync();
      await audioInstance.unloadAsync();
      setAudioInstance(null);
    }
    setIsPlaying(false);
  }, [audioInstance]);

  const transcribeAudio = useCallback(
    async (
      audioBlob: Blob,
      config?: Partial<ElevenLabsSTTConfig>
    ): Promise<string | null> => {
      if (!isSttConfigured()) {
        setError('ElevenLabs API key not configured');
        return null;
      }

      setError(null);
      setIsRecording(true);

      try {
        const result = await transcribe(audioBlob, config);
        setLastTranscribedText(result.text);
        setIsRecording(false);
        return result.text;
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        const elevenError = e as ElevenLabsError;
        if (elevenError.statusCode) {
          setError(`Transcription failed (${elevenError.statusCode}): ${message}`);
        } else {
          setError(`Transcription failed: ${message}`);
        }
        setIsRecording(false);
        return null;
      }
    },
    []
  );

  const clearElevenLabsCache = useCallback(() => {
    clearCache();
  }, []);

  return {
    isConfigured,
    isPlaying,
    isRecording,
    lastSpokenText,
    lastTranscribedText,
    error,
    speakText,
    stopSpeaking,
    transcribeAudio,
    clearCache: clearElevenLabsCache,
  };
}
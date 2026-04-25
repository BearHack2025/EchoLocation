import { useCallback, useState, useRef, useEffect } from 'react';
import { createAudioPlayer, AudioPlayer } from 'expo-audio';
import * as Speech from 'expo-speech';

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

  const playerRef = useRef<AudioPlayer | null>(null);
  const speechGenRef = useRef(0);

  const isConfigured = isTtsConfigured() && isSttConfigured();

  const stopAllPlayback = useCallback(() => {
    speechGenRef.current += 1;
    if (playerRef.current) {
      try { playerRef.current.pause(); } catch {}
      try { playerRef.current.remove(); } catch {}
      playerRef.current = null;
    }
    Speech.stop();
  }, []);

  const speakText = useCallback(
    async (text: string, config?: Partial<ElevenLabsTTSConfig>): Promise<boolean> => {
      if (!isTtsConfigured()) {
        setError('ElevenLabs API key not configured');
        return false;
      }

      stopAllPlayback();
      const myGen = speechGenRef.current;
      setError(null);
      setLastSpokenText(text);

      try {
        const result = await speak(text, config);
        if (myGen !== speechGenRef.current) return false;
        if (result.audioUrl === undefined) {
          setError('No audio URL returned from ElevenLabs');
          return false;
        }

        const player = createAudioPlayer(result.audioUrl);
        playerRef.current = player;

        player.addListener('playbackStatusUpdate', (status) => {
          if (status.isLoaded && status.didJustFinish && myGen === speechGenRef.current) {
            setIsPlaying(false);
          }
        });

        player.play();
        setIsPlaying(true);
        return true;
      } catch (e) {
        if (myGen !== speechGenRef.current) return false;
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
    [stopAllPlayback]
  );

  const stopSpeaking = useCallback(async () => {
    stopAllPlayback();
    setIsPlaying(false);
  }, [stopAllPlayback]);

  const speakWithFallback = useCallback(
    async (text: string, config?: Partial<ElevenLabsTTSConfig>): Promise<boolean> => {
      stopAllPlayback();
      const myGen = speechGenRef.current;
      setError(null);
      setLastSpokenText(text);

      if (isTtsConfigured()) {
        try {
          const result = await speak(text, config);
          if (myGen !== speechGenRef.current) return false;
          if (result.audioUrl === undefined) {
            throw new Error('No audio URL returned from ElevenLabs');
          }

          const player = createAudioPlayer(result.audioUrl);
          playerRef.current = player;

          player.addListener('playbackStatusUpdate', (status) => {
            if (status.isLoaded && status.didJustFinish && myGen === speechGenRef.current) {
              setIsPlaying(false);
            }
          });

          player.play();
          setIsPlaying(true);
          return true;
        } catch (e) {
          if (myGen !== speechGenRef.current) return false;
          console.warn('ElevenLabs TTS failed, falling back to expo-speech:', e);
        }
      }

      try {
        await Speech.speak(text, {
          language: 'en-US',
          pitch: 1.0,
          rate: 0.9,
          onStart: () => {
            if (myGen === speechGenRef.current) setIsPlaying(true);
          },
          onDone: () => {
            if (myGen === speechGenRef.current) setIsPlaying(false);
          },
          onError: (e) => {
            if (myGen !== speechGenRef.current) return;
            setError(`Speech fallback failed: ${e.message}`);
            setIsPlaying(false);
          },
        });
      } catch (e) {
        if (myGen !== speechGenRef.current) return false;
        setError(`expo-speech failed: ${e instanceof Error ? e.message : String(e)}`);
        setIsPlaying(false);
      }
      return true;
    },
    [stopAllPlayback]
  );

  const stopSpeakingAll = useCallback(async () => {
    stopAllPlayback();
    setIsPlaying(false);
  }, [stopAllPlayback]);

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

  const transcribeWithFallback = useCallback(
    async (
      audioBlob: Blob,
      config?: Partial<ElevenLabsSTTConfig>
    ): Promise<string | null> => {
      setError(null);
      setIsRecording(true);

      if (isSttConfigured()) {
        try {
          const result = await transcribe(audioBlob, config);
          setLastTranscribedText(result.text);
          setIsRecording(false);
          return result.text;
        } catch (e) {
          console.warn('ElevenLabs STT failed, no fallback available:', e);
          setError(e instanceof Error ? e.message : String(e));
          setIsRecording(false);
          return null;
        }
      }

      setError('ElevenLabs not configured and no builtin fallback available');
      setIsRecording(false);
      return null;
    },
    []
  );

  const clearElevenLabsCache = useCallback(() => {
    clearCache();
  }, []);

  useEffect(() => {
    return () => {
      if (playerRef.current) {
        playerRef.current.remove();
      }
    };
  }, []);

  return {
    isConfigured,
    isPlaying,
    isRecording,
    lastSpokenText,
    lastTranscribedText,
    error,
    speakText,
    speakWithFallback,
    stopSpeaking,
    stopSpeakingAll,
    transcribeAudio,
    transcribeWithFallback,
    clearCache: clearElevenLabsCache,
  };
}
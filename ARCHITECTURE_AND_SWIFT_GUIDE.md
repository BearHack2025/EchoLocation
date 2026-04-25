# Architecture And Minimum Swift Guide

## Overview

This document explains:

- the smallest amount of `Swift` needed for the project
- the one-page architecture for the app
- the file-by-file breakdown of what to build first

This project should follow a simplicity-first rule:

- use existing abstractions if they already solve the problem
- avoid custom infrastructure unless the platform forces it
- keep the Swift layer as small as possible

The goal is to make the native iOS part feel manageable. You do not need to build the whole app in Swift. You only need Swift for the pieces that `React Native` cannot do well, mainly `ARKit`, LiDAR depth access, and native event emission.

## Do We Need Swift?

Yes, for this project you should assume you need some `Swift`.

You do not need to write the entire app in Swift. The recommended split is:

- `React Native` for UI, controls, mode switching, and app state
- `Swift` for `ARKit`, LiDAR depth, scene understanding, and feedback logic

Why:

- `ARKit` is an Apple-native framework
- LiDAR APIs are iOS-native
- the real-time sensor loop is performance-sensitive
- the depth data and mesh classification are much easier to control in native code

So the correct mental model is:

- `React Native` is the app shell
- `Swift` is the sensing engine

The goal is not to write a lot of Swift. The goal is to write the smallest possible Swift layer that unlocks `ARKit`.

## Smallest Amount Of Swift You Need

You only need a small native surface area:

1. a module file that exposes `start`, `stop`, and support checks
2. a session manager that runs `ARSession`
3. a frame handler that reads LiDAR depth
4. a simple event emitter that sends `distance`, `direction`, and `label` to React Native

That is enough for a real MVP.

## Minimum Swift Example

### Native Module

This is the rough minimum shape of the native bridge:

```swift
import ExpoModulesCore
import ARKit

public final class EchoLidarModule: Module {
  private let sessionController = EchoLidarSession()

  public func definition() -> ModuleDefinition {
    Name("EchoLidar")

    Events("onEchoUpdate")

    Function("isSupported") {
      ARWorldTrackingConfiguration.isSupported
    }

    Function("supportsDepth") {
      ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
    }

    AsyncFunction("start") { [weak self] in
      try self?.sessionController.start(sendEvent: { name, payload in
        self?.sendEvent(name, payload)
      })
    }

    AsyncFunction("stop") { [weak self] in
      self?.sessionController.stop()
    }
  }
}
```

### Session Manager

This owns the `ARSession` and emits simplified results:

```swift
import ARKit

final class EchoLidarSession: NSObject, ARSessionDelegate {
  private let session = ARSession()
  private var sendEvent: ((String, [String: Any]) -> Void)?

  func start(sendEvent: @escaping (String, [String: Any]) -> Void) throws {
    guard ARWorldTrackingConfiguration.isSupported else { return }
    guard ARWorldTrackingConfiguration.supportsFrameSemantics([.smoothedSceneDepth]) else { return }

    self.sendEvent = sendEvent
    session.delegate = self

    let config = ARWorldTrackingConfiguration()
    config.frameSemantics = [.smoothedSceneDepth]
    session.run(config)
  }

  func stop() {
    session.pause()
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard frame.smoothedSceneDepth != nil else { return }

    let payload: [String: Any] = [
      "nearestDistanceMeters": 1.2,
      "direction": "center",
      "label": "obstacle",
      "confidence": 0.8
    ]

    sendEvent?("onEchoUpdate", payload)
  }
}
```

At first, the payload can be fake. Once the native bridge works, replace it with real depth analysis.

### JavaScript Wrapper

This is the React Native side of the bridge:

```ts
import { EventEmitter, requireNativeModule } from 'expo-modules-core';

const EchoLidar = requireNativeModule('EchoLidar');
const emitter = new EventEmitter(EchoLidar);

export const startEcho = () => EchoLidar.start();
export const stopEcho = () => EchoLidar.stop();
export const isSupported = () => EchoLidar.isSupported();

export const subscribeEcho = (cb: (event: any) => void) =>
  emitter.addListener('onEchoUpdate', cb);
```

This is enough to connect the native LiDAR code to the React Native UI.

## One-Page Architecture

```txt
React Native App
  -> Home screen
  -> Mode switcher
  -> Settings
  -> Debug UI
  -> listens for native events

Expo Module Bridge
  -> start()
  -> stop()
  -> isSupported()
  -> onEchoUpdate

Swift / iOS Layer
  -> ARKit session
  -> LiDAR depth reading
  -> confidence filtering
  -> left/center/right inference
  -> mesh classification
  -> ML Kit handoff for object hints
  -> Gemma handoff for scene summary
  -> ElevenLabs playback path
  -> speech/haptics

Outputs
  -> distance
  -> direction
  -> label
  -> confidence
  -> spoken cue / haptic cue
```

## What Each Layer Does

### React Native Layer

Responsibilities:

- show the main screen
- let the user start or stop scanning
- let the user switch between modes
- display debug values for testing and demos
- listen for summarized native events

This layer should not process raw depth frames.

### Native Swift Layer

Responsibilities:

- start the `ARSession`
- read `sceneDepth` or `smoothedSceneDepth`
- use confidence data to reject weak pixels
- estimate nearest obstacle distance
- infer direction such as left, center, or right
- attach a coarse label from mesh classification when available
- hand off structured detections to `ML Kit`, `Gemma`, and `ElevenLabs` flows
- emit compact events to JavaScript

This layer should own all real-time sensing logic.

## File-By-File Breakdown

Recommended project layout:

```txt
echolocation/
  app/
    index.tsx
  components/
    StatusCard.tsx
    Controls.tsx
  hooks/
    useEchoLidar.ts
  modules/
    echo-lidar/
      src/
        EchoLidar.ts
      ios/
        EchoLidarModule.swift
        EchoLidarSession.swift
        DepthAnalyzer.swift
        SpeechController.swift
  ios/
  app.json
  package.json
```

### `app/index.tsx`

Purpose:

- main screen
- start / stop controls
- current mode
- current distance
- current direction
- current label

This is the first React Native screen.

### `components/StatusCard.tsx`

Purpose:

- display the current sensor state clearly

Show:

- distance
- direction
- label
- confidence

### `components/Controls.tsx`

Purpose:

- start button
- stop button
- mode selector

### `hooks/useEchoLidar.ts`

Purpose:

- subscribe to native events
- keep the latest sensor state in React state
- expose helper methods to the UI

### `modules/echo-lidar/src/EchoLidar.ts`

Purpose:

- JavaScript wrapper around the native module
- defines exported methods such as:
  - `start`
  - `stop`
  - `isSupported`
  - `subscribeToEcho`

### `modules/echo-lidar/ios/EchoLidarModule.swift`

Purpose:

- the native bridge entry point
- exposes functions and events to React Native

This file should stay small.

### `modules/echo-lidar/ios/EchoLidarSession.swift`

Purpose:

- owns the `ARSession`
- configures `ARKit`
- receives updated frames
- hands those frames to your analyzer

### `modules/echo-lidar/ios/DepthAnalyzer.swift`

Purpose:

- convert raw depth data into:
  - nearest obstacle distance
  - left / center / right direction
  - confidence

This is where the important logic lives.

Recommended behavior:

- use `smoothedSceneDepth`
- divide the image into broad zones
- ignore low-confidence pixels
- compute a stable value instead of using the raw minimum

### `modules/echo-lidar/ios/SpeechController.swift`

Purpose:

- speak short cues
- throttle repeated announcements
- handle haptics or beep timing

This should keep the user experience from becoming noisy or overwhelming.

## What To Build First

Build in this order.

### Step 1: Basic UI

Create:

- `app/index.tsx`
- `components/Controls.tsx`
- `components/StatusCard.tsx`

Goal:

- show a basic screen with Start, Stop, and placeholder sensor values

### Step 2: JavaScript Module Wrapper

Create:

- `modules/echo-lidar/src/EchoLidar.ts`

Goal:

- define the JS API that the rest of the app will use

### Step 3: Native Bridge

Create:

- `modules/echo-lidar/ios/EchoLidarModule.swift`

Goal:

- expose:
  - `isSupported`
  - `supportsDepth`
  - `start`
  - `stop`
  - `onEchoUpdate`

### Step 4: AR Session Manager

Create:

- `modules/echo-lidar/ios/EchoLidarSession.swift`

Goal:

- start an `ARSession`
- emit fake test events first

This is the easiest way to validate the bridge before doing real depth work.

### Step 5: Depth Analysis

Create:

- `modules/echo-lidar/ios/DepthAnalyzer.swift`

Goal:

- replace fake events with real:
  - distance
  - direction
  - confidence

### Step 6: Speech And Haptics

Create:

- `modules/echo-lidar/ios/SpeechController.swift`

Goal:

- speak short feedback
- add haptics or echo beeps
- rate-limit repeated announcements

### Step 7: Required AI Describe Flow

Add:

- mesh classification with `ARKit`
- `Google ML Kit` object labeling
- `Gemma` scene summarization
- `ElevenLabs` playback

Goal:

- improve phrases from:
  - "obstacle ahead"
  - to "table right"
  - and provide a richer track-demo description on demand

## What The MVP Actually Does

The first working version should do only this:

- scan with LiDAR
- find the nearest obstacle
- estimate whether it is left, center, or right
- report distance
- provide spoken or haptic feedback

That is enough for a strong hackathon demo.

Do not start with arbitrary object recognition or advanced AI summaries. The MVP should be:

- fast
- understandable
- stable enough to demo indoors

## What To Avoid Early

Avoid these in the first version:

- exact angle estimation
- full scene narration
- cloud AI in the real-time loop
- arbitrary object recognition as a dependency for the MVP
- Android support
- custom infrastructure that duplicates existing SDK behavior

These will add complexity much faster than they add demo value.

## Key Takeaway

You do not need a lot of Swift.

You need:

- one small native module
- one AR session manager
- one depth analyzer

Everything else can stay in `React Native`.

That is the cleanest and lowest-risk way to build this app.

The standard to keep applying is:

- if Apple already provides it, use Apple
- if Expo already abstracts it, use Expo
- if a stable SDK already solves it, use that
- only write custom logic for the narrow gap in the middle

## ElevenLabs Integration

This project uses ElevenLabs for premium voice output (TTS) with different voices for Echo and Describe modes. For continuous LiDAR feedback, the app uses built-in iOS TTS to reduce API usage.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EchoLidarSession (Swift)                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              SpeechController (Coordinator)                  ││
│  │  • Throttles/debounces speech                                 ││
│  │  • Formats text into phrases                                 ││
│  │  • useBuiltinSpeech flag controls routing:                   ││
│  │    - true: AVSpeechSynthesizer (built-in, zero cost)         ││
│  │    - false: JS layer for ElevenLabs                          ││
│  └─────────────────────────────────────────────────────────────┘│
│                              ↓ onSpeechRequest event (useBuiltin=false)
│                    JS Layer (Expo)                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              audio-service.ts (Voice Router)                 ││
│  │  • speakWithFallback(text, mode)                              ││
│  │  • Voice config by mode (echo vs describe)                    ││
│  │  • Timeout handling (5s)                                     ││
│  │  • preferBuiltinForContinuous config option                  ││
│  └─────────────────────────────────────────────────────────────┘│
│                              ↓                                   │
│  ┌──────────────────────────────┐  ┌──────────────────────────┐│
│  │  ElevenLabs TTS (Commands)  │  │  Builtin iOS TTS         ││
│  │  Echo: Rachel voice         │  │  (Continuous feedback)   ││
│  │  Describe: Arnold voice     │  │  AVSpeechSynthesizer     ││
│  └──────────────────────────────┘  └──────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Voice Configuration

| Mode | Voice ID | Voice Name | Purpose |
|------|----------|------------|---------|
| **Echo** | `21m00Tcm4TlvDq8ikWAM` | Rachel | Quick, clear status updates |
| **Describe** | `EXw4nqY7xTfnS2A7P8xL` | Arnold | Rich, detailed descriptions |

### Implementation Files

| File | Purpose |
|------|---------|
| `src/services/audio-logger.ts` | Structured logging to console |
| `src/services/audio-service.ts` | Voice router, TTS/STT functions, fallback logic |
| `src/services/elevenlabsTts.ts` | ElevenLabs TTS API integration |
| `src/services/elevenlabsStt.ts` | ElevenLabs STT WebSocket client |
| `src/hooks/use-echo-lidar.ts` | Speech request handler, hybrid TTS support |
| `modules/echo-lidar/ios/SpeechController.swift` | Swift speech coordinator, built-in TTS routing |
| `modules/echo-lidar/ios/VoiceCommandController.swift` | Swift voice command recognition |
| `modules/echo-lidar/ios/EchoLidarModule.swift` | Native module with TTS config functions |
| `modules/echo-lidar/ios/EchoLidarSession.swift` | AR session with TTS mode configuration |
| `modules/echo-lidar/src/EchoLidarModule.ts` | JS native module wrapper |

### API Key Configuration

**Environment variable (recommended - not committed to repo):**

```
EXPO_PUBLIC_ELEVENLABS_API_KEY=your_api_key_here
```

The API key is stored in `.env` file and NOT in `app.json` (to prevent accidental commits).

### Logging

All audio requests are logged to the console with structured format:

```
[Audio] source=elevenlabs-tts level=info status=success text="right, very close" latency=450ms mode=echo ts=2026-04-25T...
[Audio] source=builtin-ios level=warn status=success text="right, very close" error="ElevenLabs unavailable: timeout" mode=echo ts=2026-04-25T...
```

Log sources: `elevenlabs-tts`, `elevenlabs-stt`, `expo-speech`, `builtin-ios`

### Usage

```typescript
import { speakWithFallback } from '@/services/audio-service';

// Text-to-Speech with fallback
const audioUrl = await speakWithFallback('Object detected: chair, 2 meters ahead', 'describe');
```

### Swift-JS Bridge

Speech requests flow through events with two modes:

**Mode 1: Built-in TTS (useBuiltinSpeech=true)**
- Swift handles speech directly via AVSpeechSynthesizer
- No JS bridge calls, no ElevenLabs API usage
- Used for continuous LiDAR feedback

**Mode 2: ElevenLabs (useBuiltinSpeech=false)**
1. **Swift → JS**: `onSpeechRequest` event with `{ text, mode }`
2. **JS → Swift**: `onSpeechReady(audioUrl)` or `onSpeechFailed(error)`
3. Swift plays the audio via AVAudioPlayer

**Default behavior**: `useBuiltinSpeech=true` (uses built-in TTS by default)

### Voice I/O Summary

This project handles both voice input (speech recognition) and voice output (text-to-speech).

| Direction | Technology | When Used |
|-----------|------------|-----------|
| **Input (voice commands)** | iOS SFSpeechRecognizer | Primary - always available |
| **Input (voice commands)** | ElevenLabs Scribe | Optional - higher accuracy (WebSocket streaming) |
| **Output (voice commands)** | ElevenLabs TTS | Premium voice responses |
| **Output (continuous)** | iOS AVSpeechSynthesizer | Free, instant LiDAR feedback |

### Voice Input Flow

Voice commands are captured in Swift using VoiceCommandController:

1. **Capture**: iOS AVAudioEngine records microphone input
2. **Recognize**: SFSpeechRecognizer processes audio in real-time
3. **Match**: Transcript is matched against known commands (left, right, ahead, repeat)
4. **Emit**: `onVoiceCommand` event sent to JS layer

### Voice Output Flow

Speech is handled through the SpeechController in Swift with two paths:

1. **Built-in**: AVSpeechSynthesizer handles speech directly in Swift
2. **ElevenLabs**: onSpeechRequest event → JS audio-service → native playback

**Fallback triggers**: Builtin iOS `AVSpeechSynthesizer` when:
- `useBuiltinSpeech=true` (always uses builtin)
- ElevenLabs API is not configured
- Network timeout (>5 seconds)
- API returns error
- No internet connection

### What To Avoid

- Do not stream audio continuously (cost)
- Do not use ElevenLabs for real-time obstacle warnings without fallback (latency/connectivity)
- Do not commit API keys to version control
- Do not disable built-in TTS for continuous feedback (unnecessary API costs)

## ElevenLabs STT Integration

This project uses ElevenLabs for speech-to-text (STT) to transcribe voice commands. The implementation uses WebSocket streaming for real-time transcription.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              VoiceCommandController (Swift)                     │
│  • Uses iOS SFSpeechRecognizer for voice capture                │
│  • Runs speech recognition loop continuously                  │
│  • Matches transcript against known commands                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓ onVoiceCommand
┌─────────────────────────────────────────────────────────────────┐
│                    audio-service.ts                              │
│  • startRealtimeSTT(callbacks)  - Connect to ElevenLabs WebSocket│
│  • sendSTTAudioChunk(audio)     - Stream audio data              │
│  • commitSTT()                 - Signal end of speech          │
│  • stopRealtimeSTT()           - Disconnect                    │
└─────────────────────────────────────────────────────────────────┘
```

### STT Functions

| Function | Purpose |
|----------|---------|
| `startRealtimeSTT(callbacks)` | Connect to ElevenLabs WebSocket |
| `sendSTTAudioChunk(audioData: Int16Array)` | Stream audio to ElevenLabs |
| `commitSTT()` | Signal end of speech for final transcript |
| `stopRealtimeSTT()` | Disconnect WebSocket |
| `isSTTConnected()` | Check connection status |

### Callbacks

```typescript
interface RealtimeSTTCallbacks {
  onTranscript?: (text: string, isFinal: boolean) => void;
  onError?: (error: string) => void;
  onConnected?: () => void;
  onDisconnected?: () => void;
}
```

### Configuration

- **Model**: `scribe_v2_realtime`
- **Endpoint**: `wss://api.elevenlabs.io`
- **Timeout**: 10 seconds

### Usage

```typescript
const connected = await startRealtimeSTT({
  onTranscript: (text, isFinal) => {
    if (isFinal) {
      console.log('[STT] Final:', text);
    }
  },
  onConnected: () => console.log('[STT] Connected'),
  onError: (error) => console.error('[STT] Error:', error),
});

if (connected) {
  sendSTTAudioChunk(audioBuffer);
  commitSTT();
}
```

### Fallback

If ElevenLabs STT fails to connect or times out, the system falls back to iOS built-in speech recognition (SFSpeechRecognizer in VoiceCommandController.swift). The built-in recognizer is:

- Always available (no API key required)
- Works offline
- Free to use

The fallback happens automatically in the Swift layer.

## Hybrid TTS Strategy

To reduce ElevenLabs API usage while maintaining premium voice quality for important interactions, the app uses a hybrid approach:

### Strategy

| Context | TTS Engine | ElevenLabs Calls |
|---------|------------|------------------|
| **LiDAR continuous feedback** | Built-in iOS (AVSpeechSynthesizer) | **Zero** |
| **Voice commands** | ElevenLabs (premium voice) | Per command |
| **Announcements** | ElevenLabs (on-demand) | As requested |

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    EchoLidarSession (Swift)                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              SpeechController (Coordinator)                  ││
│  │  • Throttles/debounces speech                                 ││
│  │  • Formats text into phrases                                 ││
│  │  • useBuiltinSpeech flag controls routing:                   ││
│  │    - true: AVSpeechSynthesizer (free, local)                 ││
│  │    - false: JS layer for ElevenLabs                          ││
│  └─────────────────────────────────────────────────────────────┘│
│                              ↓ (when useBuiltin=false)          │
│                    JS Layer (Expo)                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              audio-service.ts (Voice Router)                 ││
│  │  • speakWithFallback(text, mode)                              ││
│  │  • ElevenLabs for voice commands/announcements               ││
│  │  • Builtin fallback for non-critical speech                  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Options

**In Swift (EchoLidarModule.swift):**

- `setBuiltinSpeechEnabled(enabled: Bool)` - Enable/disable built-in TTS
- `start(mode, useBuiltin)` - Start session with TTS preference

**In TypeScript (use-echo-lidar.ts):**

```typescript
// Use built-in for LiDAR (default - saves ElevenLabs credits)
const { start, speakCommand } = useEchoLidar();
await start('describe', true);  // true = use built-in TTS

// Voice commands can still use ElevenLabs
await speakCommand("What is my battery level?");

// Use premium voice for everything
await start('describe', false);  // false = use ElevenLabs
```

**In audio-service.ts:**

```typescript
configureAudioService({
  preferBuiltinForContinuous: true,  // Default: true
  useElevenLabs: true,               // Default: true
  useFallback: true                  // Default: true
});

// Check if builtin should be used
shouldUseBuiltinForContinuous();  // Returns true/false
shouldUseElevenLabs('continuous');  // Returns false if preferBuiltinForContinuous
shouldUseElevenLabs('command');      // Returns true if configured
```

### Built-in Speech Parameters

SpeechController configures AVSpeechSynthesizer with:

- **Rate**: 0.5 (moderate speed, clear articulation)
- **Pitch**: 1.0 (natural)
- **Voice**: en-US
- **Audio Session**: `.playback` mode with `.duckOthers` and `.interruptSpokenAudioAndMixWithOthers`

### Benefits

- **90%+ reduction** in ElevenLabs TTS calls during continuous LiDAR operation
- No change in voice quality for voice commands (still uses ElevenLabs)
- Immediate speech playback (no network latency)
- Works offline (built-in TTS doesn't require internet)

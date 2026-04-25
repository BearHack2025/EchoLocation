# Echolocation Hackathon Tasks

## Goal

Build an iOS-only accessibility prototype that uses LiDAR to estimate nearby obstacles and surfaces, then communicates those results through speech, haptics, or beeps.

The hackathon target is not full navigation. The target is a stable short-range awareness demo.

## Simplicity Rule

Use the highest-level existing abstraction that still gives you the required control.

Preference order:

1. Apple framework
2. Expo abstraction
3. well-supported third-party SDK
4. small custom native code
5. custom AI or infrastructure

Apply that rule everywhere:

- use `ARKit` for depth and coarse labels
- use `AVSpeechSynthesizer` for speech first
- use `Expo Modules API` for the bridge
- use `Google ML Kit` before custom vision models
- keep `Gemma` and `ElevenLabs` out of the fast feedback loop, but treat them as required track features

## Track Requirements

To compete for the intended sponsor tracks, the delivered demo must visibly include:

1. `Google ML Kit` for object detection or image labeling
2. `Gemma 3` or `Gemma 3n` for scene reasoning or summarization
3. `ElevenLabs` for premium voice output or voice interaction

These are not stretch goals in this plan. They are required demo integrations.

## MVP Definition

The MVP is complete when the app can:

- run on a LiDAR-capable iPhone
- start a working `ARKit` session
- estimate nearest obstacle distance
- estimate rough direction as `left`, `center`, or `right`
- provide spoken or haptic feedback
- remain stable enough for an indoor demo

## Scope Rules

Always protect these priorities:

1. support checks
2. stable distance detection
3. usable feedback
4. demo reliability

Deprioritize or cut:

1. arbitrary object recognition
2. advanced settings
3. visual polish that does not improve the demo
4. cloud AI integrations
5. any custom system that duplicates an existing SDK

## Build Order

## Phase 0: Project Setup

### Task 0.1: Confirm Hardware

- verify you have a real LiDAR-capable iPhone or iPad
- verify you have a Mac with `Xcode`
- verify you can run apps on the phone from Xcode

Definition of done:

- physical device available
- code signing works

### Task 0.2: Create App Shell

- create Expo app
- generate iOS project with prebuild
- install pods
- run a blank build on device

Suggested commands:

```bash
npx create-expo-app@latest --template default@sdk-55 echolocation
cd echolocation
npx expo prebuild --clean
npx pod-install
```

Definition of done:

- app launches on phone

### Task 0.3: Add Local Native Module

- create local Expo module
- name it `echo-lidar`
- verify the module is included in the iOS project

Suggested command:

```bash
npx create-expo-module@latest --local
```

Definition of done:

- Swift module builds successfully

## Phase 1: Basic React Native UI

### Task 1.1: Create Main Screen

Create:

- `app/index.tsx`

Requirements:

- start button
- stop button
- current mode
- placeholder distance
- placeholder direction
- placeholder label

Definition of done:

- app displays the main controls and status layout

### Task 1.2: Create Reusable UI Components

Create:

- `components/Controls.tsx`
- `components/StatusCard.tsx`

Requirements:

- controls separated from status display
- clean enough for a hackathon demo

Definition of done:

- UI is readable and easy to demo

### Task 1.3: Add Lidar Hook

Create:

- `hooks/useEchoLidar.ts`

Requirements:

- maintain latest sensor event in React state
- expose `start`, `stop`, and support flags

Definition of done:

- UI can connect to the future native module cleanly

## Phase 2: Native Bridge

### Task 2.1: JavaScript Wrapper For Native Module

Create:

- `modules/echo-lidar/src/EchoLidar.ts`

Requirements:

- export `isSupported`
- export `supportsDepth`
- export `start`
- export `stop`
- export event subscription helper

Definition of done:

- React Native code imports a stable JS API

### Task 2.2: Native Module Entry Point

Create:

- `modules/echo-lidar/ios/EchoLidarModule.swift`

Requirements:

- expose `isSupported`
- expose `supportsDepth`
- expose `start`
- expose `stop`
- emit `onEchoUpdate`

Definition of done:

- app builds with the native module included

### Task 2.3: Emit Fake Test Events

Create or update:

- `modules/echo-lidar/ios/EchoLidarSession.swift`

Requirements:

- on `start`, emit fake values every short interval
- send:
  - distance
  - direction
  - label
  - confidence

Definition of done:

- tapping start updates the React Native UI with fake native data

## Phase 3: Device Support And Permissions

### Task 3.1: Add Camera Permission

Update:

- iOS app config / `Info.plist`

Requirements:

- add `NSCameraUsageDescription`

Definition of done:

- permission prompt appears correctly

### Task 3.2: Support Checks

Implement:

- `ARWorldTrackingConfiguration.isSupported`
- `supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])`
- optional scene reconstruction support check

Definition of done:

- app can clearly say whether the current device supports the needed features

## Phase 4: Real AR Session

### Task 4.1: Start ARKit Session

Update:

- `modules/echo-lidar/ios/EchoLidarSession.swift`

Requirements:

- create `ARSession`
- set session delegate
- configure `ARWorldTrackingConfiguration`
- enable `.smoothedSceneDepth`

Definition of done:

- session starts on device without crashing

### Task 4.2: Read Frame Depth

Requirements:

- read `frame.smoothedSceneDepth`
- handle missing depth safely

Definition of done:

- native code sees live depth frames

### Task 4.3: Log Or Inspect Raw Values

Requirements:

- confirm depth values change as objects move
- confirm the data is plausible indoors

Definition of done:

- you have proof that real depth is streaming

## Phase 5: Distance And Direction

### Task 5.1: Create Depth Analyzer

Create:

- `modules/echo-lidar/ios/DepthAnalyzer.swift`

Requirements:

- accept depth and confidence maps
- split the frame into:
  - left
  - center
  - right
- compute stable distance per zone

Definition of done:

- analyzer returns a nearest obstacle summary

### Task 5.2: Add Confidence Filtering

Requirements:

- ignore low-confidence pixels
- avoid noisy edge values

Definition of done:

- results are less jumpy than raw minima

### Task 5.3: Infer Primary Direction

Requirements:

- decide whether the nearest obstacle is left, center, or right
- fall back to `unknown` when the reading is weak

Definition of done:

- app emits believable direction values

### Task 5.4: Emit Real Events

Requirements:

- replace fake events with real analyzer output

Definition of done:

- UI updates with live:
  - distance
  - direction
  - confidence

## Phase 6: Feedback Layer

### Task 6.1: Add Speech Controller

Create:

- `modules/echo-lidar/ios/SpeechController.swift`

Requirements:

- speak short phrases
- throttle repeated speech
- avoid constant repetition

Definition of done:

- app gives short spoken cues without becoming unusable

### Task 6.2: Add Haptics Or Beeps

Requirements:

- create distance-based feedback
- closer obstacles should feel more urgent

Definition of done:

- user gets non-visual feedback even without speech

### Task 6.3: Add Modes

Modes:

- `Echo`
- `Describe`
- `Quiet`

Requirements:

- connect mode selection from React Native to native behavior

Definition of done:

- switching mode changes the feedback style

## Phase 7: Scene Labels

### Task 7.1: Enable Scene Reconstruction

Requirements:

- if supported, enable `.meshWithClassification`

Definition of done:

- app can access mesh anchors on supported devices

### Task 7.2: Map Mesh Classifications

Requirements:

- support labels such as:
  - wall
  - floor
  - table
  - seat
  - door
  - window
- map unknown classifications to `obstacle`

Definition of done:

- app can attach coarse scene labels to some detections

### Task 7.3: Merge Labels With Distance Events

Requirements:

- combine label, distance, and direction into one event payload
- only speak labels when reasonably stable

Definition of done:

- spoken phrases improve from `obstacle ahead` to `table right`

## Phase 8: Google ML Kit Object Detection

### Task 8.1: Integrate Google ML Kit

Requirements:

- add iOS ML Kit dependency
- choose either object detection or image labeling first

Definition of done:

- model runs on-device

### Task 8.2: Crop Relevant Camera Region

Requirements:

- use LiDAR result to choose the likely relevant part of the camera frame
- avoid running labels on the whole image when possible

Definition of done:

- object labels are more likely to match the nearest object

### Task 8.3: Stabilize Object Labels

Requirements:

- smooth labels across multiple frames
- do not announce unstable low-confidence guesses

Definition of done:

- app can say phrases like `possible chair ahead`

## Phase 9: Gemma Summarization

### Task 9.1: Add Gemma Summarization

Requirements:

- use structured detections as input
- generate short scene summaries
- do not place Gemma in the fast obstacle warning loop

Definition of done:

- app can produce a richer summary on demand during the demo

## Phase 10: ElevenLabs Voice

### Task 10.1: Add ElevenLabs Environment Setup

**Requirements**:

- add `EXPO_PUBLIC_ELEVENLABS_API_KEY` to `app.json` or `.env` file
- create `.env.example` with placeholder

**Definition of done**:

- API key is configurable without hardcoding

### Task 10.2: Create ElevenLabs TTS Service

**Files to create**:

- `src/services/elevenlabsTts.ts`

**Requirements**:

- implement `speak(text, config)` that calls ElevenLabs Text-to-Speech API
- implement audio caching for repeated phrases
- expose `isConfigured()` check

**Definition of done**:

- TTS service generates audio from ElevenLabs

### Task 10.3: Create ElevenLabs STT Service

**Files to create**:

- `src/services/elevenlabsStt.ts`

**Requirements**:

- implement `transcribe(audioBlob)` that calls ElevenLabs Scribe API
- handle FormData upload for audio files

**Definition of done**:

- STT service transcribes audio to text

### Task 10.4: Create ElevenLabs Hook

**Files to create**:

- `src/hooks/useElevenLabs.ts`

**Requirements**:

- integrate with expo-av for audio playback
- provide `speakText()` function
- provide `transcribeAudio()` function

**Definition of done**:

- React components can use ElevenLabs through the hook

### Task 10.5: Add ElevenLabs Voice

Requirements:

- replace or supplement built-in speech with higher-quality voice output
- use only if latency is acceptable

Definition of done:

- richer spoken responses work reliably in demo conditions

### Task 10.6: Add One Explicit AI Demo Action

Requirements:

- add one button or voice prompt such as:
  - `Describe Scene`
  - `What is in front of me?`
- route that flow through `ML Kit -> Gemma -> ElevenLabs`

Definition of done:

- judges can clearly see the sponsor integrations being exercised

## Phase 11: Demo Polish

### Task 10.1: Improve Demo UI

Requirements:

- clear mode indicator
- readable debug values
- obvious start and stop flow

Definition of done:

- judges can understand what the app is doing

### Task 10.2: Tune Thresholds

Requirements:

- test in one controlled indoor environment
- adjust speech timing
- adjust distance thresholds
- reduce noisy announcements

Definition of done:

- demo path works consistently

### Task 10.3: Rehearse Demo

Requirements:

- define one exact demo path
- define one exact script
- test against the same room setup repeatedly

Definition of done:

- the demo can be repeated reliably

## Recommended File Checklist

Create these first:

- `PROJECT_PLAN.md`
- `ARCHITECTURE_AND_SWIFT_GUIDE.md`
- `TASKS.md`
- `app/index.tsx`
- `components/Controls.tsx`
- `components/StatusCard.tsx`
- `hooks/useEchoLidar.ts`
- `modules/echo-lidar/src/EchoLidar.ts`
- `modules/echo-lidar/ios/EchoLidarModule.swift`
- `modules/echo-lidar/ios/EchoLidarSession.swift`
- `modules/echo-lidar/ios/DepthAnalyzer.swift`
- `modules/echo-lidar/ios/SpeechController.swift`

ElevenLabs integration files:

- `src/services/elevenlabsTts.ts` - TTS worker
- `src/services/elevenlabsStt.ts` - STT worker
- `src/hooks/useElevenLabs.ts` - React hook

## Daily Checklist

Use this each day during the hackathon.

### Day 1

- confirm device support
- scaffold Expo app
- prebuild iOS project
- create local native module
- run on real device
- connect fake native events to UI

### Day 2

- start AR session
- read depth frames
- implement distance analysis
- implement direction inference
- show live values in UI

### Day 3

- add speech
- add haptics or beeps
- add mesh labels if stable
- add `ML Kit`
- add `Gemma`
- add `ElevenLabs`
- polish demo flow
- rehearse final pitch

## Cut List

If time runs short, cut in this order:

1. advanced settings
2. visual polish
3. extra modes beyond the main demo path
4. mesh labels

Do not cut:

1. `ML Kit`
2. `Gemma`
3. `ElevenLabs`
4. support checks
5. distance detection
6. direction detection
7. feedback output
8. demo rehearsal

## Final Demo Checklist

Before presenting:

- phone is fully charged
- app launches cleanly
- camera permission is already granted
- support checks pass
- one room is chosen and rehearsed
- speech timing is not too noisy
- debug values are visible for judges
- there is a backup explanation if labels fail
- the `ML Kit -> Gemma -> ElevenLabs` demo path works at least once reliably

## Definition Of Success

This project is successful if it can do this reliably in a room:

- detect something nearby
- say roughly where it is
- estimate how close it is
- communicate that without overwhelming the user

That is enough for a strong hackathon prototype.

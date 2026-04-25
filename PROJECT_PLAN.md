# Echolocation LiDAR Accessibility Prototype

## Overview

This project is an iOS accessibility prototype intended for a hackathon. The app uses an iPhone or iPad with a LiDAR Scanner to estimate nearby obstacles and surfaces, then communicates that information through speech and haptics. The target audience is blind or low-vision users, but this must be treated as an experimental awareness aid, not a navigation or safety device.

The implementation rule for this project is:

- abstract as much as possible
- use existing frameworks and SDKs wherever they already solve the problem
- only write custom code where platform APIs do not provide the missing piece

The product goal is narrow:

- detect nearby obstacles in front of the user
- estimate rough direction such as left, center, or right
- provide short spoken cues such as "wall ahead, 1.2 meters"
- provide haptic or beep-based feedback as objects get closer
- optionally identify coarse scene classes such as wall, floor, table, seat, door, and window

The product should not promise:

- full navigation
- reliable recognition of arbitrary objects
- outdoor mobility safety
- replacement for a cane, guide dog, or orientation and mobility training

## Product Statement

Echolocation is a short-range spatial awareness prototype for iPhone LiDAR devices. It translates depth and scene understanding into audio and haptic cues to help a user understand what is directly nearby.

## Core User Experience

The user opens the app, points the phone outward, and receives feedback about what is directly ahead.

Three interaction modes are recommended:

- `Echo Mode`: sonar-like beeps whose frequency increases as obstacles get closer
- `Describe Mode`: brief spoken summaries such as "table right, one meter"
- `Quiet Mode`: haptics only

The app should stay minimal. The best hackathon experience is one screen with:

- start / stop scan
- current mode
- current nearest distance
- current direction
- current surface label if available
- debug text for judges and teammates

## Success Criteria

The MVP is successful if it can:

1. run on a LiDAR-capable iPhone
2. start an `ARKit` world-tracking session
3. read `sceneDepth` or `smoothedSceneDepth`
4. estimate nearest obstacle distance in front of the user
5. communicate that distance through sound or speech
6. avoid spamming the user with constant repeated announcements

The stretch version is successful if it can also:

1. infer left, center, or right obstacle direction
2. classify coarse surfaces with mesh reconstruction
3. add a polished demo mode and onboarding

## Recommended Tech Stack

### Final Recommendation

Use `React Native` for the app shell and `Swift` for the sensing engine.

### Simplicity-First Rule

Prefer this order of implementation:

1. built-in Apple frameworks
2. Expo abstractions
3. well-supported SDKs like `Google ML Kit`
4. small custom native code
5. custom AI logic only if the product still needs it

In practice, that means:

- use `ARKit` instead of building custom depth logic from scratch
- use `AVSpeechSynthesizer` instead of adding a network voice service for the MVP
- use `Expo Modules API` instead of building a larger manual bridge
- use `Google ML Kit` before considering custom object-detection models
- keep `Gemma` and `ElevenLabs` optional and outside the fast feedback loop

Recommended stack:

- `React Native` for screens and controls
- `Expo` for app scaffolding
- `Expo development build` instead of `Expo Go`
- `Expo Modules API` for the native iOS module
- `Swift` for the LiDAR and AR processing layer
- `ARKit` for depth and scene reconstruction
- `Google ML Kit` for optional camera-based object detection or image labeling
- `AVSpeechSynthesizer` for spoken feedback
- `Core Haptics` or standard UIKit haptics for tactile alerts

Optional AI services:

- `Gemma` for scene summarization or multimodal reasoning
- `ElevenLabs` for higher-quality voice output or voice input

### Why This Stack

`React Native` is not the easiest way to build the sensing logic itself. `Swift` is easier for that. However, `React Native + a native Swift module` is a good balance for a hackathon because:

- the UI can be built quickly
- the iOS-specific sensor work remains native
- Expo local modules provide a cleaner path than building a large bridge by hand
- the amount of custom native code can stay very small

### Explicit Recommendation

Do not use:

- pure JavaScript-only React Native for LiDAR processing
- `Expo Go` for the final project
- cloud object recognition for the MVP feedback loop
- Android support in the hackathon version

## Platform Scope

### Supported Platform

- iOS only

### Supported Hardware

- LiDAR-capable iPhone or iPad

### Unsupported or Deprioritized

- Android
- non-LiDAR iPhones
- iOS Simulator for actual AR testing

The iOS Simulator can help with UI work, but the actual AR functionality must be tested on a real device.

## High-Level Architecture

The app should be split into two layers.

### 1. React Native Layer

Responsibilities:

- home screen
- mode controls
- settings
- debug display
- status indicators
- accessibility-friendly UI text
- display of summarized events from native code

This layer should not process raw depth frames.

### 2. Native iOS Layer

Responsibilities:

- start and stop `ARSession`
- verify LiDAR and scene reconstruction support
- read `ARFrame.sceneDepth` or `smoothedSceneDepth`
- read confidence data
- optionally read mesh anchors and classifications
- estimate nearest stable obstacle distance
- estimate left, center, or right direction
- throttle spoken output
- emit compact events to JavaScript

This layer should own all real-time sensing and decision logic.

## Native Processing Design

### ARKit Session Configuration

Use `ARWorldTrackingConfiguration`.

Recommended options:

- `frameSemantics = [.smoothedSceneDepth]`
- if supported, enable `sceneReconstruction = .meshWithClassification`

Why:

- `smoothedSceneDepth` is more stable than raw `sceneDepth`
- mesh reconstruction can add useful coarse labels like wall, floor, or table

### Frame Analysis Strategy

Do not send raw depth buffers to JavaScript.

For each frame:

1. read the depth map
2. read the confidence map
3. split the visible frame into regions:
   - left
   - center
   - right
4. ignore low-confidence pixels
5. estimate a stable nearest distance using a percentile or filtered minimum
6. determine which region contains the closest reliable obstacle
7. if mesh labels are available, attach a coarse class
8. emit a compact update event

### Camera-Based Object Detection Strategy

If you want the app to say more than coarse LiDAR mesh labels such as wall or table, add a second vision pipeline using the camera feed.

Recommended approach:

1. use LiDAR depth to decide what region is nearest and relevant
2. crop the corresponding region from the camera image
3. run object detection or image labeling on that crop
4. combine the visual label with LiDAR distance before speaking

This is much better than running generic image labeling over the full frame because:

- it reduces noise
- it ties labels to the object directly in front of the user
- it makes spoken results more believable

### Suggested Event Payload

```ts
type EchoUpdate = {
  nearestDistanceMeters: number | null;
  direction: 'left' | 'center' | 'right' | 'unknown';
  label: 'wall' | 'floor' | 'table' | 'seat' | 'door' | 'window' | 'obstacle' | 'unknown';
  confidence: number;
  mode: 'echo' | 'describe' | 'quiet';
};
```

### Audio Feedback Rules

Speech should be short and rate-limited.

Example rules:

- only speak if the nearest obstacle is within `2.0 m`
- do not repeat the same phrase more than once every `1.5 to 2.5 seconds`
- prefer short messages over detailed descriptions
- interrupt less urgent speech when a much closer obstacle appears

Example phrases:

- "Obstacle ahead, 0.8 meters"
- "Wall left, 1.5 meters"
- "Table right, 1.0 meter"

### Haptic / Echo Feedback Rules

Example distance mapping:

- `> 2.5 m`: no feedback
- `1.5 m - 2.5 m`: slow pulse
- `0.8 m - 1.5 m`: medium pulse
- `< 0.8 m`: fast pulse or more urgent sound

## Data Flow

```txt
ARKit camera + LiDAR
  -> native Swift session manager
  -> depth/confidence filtering
  -> obstacle summary
  -> optional camera crop selection
  -> optional object detection / image labeling
  -> optional Gemma summarization layer
  -> optional mesh classification
  -> speech/haptic controller
  -> event emitter
  -> React Native UI
```

## AI Integration Options

This section explains where `Google object detection`, `Gemma`, and `ElevenLabs` fit in the product.

### Option 1: Google ML Kit

This is the easiest object-detection layer to add on iOS.

What it is good for:

- on-device object detection in video frames
- object tracking across frames
- coarse classification
- optional image labeling with a broader label set

Why it fits this project:

- it runs on-device
- it is easier to integrate than building a custom vision model from scratch
- it works well as a second signal alongside LiDAR

Important limitations:

- the standard object detector is coarse and can classify broad categories
- image labeling can return many labels, but those labels are not guaranteed to correspond to the exact nearest object
- camera-based labels are less reliable than distance data for safety-critical feedback

Best use in this app:

- use `ARKit` for distance and direction
- use `ML Kit` for possible object identity
- only speak labels when the result is stable across multiple frames

Recommended outputs:

- "obstacle ahead, 0.9 meters"
- "possible chair ahead, 1.1 meters"
- "table right, 1.3 meters"

### Option 2: Gemma

`Gemma` should not be the primary detector in the hackathon version. It is better used as a reasoning or summarization layer.

According to Google's current docs, the Gemma family includes multimodal variants, and `Gemma 3n` is optimized for mobile-class devices while accepting text, visual, and audio inputs. However, that does not automatically make it the easiest or most reliable real-time detector for this app.

Good uses for Gemma here:

- summarizing structured detections into natural speech
- answering a user-initiated question such as "what is in front of me?"
- generating cleaner scene descriptions from multiple inputs
- optional multimodal experimentation after the MVP works

Bad uses for Gemma here:

- continuous frame-by-frame obstacle detection in the safety loop
- replacing LiDAR distance estimation
- replacing on-device classical detection for the MVP

Recommended role:

- feed Gemma a compact JSON summary such as distance, direction, and candidate labels
- ask it to produce a short sentence
- use it only in a slower `Describe` action, not for every frame

Example structured input:

```json
{
  "nearest_distance_m": 1.0,
  "direction": "center",
  "mesh_label": "table",
  "camera_labels": ["desk", "table", "furniture"]
}
```

Example Gemma output:

- "There appears to be a table directly ahead about one meter away."

Practical recommendation:

- if you use Gemma in the hackathon, run it as an optional feature
- do not make the core demo depend on it

### Option 3: ElevenLabs

`ElevenLabs` is best treated as the voice layer, not the object detection layer.

What it is good for:

- high-quality text-to-speech
- speech-to-text
- conversational voice experiences

What it is not:

- a primary object detection API for this use case

If someone says ElevenLabs "tells you what object is in front of you", the missing part is that another vision system must first identify the object. ElevenLabs can then speak that result naturally.

Best use in this app:

- convert the final description into a high-quality voice response
- optionally support voice commands such as "describe scene" or "what is ahead?"

Why it is risky for the MVP:

- network dependency
- latency
- API cost
- privacy concerns because camera-derived information may leave the device
- less predictable behavior than built-in iOS speech

MVP recommendation:

- use `AVSpeechSynthesizer` first
- add `ElevenLabs` only if you want a more polished demo voice

## Final AI Stack Recommendation

For the hackathon version, the best stack is:

- `ARKit` for depth and direction
- `ARKit` mesh classification for coarse scene labels
- `Google ML Kit` for optional object labels from the camera feed
- `AVSpeechSynthesizer` for the main spoken feedback loop
- `Gemma` only for optional scene summarization
- `ElevenLabs` only for optional premium voice output or voice commands

This gives you the cleanest separation:

- `ARKit` answers: how far away and where
- `ML Kit` answers: what might it be
- `Gemma` answers: how should I phrase this
- `ElevenLabs` answers: how should it sound

## AI Feature Priorities

Build in this order:

1. LiDAR obstacle distance and direction
2. built-in iOS speech and haptics
3. mesh classification labels
4. Google ML Kit object detection or image labeling
5. Gemma summarization
6. ElevenLabs voice polish

If time is limited, stop after step 4.

## Development Setup

## Local Tooling

Required:

- macOS
- `Xcode`
- Xcode Command Line Tools
- `Node` LTS
- `Watchman`
- `CocoaPods`
- one real LiDAR-capable iPhone or iPad

Install core tools:

```bash
brew install node
brew install watchman
```

Create the project:

```bash
npx create-expo-app@latest --template default@sdk-55 echolocation
cd echolocation
```

Generate native projects:

```bash
npx expo prebuild --clean
npx pod-install
```

Create the local module:

```bash
npx create-expo-module@latest --local
```

Recommended module name:

- `echo-lidar`

### Why a Development Build

Use an Expo development build because:

- `Expo Go` cannot include your custom LiDAR native module
- you need your own native app binary
- you need Xcode rebuilds for Swift changes

### Daily Dev Loop

Run the JS bundler:

```bash
npx expo start
```

Open the iOS project:

```bash
xed ios
```

Workflow:

- edit TypeScript and React UI, then use fast refresh
- edit Swift native code, then rebuild from Xcode
- test AR behavior only on the real device

## Recommended Project Structure

```txt
echolocation/
  app/
    index.tsx
    settings.tsx
  components/
    StatusCard.tsx
    ModeSwitcher.tsx
  hooks/
    useEchoLidar.ts
  modules/
    echo-lidar/
      ios/
        EchoLidarModule.swift
        EchoLidarSession.swift
      src/
        EchoLidar.ts
      expo-module.config.json
  docs/
  ios/
  package.json
```

## Initial Native Module Shape

### JavaScript Wrapper

```ts
import { EventEmitter, requireNativeModule } from 'expo-modules-core';

const EchoLidar = requireNativeModule('EchoLidar');
const emitter = new EventEmitter(EchoLidar);

export function isSupported(): boolean {
  return EchoLidar.isSupported();
}

export function supportsDepth(): boolean {
  return EchoLidar.supportsDepth();
}

export async function start() {
  return EchoLidar.start();
}

export async function stop() {
  return EchoLidar.stop();
}

export function subscribeToEcho(listener: (event: unknown) => void) {
  return emitter.addListener('onEchoUpdate', listener);
}
```

### Swift Module Shape

```swift
import ExpoModulesCore
import ARKit
import AVFAudio

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

### Swift Session Controller Responsibilities

`EchoLidarSession.swift` should:

- own the `ARSession`
- conform to `ARSessionDelegate`
- analyze each frame
- convert raw depth into summarized events
- manage speech and haptic throttling

## Product Milestones

### Milestone 0: Validation

Goal:

- confirm the device supports the required AR features

Tasks:

- create the app shell
- verify code signing works in Xcode
- add camera usage description
- confirm `ARWorldTrackingConfiguration.isSupported`
- confirm `supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])`
- if needed, confirm `supportsSceneReconstruction(.meshWithClassification)`

Deliverable:

- a running development build on the real phone

### Milestone 1: Native Session Streaming

Goal:

- start AR and emit live summarized test events

Tasks:

- create the local Expo module
- wire event emitter from Swift to JS
- add start and stop controls in the UI
- emit fake test events first to validate the bridge

Deliverable:

- React Native screen receives native events

### Milestone 2: Depth-Based Obstacle Detection

Goal:

- detect nearest obstacle and report rough direction

Tasks:

- read depth map and confidence map
- divide frame into left, center, right zones
- filter low-confidence values
- compute stable distance per zone
- choose a primary obstacle direction

Deliverable:

- UI shows nearest distance and direction in real time

### Milestone 3: Audio and Haptics

Goal:

- turn sensing into usable feedback

Tasks:

- add `AVSpeechSynthesizer`
- add distance-based haptic or beep patterns
- rate-limit repeated speech
- avoid speaking if readings are weak or noisy

Deliverable:

- user can walk around a room and hear useful short-range cues

### Milestone 4: Scene Labels

Goal:

- add coarse labels when ARKit mesh classification supports them

Tasks:

- enable scene reconstruction if supported
- inspect nearby mesh anchors
- map `ARMeshClassification` values into user-facing labels
- only speak them when confidence is good enough

Deliverable:

- phrases like "wall ahead" or "table right"

### Milestone 5: Google Object Detection

Goal:

- add camera-based object hints beyond coarse ARKit mesh labels

Tasks:

- integrate `GoogleMLKit/ObjectDetection` or `GoogleMLKit/ImageLabeling`
- run detection on the relevant crop from the camera image
- stabilize results over multiple frames
- merge labels with LiDAR distance and direction
- avoid speaking low-confidence labels

Deliverable:

- phrases like "possible chair ahead" or "possible backpack right"

### Milestone 6: Optional AI Voice and Summarization

Goal:

- optionally improve the polish of spoken responses

Tasks:

- add a summarization layer using `Gemma`
- use it only for slower `Describe` mode or explicit user requests
- optionally add `ElevenLabs` for richer text-to-speech
- keep the real-time feedback loop independent of network AI

Deliverable:

- optional richer scene summaries without risking the main demo

### Milestone 7: Demo Polish

Goal:

- make the project understandable and stable for judges

Tasks:

- add mode switcher
- add onboarding screen
- add visible debug UI for demo observers
- tune wording and thresholds
- prepare one controlled demo environment

Deliverable:

- polished hackathon demo flow

## Hackathon Schedule

### Day 1

Focus:

- project creation
- native setup
- event bridge

Tasks:

- scaffold Expo app
- prebuild iOS project
- create local module
- run on real device
- validate support checks
- emit fake test events into React Native

End-of-day target:

- working dev build and native bridge

### Day 2

Focus:

- real sensing
- distance calculations

Tasks:

- start AR session
- read `smoothedSceneDepth`
- compute left, center, right obstacle distances
- display live results in UI
- start threshold tuning indoors

End-of-day target:

- live obstacle distance and direction updates

### Day 3

Focus:

- user feedback layer
- demo polish

Tasks:

- add speech
- add haptics
- add mode switching
- add scene labels
- add Google object detection only if the core loop is already stable
- add Gemma or ElevenLabs only if there is extra time
- rehearse controlled demo

End-of-day target:

- presentable accessibility prototype

## Accessibility and UX Principles

Because the audience includes blind users, the interaction design matters as much as the sensing.

Rules:

- keep spoken phrases short
- do not overload the user with constant messages
- prefer a small number of stable cues over rich narration
- design around one-handed use if possible
- make the UI screen-reader friendly, but assume the main interaction is auditory

Strong recommendation:

- if possible, get quick feedback from at least one blind or low-vision tester before demo day

## Limitations

### Hardware Limitations

- only works on LiDAR-capable iPhones and iPads
- cannot be meaningfully tested in the iOS Simulator
- battery and heat may become an issue with continuous AR use

### Sensor Limitations

- LiDAR depth is not a perfect full-resolution scene understanding system
- depth confidence varies across surfaces and lighting conditions
- shiny, transparent, dark, thin, and reflective objects can be difficult
- outdoor conditions can degrade quality

### Classification Limitations

- `ARMeshClassification` is coarse, not general object recognition
- it can classify categories like wall, floor, table, seat, door, and window
- it will not reliably identify arbitrary items like backpack, cup, cane, or laptop
- `ML Kit` object detection and image labeling are also not safety-grade object understanding
- camera-based labels can be wrong, unstable, or unrelated to the nearest object unless you tightly gate them with LiDAR

### AI Service Limitations

- `Gemma` adds complexity and should not sit inside the fast obstacle warning loop
- `ElevenLabs` requires network access for its hosted APIs and increases latency, cost, and privacy exposure
- any cloud AI service is a weak fit for the most time-sensitive accessibility feedback

### Product Limitations

- this is not a mobility safety system
- it should not be marketed as reliable navigation
- false positives and false negatives are expected
- blind users may find noisy or slow speech frustrating if not tuned carefully

### Engineering Limitations

- React Native is only suitable for the app shell here
- the real challenge lives in native iOS processing and feedback design
- adding camera-based object recognition would expand complexity significantly

## Risk Register

### Risk 1: Device Support Failure

Problem:

- the available demo phone may not support LiDAR features needed

Mitigation:

- verify `sceneDepth` and scene reconstruction support on day 1

### Risk 2: Audio Spam

Problem:

- too many updates make the app unusable

Mitigation:

- rate-limit speech
- use haptics or tones for continuous feedback
- reserve speech for meaningful changes

### Risk 3: Noisy Readings

Problem:

- raw minima fluctuate too much

Mitigation:

- use smoothed depth
- filter low-confidence pixels
- use percentiles or temporal smoothing

### Risk 4: Over-Scoping

Problem:

- arbitrary object recognition and navigation are too large for a hackathon

Mitigation:

- keep the promise narrow: short-range obstacle awareness

### Risk 5: Lack of User Validation

Problem:

- a technically impressive demo may still be unusable for blind users

Mitigation:

- keep the output simple
- test with accessibility expectations in mind
- state clearly that it is a prototype

## Stretch Goals

Only attempt these after the MVP works reliably.

- mode-specific audio profiles
- simple obstacle history smoothing
- visual debug overlay for judges
- saved threshold presets
- optional camera-based `ML Kit` classification for coarse object guesses
- optional `Gemma` scene summaries on demand
- optional `ElevenLabs` voice output for a more polished demo
- lightweight onboarding tutorial

## Features To Cut First If Time Runs Out

Cut in this order:

1. general object recognition
2. advanced settings
3. visual overlays
4. Gemma summarization
5. ElevenLabs integration
6. multiple scenes and fancy onboarding
7. mesh labels

Never cut:

1. support checks
2. stable distance estimation
3. speech or haptic output
4. controlled demo usability

## Demo Plan

Run the demo in a controlled indoor space with a few clear objects and surfaces.

Suggested demo script:

1. start in `Describe Mode`
2. point at a wall and hear "wall ahead"
3. rotate toward a table and hear "table right"
4. move forward to demonstrate closer haptic or beep feedback
5. switch to `Echo Mode`
6. show the debug UI to judges

Important:

- avoid crowded or reflective environments
- rehearse the exact path
- keep the demo under two minutes

## Post-Hackathon Next Steps

If the prototype works, the next steps are:

1. test with blind or low-vision users
2. refine audio vocabulary and interaction patterns
3. improve stability and confidence filtering
4. evaluate whether a full native Swift app is better than React Native long term
5. explore optional Vision or Core ML support for bounded object categories

## Final Scope Decision

The right hackathon scope is:

- iOS only
- LiDAR only
- short-range awareness only
- speech and haptic feedback only
- coarse scene labels only where ARKit already supports them

That scope is realistic. Anything larger is likely to collapse into a half-working demo.

## References

Official sources used for this plan:

- React Native environment setup: https://reactnative.dev/docs/set-up-your-environment
- Expo create project: https://docs.expo.dev/get-started/create-a-project/
- Expo development builds: https://docs.expo.dev/develop/development-builds/introduction/
- Expo Modules API: https://docs.expo.dev/modules/get-started/
- Apple ARKit device support and permission: https://developer.apple.com/documentation/arkit/verifying-device-support-and-user-permission
- Apple `sceneDepth`: https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth
- Apple `smoothedSceneDepth`: https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/smoothedscenedepth
- Apple `supportsFrameSemantics`: https://developer.apple.com/documentation/arkit/arconfiguration/supportsframesemantics%28_%3A%29
- Apple scene reconstruction support: https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction%28_%3A%29
- Apple mesh classification: https://developer.apple.com/documentation/arkit/armeshclassification
- Apple AR depth data: https://developer.apple.com/documentation/arkit/ardepthdata
- Apple speech synthesis: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- Google ML Kit object detection on iOS: https://developers.google.com/ml-kit/vision/object-detection/ios
- Google ML Kit custom object detection models on iOS: https://developers.google.com/ml-kit/vision/object-detection/custom-models/ios
- Google ML Kit image labeling on iOS: https://developers.google.com/ml-kit/vision/image-labeling/ios
- Google Gemma overview: https://ai.google.dev/gemma/docs
- Google Gemma get started: https://ai.google.dev/gemma/docs/get_started
- Google Gemma 3 model overview: https://ai.google.dev/gemma/docs/core
- Google Gemma 3n model overview: https://ai.google.dev/gemma/docs/gemma-3n
- Google Gemma mobile deployment: https://ai.google.dev/gemma/docs/integrations/mobile
- ElevenLabs overview: https://elevenlabs.io/docs/overview
- ElevenLabs text to speech: https://elevenlabs.io/docs/product/speech-synthesis/overview
- ElevenLabs speech to text: https://elevenlabs.io/docs/capabilities/speech-to-text

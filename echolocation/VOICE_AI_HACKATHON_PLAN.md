# Voice AI Hackathon Plan

## Goal

Ship a working iPhone-only hackathon demo where the app:

1. continuously monitors nearby obstacles with LiDAR
2. responds to a short voice command like `what's ahead`
3. captures the current scene
4. labels the scene with `ML Kit`
5. summarizes the result with `Gemma 4`
6. speaks the response with `ElevenLabs`

This project should be framed as a **short-range spatial awareness aid**, not a replacement for a walking stick, cane, guide dog, or navigation tool.

## Demo Story

The user points the phone forward and says:

- `What's ahead?`
- `What's on my left?`
- `Repeat`

The app responds with one short spoken sentence such as:

`There's a chair slightly right, about a meter away.`

## Non-Goals

Do not spend hackathon time on:

- Android support
- open-ended conversation
- continuous cloud inference on every frame
- full navigation claims
- arbitrary object recognition perfection
- a second camera stack if ARKit can provide the image

## Build Order

## Phase 1: Keep LiDAR Awareness Working

### Objective

Preserve the current `ARKit` awareness loop as the reliable foundation.

### Current Repo Status

- native iOS `ARKit` session exists
- depth analysis exists
- left / center / right inference exists
- mesh classification exists
- native speech exists

### Tasks

- verify live updates still appear in the React Native UI
- verify native speech still works on a LiDAR-capable iPhone
- keep awareness mode simple:
  - obstacle distance
  - rough direction
  - coarse mesh label

### Definition of Done

- app runs on a physical LiDAR iPhone
- app can start and stop scanning
- app can report nearby obstacles without crashing

## Phase 2: Add Voice Command Recognition

### Objective

Trigger the rich describe flow with a tiny command set.

### Recommended Command Set

- `what's ahead`
- `what's on my left`
- `what's on my right`
- `repeat`

### Recommended Implementation

Use native iOS speech recognition:

- `SFSpeechRecognizer`
- `AVAudioEngine`

Expose it through the existing Expo module instead of adding a separate app architecture.

### Likely Files

- `modules/echo-lidar/ios/EchoLidarModule.swift`
- `modules/echo-lidar/ios/EchoLidarSession.swift`
- new native speech command helper
- `modules/echo-lidar/src/EchoLidarModule.ts`
- `src/hooks/use-echo-lidar.ts`

### Definition of Done

- user can speak one of the supported commands
- app can surface the recognized command back to JavaScript
- command recognition is stable enough for a live demo

## Phase 3: Add Snapshot Capture From AR Session

### Objective

Capture a current image from the active AR session when a command is triggered.

### Why

This avoids a second camera pipeline and keeps the architecture tight.

### Recommended Contract

Add a native method such as:

```ts
captureSnapshot(): Promise<{
  jpegBase64: string;
  width: number;
  height: number;
  timestampMs: number;
}>
```

If base64 is too heavy, return a temporary file path instead.

### Definition of Done

- JavaScript can request a snapshot on demand
- the snapshot comes from the current AR session
- the snapshot is good enough to run `ML Kit`

## Phase 4: Add ML Kit On-Demand

### Objective

Use `ML Kit` only when the user asks for a rich description.

### Why

- better battery behavior
- lower complexity
- more reliable live demo

### Recommended Flow

1. voice command arrives
2. use latest `EchoUpdate`
3. capture snapshot
4. run `ML Kit` image labeling on the snapshot
5. keep top 3 labels above a confidence threshold

### Recommended Output Shape

```ts
type SceneLabels = {
  labels: Array<{
    text: string;
    confidence: number;
  }>;
};
```

### Fallback Rule

If no useful labels are returned, continue with LiDAR-only input.

### Definition of Done

- one voice command can produce a list of likely labels
- labels are available in JavaScript for the `Gemma` prompt

## Phase 5: Add Gemma 4 Summarization

### Objective

Turn structured LiDAR + vision inputs into one short useful sentence.

### Input

- user command
- distance
- direction
- mesh label
- top `ML Kit` labels

### Prompt

```txt
You are a concise spatial describer for a blind or low-vision user.

Given:
- command: {{command}}
- distance: {{distance_m}} meters
- direction: {{direction}}
- mesh label: {{mesh_label}}
- camera labels: {{camera_labels}}

Reply with exactly one short sentence under 15 words.
No preamble. No bullets. No safety disclaimer.
```

### Example Output

`There's a chair slightly right, about a meter away.`

### Fallback Rule

If `Gemma` fails, return:

`Obstacle {{direction}}, about {{distance}} meters away.`

### Definition of Done

- the app can turn structured scene data into one sentence
- the sentence is short and consistent enough for a demo

## Phase 6: Add ElevenLabs Playback

### Objective

Use `ElevenLabs` for the rich voice response path.

### Voice Ownership Rule

Split the two loops clearly:

- `ARKit` awareness loop:
  - native short warnings
  - low-latency local speech or haptics
- rich voice-command loop:
  - `Gemma` sentence
  - `ElevenLabs` playback

Do not let both systems speak the same event.

### Recommended Flow

1. user speaks command
2. app captures snapshot
3. `ML Kit` produces labels
4. `Gemma` produces sentence
5. `ElevenLabs` speaks final response

### Definition of Done

- one voice command results in one polished spoken response
- repeated commands do not overlap or spam audio

## Phase 7: Optional OCR / Text Reading

### Objective

If time remains, add text-reading commands.

### Good Stretch Commands

- `read this`
- `what does the sign say`

### Implementation Options

- `ML Kit` text recognition for a simpler local path
- `Google Cloud Vision API` if sponsor-track alignment matters

### Definition of Done

- app can read a visible sign or printed text in a controlled demo

## Suggested JavaScript Contracts

### Native Event

```ts
type EchoUpdate = {
  nearestDistanceMeters: number | null;
  direction: 'left' | 'center' | 'right' | 'unknown';
  label: 'obstacle' | 'wall' | 'floor' | 'table' | 'seat' | 'door' | 'window' | 'unknown';
  confidence: number;
  mode: 'echo' | 'describe' | 'quiet';
  timestampMs: number;
  source: 'mock' | 'arkit';
};
```

### Voice Command Result

```ts
type VoiceCommand = {
  command: 'ahead' | 'left' | 'right' | 'repeat';
  transcript: string;
  timestampMs: number;
};
```

### Rich Description Input

```ts
type RichDescribeInput = {
  command: VoiceCommand['command'];
  update: EchoUpdate | null;
  cameraLabels: string[];
};
```

### Rich Description Output

```ts
type RichDescribeResult = {
  sentence: string;
  source: 'gemma' | 'fallback';
};
```

## Suggested File Additions

- `modules/echo-lidar/src/describeScene.ts`
- `src/lib/mlkit.ts`
- `src/lib/gemma.ts`
- `src/lib/elevenlabs.ts`
- `src/lib/voice-command-orchestrator.ts`

Potential native additions:

- `modules/echo-lidar/ios/VoiceCommandController.swift`

## Execution Priority

If time is short, cut in this order:

1. cut OCR
2. cut extra voice commands
3. cut fancy UI
4. cut directional variants beyond `what's ahead`
5. do not cut the core voice-triggered `ML Kit -> Gemma -> ElevenLabs` path

## Minimum Winning Demo

The smallest convincing sponsor-track demo is:

1. user points phone at scene
2. LiDAR awareness is already active
3. user says `what's ahead`
4. app captures image
5. `ML Kit` labels scene
6. `Gemma 4` generates one short sentence
7. `ElevenLabs` speaks it naturally

## Immediate Next Coding Steps

1. add a native voice-command contract
2. add snapshot capture from the active AR session
3. scaffold `describeScene.ts`
4. add `ML Kit` wrapper
5. add `Gemma` wrapper
6. add `ElevenLabs` playback wrapper
7. wire the orchestration path end to end

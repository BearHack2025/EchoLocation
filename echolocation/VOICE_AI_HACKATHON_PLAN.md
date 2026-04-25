# Voice AI Hackathon Plan

## Goal

Ship a working iPhone-only hackathon demo for a **head-worn spatial awareness assistant** where the system:

1. continuously monitors nearby obstacles with LiDAR
2. responds to a short voice command like `what's ahead`
3. captures the current scene
4. labels the scene with `ML Kit`
5. summarizes the result with `Gemma 4`
6. speaks the response with `ElevenLabs`
7. optionally recognizes familiar places using image embeddings

This project should be framed as a **short-range spatial awareness aid** or **head-worn wearable companion**, not a replacement for a walking stick, cane, guide dog, or navigation tool.

## Demo Story

The user wears the setup on their head or chest and says:

- `What's ahead?`
- `What's on my left?`
- `Repeat`
- `Is this familiar?`

The app responds with one short spoken sentence such as:

`There's a chair slightly right, about a meter away.`

For a familiar-place query, the app can respond with:

`This looks like the study lounge you visited earlier.`

## Non-Goals

Do not spend hackathon time on:

- Android support
- open-ended conversation
- continuous cloud inference on every frame
- full navigation claims
- arbitrary object recognition perfection
- a second camera stack if ARKit can provide the image
- a full SLAM or robotics-grade map

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
- `is this familiar`
- `save this place`

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

## Phase 5: Add Visual Memory With Image Embeddings

### Objective

Let the user ask whether the current place looks familiar.

### Product Behavior

Supported memory-style commands:

- `is this familiar`
- `have I been here before`
- `save this place`

### Minimal Hackathon Version

Do not build a full navigation map. Build a lightweight **visual memory**:

1. capture a snapshot
2. compute an image embedding
3. store the embedding with metadata
4. compare the current embedding against saved embeddings
5. if similarity is high enough, return the closest match

### Recommended Stored Metadata

```ts
type PlaceMemory = {
  id: string;
  embedding: number[];
  createdAtMs: number;
  note?: string;
  topLabels: string[];
  meshLabel?: string;
  lastKnownDirection?: 'left' | 'center' | 'right' | 'unknown';
};
```

### Recommended Matching Rule

- use cosine similarity
- only report a match above a fixed threshold
- keep top 1 match for the hackathon
- if confidence is weak, say it does not look familiar yet

### Suggested User Experience

When the user says `save this place`:

- capture a snapshot
- compute the embedding
- store it locally as a remembered place

When the user says `is this familiar`:

- capture a snapshot
- compute the current embedding
- compare to remembered places
- if matched, respond with a short sentence

### Important Scope Rule

This is **place similarity**, not true localization.
Do not claim exact indoor navigation or precise mapping.

### Definition of Done

- app can save at least one remembered place
- app can compare the current scene against saved memories
- app can speak whether the place appears familiar

## Phase 6: Add Gemma 4 Summarization

### Objective

Turn structured LiDAR + vision inputs into one short useful sentence.

### Input

- user command
- distance
- direction
- mesh label
- top `ML Kit` labels
- optional familiar-place match

### Prompt

```txt
You are a concise spatial describer for a blind or low-vision user.

Given:
- command: {{command}}
- distance: {{distance_m}} meters
- direction: {{direction}}
- mesh label: {{mesh_label}}
- camera labels: {{camera_labels}}
- familiar match: {{familiar_match}}

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

## Phase 7: Add ElevenLabs Playback

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

## Phase 8: Optional OCR / Text Reading

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
  command: 'ahead' | 'left' | 'right' | 'repeat' | 'familiar' | 'save_place';
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
  familiarMatch?: {
    id: string;
    similarity: number;
    note?: string;
  } | null;
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
- `src/lib/place-memory.ts`
- `src/lib/image-embeddings.ts`
- `src/lib/gemma.ts`
- `src/lib/elevenlabs.ts`
- `src/lib/voice-command-orchestrator.ts`

Potential native additions:

- `modules/echo-lidar/ios/VoiceCommandController.swift`

## Execution Priority

If time is short, cut in this order:

1. cut OCR
2. cut multi-place memory and keep only one remembered place
3. cut extra voice commands
4. cut fancy UI
5. cut directional variants beyond `what's ahead`
6. do not cut the core voice-triggered `ML Kit -> Gemma -> ElevenLabs` path

## Minimum Winning Demo

The smallest convincing sponsor-track demo is:

1. user points phone at scene
2. LiDAR awareness is already active
3. user says `what's ahead`
4. app captures image
5. `ML Kit` labels scene
6. `Gemma 4` generates one short sentence
7. `ElevenLabs` speaks it naturally

Strong stretch demo:

1. user says `save this place`
2. app stores an embedding for the current scene
3. user moves away and later says `is this familiar`
4. app matches the current scene to the saved memory
5. app says it looks like a previously seen place

## Immediate Next Coding Steps

1. add a native voice-command contract
2. add snapshot capture from the active AR session
3. scaffold `describeScene.ts`
4. add `ML Kit` wrapper
5. add image embedding + place memory storage
6. add `Gemma` wrapper
7. add `ElevenLabs` playback wrapper
8. wire the orchestration path end to end

# 3-Person Team Split

## Goal

Split the hackathon work so three people can work in parallel with minimal overlap.

The cleanest split is:

1. `Person 1`: native iOS LiDAR and ARKit
2. `Person 2`: React Native app shell and UI
3. `Person 3`: AI integrations, feedback layer, and demo flow

This keeps ownership clear and reduces merge conflicts.

## Team Structure

### Person 1: Native LiDAR / ARKit Engineer

Primary responsibility:

- make the phone actually sense depth and emit usable data

Own these files:

- `modules/echo-lidar/ios/EchoLidarModule.swift`
- `modules/echo-lidar/ios/EchoLidarSession.swift`
- `modules/echo-lidar/ios/DepthAnalyzer.swift`

Core tasks:

- set up `ARSession`
- check device support
- enable `smoothedSceneDepth`
- add mesh reconstruction support if available
- read depth frames
- split the frame into `left`, `center`, `right`
- compute nearest stable distance
- emit compact native events to JS

Definition of done:

- React Native receives real events like:
  - distance
  - direction
  - confidence
  - label

Priority order:

1. support checks
2. AR session startup
3. depth frame handling
4. stable distance detection
5. direction inference
6. mesh classification

Risks to watch:

- device compatibility
- ARKit permission/setup issues
- noisy depth values
- over-complicating the analyzer

## Person 2: React Native App / UI Engineer

Primary responsibility:

- make the app usable, clear, and easy to demo

Own these files:

- `app/index.tsx`
- `components/Controls.tsx`
- `components/StatusCard.tsx`
- `hooks/useEchoLidar.ts`
- `modules/echo-lidar/src/EchoLidar.ts`

Core tasks:

- build the home screen
- create start and stop controls
- create mode switching UI
- subscribe to native events
- show support status
- show distance, direction, confidence, and label
- make the UI demo-friendly for judges

Definition of done:

- app can display live data from native code clearly

Priority order:

1. app shell
2. controls
3. event subscription
4. live sensor display
5. support / error states
6. polish for demo

Risks to watch:

- building too much UI before native data exists
- over-designing screens
- coupling UI too tightly to unfinished native code

## Person 3: Feedback / QA / Demo Engineer

Primary responsibility:

- turn raw sensor output into a convincing accessibility demo

Own these files:

- `modules/echo-lidar/ios/SpeechController.swift`
- demo notes and test docs
- AI integration files and service wrappers

Secondary ownership:

- `Google ML Kit`
- `Gemma 3` or `Gemma 3n`
- `ElevenLabs`
- rehearsal and test scripts

Core tasks:

- add speech output with `AVSpeechSynthesizer`
- add haptics or beep feedback
- throttle repeated announcements
- tune thresholds with real-world testing
- define demo path and test scenarios
- document failure cases and fallback demo behavior
- integrate `ML Kit` object labels
- integrate `Gemma` summaries
- integrate `ElevenLabs` voice playback

Definition of done:

- user feedback feels understandable and not overwhelming
- team has a stable demo path
- sponsor-track integrations are visibly working

Priority order:

1. speech
2. haptics or beeps
3. rate limiting and threshold tuning
4. QA in a real room
5. demo script
6. `ML Kit`
7. `Gemma`
8. `ElevenLabs`

Risks to watch:

- audio spam
- unstable labeling
- letting the AI demo path block the core awareness path

## Parallel Build Plan

## Day 1

### Person 1

- create native module entry point
- implement support checks
- start `ARSession`
- emit fake events if real depth is not ready yet

### Person 2

- scaffold main screen
- build controls and status card
- add hook and JS wrapper for native events
- render fake native events in the UI

### Person 3

- plan spoken phrases and feedback modes
- set up `SpeechController.swift`
- define threshold ideas for distance bands
- prepare `ML Kit`, `Gemma`, and `ElevenLabs` integration notes
- prepare test checklist and demo script outline

End-of-day target:

- app runs on phone
- UI receives events
- team can prove the bridge works

## Day 2

### Person 1

- replace fake events with real depth analysis
- implement left/center/right logic
- add confidence filtering

### Person 2

- wire real events into the UI
- add support status and error states
- make sensor values easy to read

### Person 3

- connect speech and haptics to real data
- tune rate limiting
- test indoors with real obstacles
- wire the richer AI description flow

End-of-day target:

- app detects and reports nearby obstacles in real time

## Day 3

### Person 1

- improve stability
- add mesh classification if supported and low-risk

### Person 2

- finalize mode switching
- improve demo UI
- clean up edge states

### Person 3

- tune spoken feedback
- rehearse demo
- finalize `ML Kit + Gemma + ElevenLabs` demo path

End-of-day target:

- polished, reliable demo in one controlled room

## Handoff Contracts

To keep people from blocking each other, use these contracts.

### Contract From Person 1 To Person 2

Native event shape:

```ts
type EchoUpdate = {
  nearestDistanceMeters: number | null;
  direction: 'left' | 'center' | 'right' | 'unknown';
  label: string;
  confidence: number;
};
```

Person 1 should keep this stable as early as possible.

### Contract From Person 2 To Person 3

UI should expose:

- current mode
- current values
- easy start / stop interaction

This lets Person 3 test speech and feedback quickly.

### Contract From Person 3 To Team

Feedback rules should be explicit:

- when to speak
- when to stay quiet
- what phrases to use
- what happens when confidence is low

This prevents confusion during integration.

## Recommended Branching

Use one branch per owner:

- `person1-native-lidar`
- `person2-rn-ui`
- `person3-feedback-demo`

Merge strategy:

- merge Person 1 first if event contracts change
- Person 2 and Person 3 rebase on the current event shape
- avoid editing the same file unless necessary

## What Each Person Should Not Do

### Person 1 Should Not

- spend time on UI polish
- add cloud AI
- over-engineer exact angle estimation

### Person 2 Should Not

- block on final native logic
- build too many screens
- redesign the whole app during the hackathon

### Person 3 Should Not

- rely on unstable object labels for the main demo
- let the speech become too verbose
- let network-dependent AI replace the fallback local warning path

## Best Fallback If Time Runs Out

If the project gets tight, lock the scope to:

- Person 1: distance + left/center/right
- Person 2: clean live debug UI
- Person 3: one narrow `ML Kit + Gemma + ElevenLabs` describe flow plus speech + haptics

That is enough for a strong hackathon demo.

## Success Criteria By Person

### Person 1 Success

- native module works
- phone emits real obstacle summaries

### Person 2 Success

- app is easy to operate and easy to understand visually

### Person 3 Success

- feedback is usable and the demo is polished

## Recommended Team Standup Questions

Ask these every few hours:

1. Is the event payload stable?
2. Is the current phone definitely supported?
3. Is the feedback useful or too noisy?
4. Does the `ML Kit -> Gemma -> ElevenLabs` path still work end-to-end?

## Final Recommendation

If you only remember one thing, split it like this:

- `Person 1`: sensing
- `Person 2`: app
- `Person 3`: AI integrations, feedback, and demo

That is the lowest-risk 3-person split for this project.

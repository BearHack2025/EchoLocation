# Technologies Summary

## Overview

This project uses four main technologies together:

- `ARKit`
- `Google ML Kit`
- `Gemma 3 / 3n`
- `ElevenLabs`

Each one has a different job. The app works best when each technology is responsible for one clear part of the system.

## What Each Technology Does

### ARKit

`ARKit` is the core sensing system.

It is used for:

- LiDAR depth
- obstacle distance
- rough direction such as `left`, `center`, or `right`
- coarse scene labels such as `wall`, `floor`, `table`, `seat`, `door`, or `window`

In this project, `ARKit` answers:

- where is the object?
- how far away is it?

It is the fast real-time loop and should stay local on the phone.

### Google ML Kit

`Google ML Kit` is the object detection and image labeling layer.

It is used for:

- detecting objects in camera frames
- tracking objects across frames
- generating likely labels such as `chair`, `backpack`, `bottle`, or `table`

In this project, `ML Kit` answers:

- what might this object be?

It should run on the camera region selected by `ARKit`, not on the full image every time.

### Gemma 3 / 3n

`Gemma` is the reasoning and summarization layer.

It is used for:

- taking structured sensor output
- turning that output into a short useful sentence
- making the app sound more intelligent and natural

In this project, `Gemma` answers:

- how should I explain this scene to the user?

Example:

- input: distance, direction, mesh label, ML Kit labels
- output: `There appears to be a table slightly to your right about one meter away.`

Important:

- the public official Google docs currently point to `Gemma 3` and `Gemma 3n`
- if a sponsor track says `Gemma 4`, verify the exact sponsor wording

### ElevenLabs

`ElevenLabs` is the premium voice layer.

It is used for:

- **text-to-speech (TTS)** - voice output for commands and responses using premium voices
- **speech-to-text (STT)** - WebSocket realtime streaming using `scribe_v2_realtime` model with English language optimization

In this project, `ElevenLabs` answers:

- how should the response sound? (TTS)
- what did the user say? (STT - voice commands)

When `useBuiltin=false`, voice commands are transcribed via ElevenLabs Scribe WebSocket for higher accuracy. If ElevenLabs is unavailable or fails, the app falls back to iOS built-in speech recognition (SFSpeechRecognizer).

## How They Work Together

The clean architecture is:

```txt
ARKit
  -> distance + direction + coarse label
  -> choose nearest region

ML Kit
  -> detect likely object in that region

Gemma
  -> summarize structured results into one sentence

ElevenLabs
  -> speak that sentence naturally
```

## Example End-To-End Flow

1. `ARKit` sees an obstacle `1.1m` away on the `right`.
2. `ARKit` or mesh classification suggests `table`.
3. `ML Kit` sees labels like `table` and `desk`.
4. `Gemma` turns that into:
   - `There appears to be a table slightly to your right about one meter away.`
5. `ElevenLabs` speaks the sentence.

## Fast Loop Vs Rich Loop

The app should have two different paths.

### Fast Awareness Loop

Used for:

- urgent short-range awareness
- haptics
- simple speech
- real-time obstacle warnings

Technologies:

- `ARKit`
- built-in iOS speech or haptics

This path should stay fast and reliable.

### Rich Description Loop

Used for:

- `Describe Scene`
- `What is in front of me?`
- sponsor-track demo features

Technologies:

- `ARKit`
- `ML Kit`
- `Gemma`
- `ElevenLabs`

This path can be slower, because it is for richer explanation rather than urgent warnings.

## What Each One Should Not Do

### ARKit Should Not

- be expected to identify arbitrary everyday objects reliably
- provide exact angle precision for navigation-grade use

### ML Kit Should Not

- be treated as safety-grade truth
- run on the whole frame every time if you can avoid it

### Gemma Should Not

- run on every frame in the fast warning loop
- replace LiDAR depth estimation
- replace object detection

### ElevenLabs Should Not

- be treated as the vision system
- be the only voice path for urgent warnings

## Best Practical Usage In This App

Use each technology like this:

- `ARKit`: continuous obstacle awareness
- `ML Kit`: likely object labels
- `Gemma`: one-sentence scene explanation
- `ElevenLabs`: polished spoken output

## Example Structured Input To Gemma

```json
{
  "distance_m": 1.1,
  "direction": "right",
  "mesh_label": "table",
  "camera_labels": ["table", "desk", "furniture"]
}
```

## Example Gemma Output

```txt
There appears to be a table slightly to your right about one meter away.
```

## Example Final User Experience

### Awareness Mode

- app vibrates or gives short speech
- example:
  - `Obstacle ahead, 0.9 meters`

### Describe Scene Mode

- app runs the richer AI flow
- example:
  - `There appears to be a table slightly to your right about one meter away.`

## Key Takeaway

The simplest mental model is:

- `ARKit` tells you `where` and `how far`
- `ML Kit` tells you `what it might be`
- `Gemma` tells you `how to describe it`
- `ElevenLabs` tells you `how it should sound`

That is the clearest way to explain the stack to judges, teammates, and mentors.

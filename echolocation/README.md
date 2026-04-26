# Echolocation

A head-worn spatial awareness companion for iPhone. Combines on-device LiDAR, ARKit scene understanding, ML Kit object detection, Gemma scene reasoning, and ElevenLabs voice I/O so the user can ask "what's ahead?" and get a one-sentence spoken answer about nearby obstacles.


## Demo flow

1. App boots, ARKit session starts, LiDAR streams depth + mesh anchors.
2. User says a wake word (`Hey Echo`) followed by a short query: `what's ahead`, `what's on my left`, `repeat`, `is this familiar`.
3. ElevenLabs STT transcribes the command.
4. App captures the current frame, runs ML Kit object detection, and queries Gemma 4 for a one-sentence summary.
5. ElevenLabs TTS speaks the answer.
6. The on-screen "cyclops" overlay shows distance/direction/object live and the eyeball + light cone tilt to the detected zone.

## Tech stack

| Layer | Choice |
|-------|--------|
| Runtime | Expo SDK 55, React Native 0.83, React 19 |
| Routing | `expo-router` (file-based) |
| 3D / spatial | ARKit + LiDAR (iOS native via Swift) |
| Object detection | Google ML Kit (on-device) |
| Scene reasoning | Gemma 4 (E2B / 4B variant) |
| Speech | ElevenLabs STT + TTS, `expo-speech` fallback |
| Audio | `expo-audio`, `SpatialPingPlayer` (native) |
| UI | React Native + `react-native-svg`, `@gorhom/bottom-sheet`, `react-native-reanimated` |
| Native bridge | Custom Expo Module (`echo-lidar`, Swift) |
| Lang | TypeScript 5.9 |

iOS only (LiDAR-equipped iPhone Pro / Pro Max recommended). Android target is a stub.

## Architecture overview

```
┌─────────────────────────────────────────────────────────────┐
│  React Native (TypeScript)                                  │
│                                                             │
│  src/app/index.tsx          ← entry screen                  │
│   ├─ <EchoLidarPreview/>   ← native ARKit camera view       │
│   ├─ <EchoInfoPanel/>      ← top-right HUD (dist/dir/obj)   │
│   ├─ <CyclopsFigure/>      ← animated SVG mascot            │
│   └─ <BottomSheet>         ← debug / status panel           │
│                                                             │
│  src/hooks/use-echo-lidar.ts                                │
│   └─ subscribes to native EchoLidarEmitter                  │
│                                                             │
│  src/services/                                              │
│   ├─ audio-service.ts      ← unified speech facade          │
│   ├─ elevenlabsStt.ts      ← realtime STT WS client         │
│   └─ elevenlabsTts.ts      ← TTS playback                   │
└──────────────┬──────────────────────────────────────────────┘
               │  Expo Module bridge (events + methods)
┌──────────────▼──────────────────────────────────────────────┐
│  modules/echo-lidar/  (Swift, iOS only)                     │
│                                                             │
│  EchoLidarModule           ← module registration            │
│  EchoLidarSession          ← ARKit session lifecycle        │
│  EchoLidarPreviewView      ← Metal-backed camera view       │
│  DepthAnalyzer             ← LiDAR depth sampling           │
│  MeshAnchorRenderer        ← scene-mesh wireframe overlay   │
│  MeshDistanceShader        ← MSL shader for distance heatmap│
│  MeshClassifier            ← scene-mesh semantic class      │
│  MLKitObjectDetector       ← on-device object boxes         │
│  ObjectAnchorTracker       ← anchor smoothing across frames │
│  OCRDetector               ← text-in-scene capture          │
│  SpatialPingPlayer         ← directional audio ping         │
│  SpeechController          ← native fallback TTS            │
│  VoiceCommandController    ← wake-word + intent parsing     │
└─────────────────────────────────────────────────────────────┘
```

Per-frame data path: ARKit → `DepthAnalyzer` → nearest-distance + zone (left/center/right) → JS event → `useEchoLidar` → UI re-render. On voice trigger: STT → command intent → Gemma 4 prompt with object boxes → TTS playback.

## Project structure

```
echolocation/
├── src/
│   ├── app/                          ← expo-router screens
│   │   ├── _layout.tsx               ← root nav
│   │   ├── index.tsx                 ← main echolocation screen
│   │   └── explore.tsx               ← debug / settings
│   ├── components/
│   │   ├── cyclops/                  ← animated mascot (body/eye/eyeball/cone SVGs)
│   │   ├── echo-info-panel.tsx       ← top-right Distance/Direction/Object
│   │   ├── echo-status-sheet.tsx     ← bottom sheet content
│   │   └── ui/                       ← shared primitives
│   ├── hooks/
│   │   ├── use-echo-lidar.ts         ← native event subscription + state
│   │   ├── use-eleven-labs.ts        ← STT/TTS lifecycle
│   │   └── use-theme.ts
│   ├── services/
│   │   ├── audio-service.ts          ← speech routing facade
│   │   ├── elevenlabsStt.ts          ← WS streaming STT
│   │   ├── elevenlabsTts.ts          ← TTS playback
│   │   └── audio-logger.ts
│   ├── constants/
│   ├── types/
│   └── global.css
│
├── modules/
│   └── echo-lidar/                   ← custom Expo Module
│       ├── ios/                      ← Swift implementation
│       ├── src/                      ← TS bindings
│       ├── android/                  ← stub
│       └── EchoLidar.podspec
│
├── assets/
│   └── cyclops/                      ← SVG source files for mascot
│
├── ios/                              ← prebuild output (generated)
├── android/                          ← prebuild output (generated)
├── scripts/
├── plans/                            ← project plans (markdown)
├── docs/                             ← project docs
├── app.json
├── package.json
└── tsconfig.json
```

## Prerequisites

- macOS with Xcode 16+ (for iOS build)
- Node.js 20+
- CocoaPods (`sudo gem install cocoapods`)
- A LiDAR-equipped iPhone (12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro, or any Pro Max)
- ElevenLabs API key
- (Optional) Gemma model endpoint or local inference

## Install

```bash
git clone <repo-url>
cd echolocation
npm install
```

Create `.env` at the project root:

```env
EXPO_PUBLIC_ELEVENLABS_API_KEY=sk_xxx
# optional
EXPO_PUBLIC_GEMMA_ENDPOINT=https://...
```

iOS native build:

```bash
npx expo prebuild --platform ios
cd ios && pod install && cd ..
```

## Run

```bash
# iOS device (recommended — LiDAR required)
npm run ios -- --device

# iOS simulator (no LiDAR — UI only)
npm run ios

# Metro only (if app already installed)
npm start
```

Web / Android targets compile but are non-functional for the LiDAR pipeline.

## Scripts

| Command | What it does |
|---------|--------------|
| `npm start` | Start Metro bundler |
| `npm run ios` | Build & launch on iOS |
| `npm run android` | Build & launch on Android (stub) |
| `npm run web` | Web preview |
| `npm run lint` | ESLint |
| `npm run reset-project` | Move starter to `app-example/` |


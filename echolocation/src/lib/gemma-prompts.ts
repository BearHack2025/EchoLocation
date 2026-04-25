/**
 * Prompt templates for Gemma 4 E2B vision calls.
 * Kept as constants so we can iterate without rebuilding native code.
 */

export const SCENE_DESCRIBE_PROMPT = `You are describing a scene to a blind or low-vision user.

Look at the image. Reply with EXACTLY two lines:

LINE 1: A single short sentence under 15 words describing what is in the scene
        and where (left / center / right). No preamble, no greetings.
LINE 2: A comma-separated list of distinct visible objects (lowercase nouns).

Example:
A backpack on a chair to your right and a door ahead.
backpack, chair, door`;

/**
 * Build a direction-recommendation prompt with the latest LiDAR signals.
 * Output is strict JSON on a single line.
 */
export function buildDirectionPrompt(args: {
  distanceM: number | null;
  lidarDirection: string;
  lidarLabel: string;
}): string {
  const distanceText = args.distanceM != null ? args.distanceM.toFixed(2) : 'unknown';
  return `You are guiding a blind or low-vision user. Look at the image and use these
sensor readings:

- LiDAR nearest distance: ${distanceText} meters
- LiDAR direction: ${args.lidarDirection}
- Mesh label: ${args.lidarLabel}

Decide if the user should go LEFT, FORWARD, RIGHT, or STOP.

Reply with ONLY a single line of JSON, no prose, no code fences:
{"direction":"forward","confidence":0.78,"reason":"clear hallway","sentence":"Step forward, hallway is clear for two meters."}

Constraints:
- "direction" must be one of: left, forward, right, stop
- "confidence" between 0 and 1
- "sentence" under 15 words, friendly imperative

If unsure or the path is dangerous, choose "stop" with a sentence that
describes the obstacle.`;
}

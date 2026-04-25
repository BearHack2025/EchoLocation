import { StyleSheet, View } from 'react-native';

import type { useEchoLidar } from '@/hooks/use-echo-lidar';

type EchoState = ReturnType<typeof useEchoLidar>;

const MAX_M = 4;
const MIN_FILL = 0.08;
const BAR_AREA_HEIGHT = 140;

const COLORS = {
  left: '#FF9F0A',
  center: '#0A84FF',
  right: '#BF5AF2',
} as const;

type Zone = keyof typeof COLORS;
const ZONES: Zone[] = ['left', 'center', 'right'];

function fillForActive(distance: number | null | undefined): number {
  if (distance == null) return MIN_FILL;
  const clamped = Math.max(0, Math.min(distance, MAX_M));
  return Math.max(MIN_FILL, 1 - clamped / MAX_M);
}

export function EchoDirectionHud({ state, bottomOffset }: { state: EchoState; bottomOffset: number }) {
  if (!state.running || !state.latest) {
    return null;
  }

  const { direction, nearestDistanceMeters } = state.latest;
  const activeFill = fillForActive(nearestDistanceMeters);

  return (
    <View pointerEvents="none" style={[styles.wrapper, { bottom: bottomOffset }]}>
      {ZONES.map((zone) => {
        const isActive = direction === zone;
        const fill = isActive ? activeFill : MIN_FILL;
        const height = Math.round(BAR_AREA_HEIGHT * fill);
        const opacity = isActive ? 1 : 0.35;
        return (
          <View key={zone} style={styles.column}>
            <View style={styles.barTrack}>
              <View
                style={[
                  styles.barFill,
                  {
                    height,
                    opacity,
                    backgroundColor: COLORS[zone],
                  },
                ]}
              />
            </View>
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-evenly',
    alignItems: 'flex-end',
    paddingHorizontal: 24,
    height: BAR_AREA_HEIGHT,
  },
  column: {
    width: 36,
    height: BAR_AREA_HEIGHT,
    justifyContent: 'flex-end',
  },
  barTrack: {
    width: '100%',
    height: BAR_AREA_HEIGHT,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 8,
    overflow: 'hidden',
    justifyContent: 'flex-end',
  },
  barFill: {
    width: '100%',
    borderRadius: 8,
  },
});

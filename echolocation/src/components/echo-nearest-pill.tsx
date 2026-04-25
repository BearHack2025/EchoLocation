import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { useEchoLidar } from '@/hooks/use-echo-lidar';

type EchoState = ReturnType<typeof useEchoLidar>;

export function EchoNearestPill({ state }: { state: EchoState }) {
  const insets = useSafeAreaInsets();

  if (!state.running || !state.latest) {
    return null;
  }

  const { nearestDistanceMeters, direction, label } = state.latest;
  const distanceText = nearestDistanceMeters != null ? `${nearestDistanceMeters.toFixed(2)} m` : '— m';

  return (
    <View pointerEvents="none" style={[styles.wrapper, { top: insets.top + 12 }]}>
      <View style={styles.pill}>
        <Text style={styles.text}>{distanceText}</Text>
        <Text style={styles.dot}>·</Text>
        <Text style={styles.text}>{direction.toUpperCase()}</Text>
        <Text style={styles.dot}>·</Text>
        <Text style={styles.text}>{label}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 999,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  text: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  dot: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 14,
    fontWeight: '700',
  },
});

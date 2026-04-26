import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { useEchoLidar } from '@/hooks/use-echo-lidar';

type EchoState = ReturnType<typeof useEchoLidar>;

const COLOR = '#2A4DBF';

function capitalize(s: string): string {
  if (!s) return s;
  return s[0].toUpperCase() + s.slice(1);
}

export function EchoInfoPanel({ state }: { state: EchoState }) {
  const insets = useSafeAreaInsets();

  if (!state.running || !state.latest) {
    return null;
  }

  const { nearestDistanceMeters, direction, label } = state.latest;
  const distanceText = nearestDistanceMeters != null ? `${nearestDistanceMeters.toFixed(1)}m` : '—m';
  const directionText = capitalize(direction ?? 'center');
  const objectText = label?.trim() ? label : '—';

  return (
    <View pointerEvents="none" style={[styles.wrapper, { top: insets.top + 12 }]}>
      <Text style={styles.line}>Distance: {distanceText}</Text>
      <Text style={styles.line}>Direction: {directionText}</Text>
      <Text style={styles.line}>Object: {objectText}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    right: 20,
    alignItems: 'flex-end',
  },
  line: {
    color: COLOR,
    fontSize: 16,
    fontWeight: '700',
    lineHeight: 22,
  },
});

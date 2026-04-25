import { BottomSheetView } from '@gorhom/bottom-sheet';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Colors, Spacing } from '@/constants/theme';
import type { useEchoLidar } from '@/hooks/use-echo-lidar';

type EchoState = ReturnType<typeof useEchoLidar>;

const palette = Colors.light;

export function EchoStatusSheet({ state }: { state: EchoState }) {
  const { latest, latestCommand, running, listening, error, isSupported, supportsDepth, start, stop } = state;

  return (
    <BottomSheetView style={styles.container}>
      <Text style={[styles.subtitle, styles.center]}>Echolocation</Text>

      <View style={styles.card}>
        <Row label="ARKit supported" value={isSupported ? '✓' : '✗'} />
        <Row label="LiDAR depth" value={supportsDepth ? '✓' : '✗'} />
        <Row label="Status" value={running ? 'running' : 'stopped'} />
        <Row label="Voice" value={listening ? 'listening' : 'off'} />
      </View>

      {latest ? (
        <View style={styles.card}>
          <Row
            label="Distance"
            value={latest.nearestDistanceMeters != null ? `${latest.nearestDistanceMeters.toFixed(2)} m` : '—'}
          />
          <Row label="Direction" value={latest.direction} />
          <Row label="Label" value={latest.label} />
          <Row label="Confidence" value={`${(latest.confidence * 100).toFixed(0)}%`} />
          <Row label="Source" value={latest.source} />
        </View>
      ) : (
        <View style={styles.card}>
          <Text style={[styles.small, styles.muted, styles.center]}>no data yet — tap Start</Text>
        </View>
      )}

      <View style={styles.card}>
        <Row label="Last command" value={latestCommand?.command ?? '—'} />
        <Row label="Transcript" value={latestCommand?.transcript ?? '—'} />
      </View>

      {error ? <Text style={[styles.small, styles.center, styles.error]}>{error}</Text> : null}

      <View style={styles.buttons}>
        <Pressable
          style={[styles.btn, styles.btnStart, running && styles.btnDisabled]}
          onPress={() => start('describe')}
          disabled={running}
        >
          <Text style={[styles.smallBold, styles.btnLabel]}>Start</Text>
        </Pressable>
        <Pressable
          style={[styles.btn, styles.btnStop, !running && styles.btnDisabled]}
          onPress={stop}
          disabled={!running}
        >
          <Text style={[styles.smallBold, styles.btnLabel]}>Stop</Text>
        </Pressable>
      </View>
    </BottomSheetView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={[styles.small, styles.muted]}>{label}</Text>
      <Text style={[styles.smallBold, styles.text]}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: Spacing.four,
    gap: Spacing.three,
    backgroundColor: palette.background,
  },
  center: { textAlign: 'center' },
  card: {
    backgroundColor: palette.backgroundElement,
    borderRadius: Spacing.three,
    padding: Spacing.three,
    gap: Spacing.two,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  buttons: {
    flexDirection: 'row',
    gap: Spacing.three,
  },
  btn: {
    flex: 1,
    paddingVertical: Spacing.three,
    borderRadius: Spacing.three,
    alignItems: 'center',
  },
  btnStart: { backgroundColor: '#3c87f7' },
  btnStop: { backgroundColor: '#ff453a' },
  btnDisabled: { opacity: 0.4 },
  btnLabel: { color: '#ffffff' },
  error: { color: '#ff453a' },
  text: { color: palette.text },
  muted: { color: palette.textSecondary },
  small: { fontSize: 14, lineHeight: 20, fontWeight: '500' },
  smallBold: { fontSize: 14, lineHeight: 20, fontWeight: '700' },
  subtitle: { fontSize: 32, lineHeight: 44, fontWeight: '600', color: palette.text },
});

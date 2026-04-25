import { Pressable, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Spacing } from '@/constants/theme';
import { useEchoLidar } from '@/hooks/use-echo-lidar';

export default function HomeScreen() {
  const { latest, latestCommand, running, listening, error, isSupported, supportsDepth, start, stop } = useEchoLidar();

  return (
    <ThemedView style={styles.container}>
      <SafeAreaView style={styles.safe}>

        <ThemedText type="subtitle" style={styles.center}>Echolocation</ThemedText>

        <ThemedView type="backgroundElement" style={styles.card}>
          <Row label="ARKit supported" value={isSupported ? '✓' : '✗'} />
          <Row label="LiDAR depth" value={supportsDepth ? '✓' : '✗'} />
          <Row label="Status" value={running ? 'running' : 'stopped'} />
          <Row label="Voice" value={listening ? 'listening' : 'off'} />
        </ThemedView>

        {latest ? (
          <ThemedView type="backgroundElement" style={styles.card}>
            <Row label="Distance" value={latest.nearestDistanceMeters != null ? `${latest.nearestDistanceMeters.toFixed(2)} m` : '—'} />
            <Row label="Direction" value={latest.direction} />
            <Row label="Label" value={latest.label} />
            <Row label="Confidence" value={`${(latest.confidence * 100).toFixed(0)}%`} />
            <Row label="Source" value={latest.source} />
          </ThemedView>
        ) : (
          <ThemedView type="backgroundElement" style={styles.card}>
            <ThemedText type="small" themeColor="textSecondary" style={styles.center}>
              no data yet — tap Start
            </ThemedText>
          </ThemedView>
        )}

        <ThemedView type="backgroundElement" style={styles.card}>
          <Row label="Last command" value={latestCommand?.command ?? '—'} />
          <Row label="Transcript" value={latestCommand?.transcript ?? '—'} />
        </ThemedView>

        {error ? (
          <ThemedText type="small" style={[styles.center, styles.error]}>{error}</ThemedText>
        ) : null}

        <View style={styles.buttons}>
          <Pressable
            style={[styles.btn, styles.btnStart, running && styles.btnDisabled]}
            onPress={() => start('describe')}
            disabled={running}
          >
            <ThemedText type="smallBold" style={styles.btnLabel}>Start</ThemedText>
          </Pressable>
          <Pressable
            style={[styles.btn, styles.btnStop, !running && styles.btnDisabled]}
            onPress={stop}
            disabled={!running}
          >
            <ThemedText type="smallBold" style={styles.btnLabel}>Stop</ThemedText>
          </Pressable>
        </View>

      </SafeAreaView>
    </ThemedView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <ThemedText type="small" themeColor="textSecondary">{label}</ThemedText>
      <ThemedText type="smallBold">{value}</ThemedText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  safe: {
    flex: 1,
    padding: Spacing.four,
    gap: Spacing.three,
    justifyContent: 'center',
  },
  center: { textAlign: 'center' },
  card: {
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
});

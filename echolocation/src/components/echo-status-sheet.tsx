import { BottomSheetView } from '@gorhom/bottom-sheet';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Colors, Spacing } from '@/constants/theme';
import type { useEchoLidar } from '@/hooks/use-echo-lidar';
import { isConfigured as isElevenLabsConfigured } from '@/services/elevenlabsTts';

type EchoState = ReturnType<typeof useEchoLidar>;

const palette = Colors.light;

function formatBytes(bytes: number): string {
  if (!bytes || bytes < 1024) return `${bytes} B`;
  const mb = bytes / (1024 * 1024);
  if (mb < 1024) return `${mb.toFixed(1)} MB`;
  return `${(mb / 1024).toFixed(2)} GB`;
}

function describeModelStatus(s: EchoState['modelStatus']): string {
  switch (s.state) {
    case 'idle':        return 'not downloaded';
    case 'downloading': {
      if (s.totalBytes > 0) {
        const pct = Math.round((s.progressBytes / s.totalBytes) * 100);
        return `${pct}% · ${formatBytes(s.progressBytes)}/${formatBytes(s.totalBytes)}`;
      }
      return `downloading · ${formatBytes(s.progressBytes)}`;
    }
    case 'ready':       return 'ready';
    case 'error':       return s.error ?? 'error';
    default:            return s.state;
  }
}

export function EchoStatusSheet({ state }: { state: EchoState }) {
  const {
    latest,
    running,
    error,
    isSupported,
    supportsDepth,
    modelStatus,
    start,
    stop,
    downloadModel,
    cancelModelDownload,
  } = state;
  const elevenLabsReady = isElevenLabsConfigured();

  return (
    <BottomSheetView style={styles.container}>
      <Text style={[styles.subtitle, styles.center]}>Echolocation</Text>

      <View style={styles.card}>
        <Row label="ARKit supported" value={isSupported ? '✓' : '✗'} />
        <Row label="LiDAR depth" value={supportsDepth ? '✓' : '✗'} />
        <Row label="Status" value={running ? 'running' : 'stopped'} />
      </View>

      {!elevenLabsReady ? (
        <Text style={[styles.small, styles.error, styles.center]}>
          ElevenLabs API key not set — speech will be silent.
        </Text>
      ) : null}

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
          <Text style={[styles.small, styles.muted, styles.center]}>
            no LiDAR data yet — tap Start
          </Text>
        </View>
      )}

      <View style={styles.card}>
        <Row label="AI scene model" value={describeModelStatus(modelStatus)} />
        {modelStatus.state === 'idle' || modelStatus.state === 'error' ? (
          <Pressable style={[styles.btn, styles.btnSecondary]} onPress={downloadModel}>
            <Text style={[styles.smallBold, styles.btnLabel]}>Download AI model</Text>
          </Pressable>
        ) : null}
        {modelStatus.state === 'downloading' ? (
          <Pressable style={[styles.btn, styles.btnSecondary]} onPress={cancelModelDownload}>
            <Text style={[styles.smallBold, styles.btnLabel]}>Cancel download</Text>
          </Pressable>
        ) : null}
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
  btnSecondary: { backgroundColor: '#5856D6' },
  btnDisabled: { opacity: 0.4 },
  btnLabel: { color: '#ffffff' },
  error: { color: '#ff453a' },
  text: { color: palette.text },
  muted: { color: palette.textSecondary },
  small: { fontSize: 14, lineHeight: 20, fontWeight: '500' },
  smallBold: { fontSize: 14, lineHeight: 20, fontWeight: '700' },
  subtitle: { fontSize: 32, lineHeight: 44, fontWeight: '600', color: palette.text },
});

import BottomSheet from '@gorhom/bottom-sheet';
import { EchoLidarPreview } from 'echo-lidar';
import { useMemo, useRef } from 'react';
import { StyleSheet, useWindowDimensions, View } from 'react-native';

import { CyclopsFigure } from '@/components/cyclops/cyclops-figure';
import { EchoInfoPanel } from '@/components/echo-info-panel';
import { EchoStatusSheet } from '@/components/echo-status-sheet';
import { useEchoLidar } from '@/hooks/use-echo-lidar';

const PEEK_RATIO = 0.12;

export default function HomeScreen() {
  const state = useEchoLidar();
  const sheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ['12%', '50%', '90%'], []);
  const { height: screenHeight } = useWindowDimensions();
  const cyclopsBottomOffset = Math.round(screenHeight * PEEK_RATIO) + 12;

  return (
    <View style={styles.root}>
      <EchoLidarPreview style={StyleSheet.absoluteFill} />

      <EchoInfoPanel state={state} />
      <CyclopsFigure state={state} bottomOffset={cyclopsBottomOffset} />

      <BottomSheet
        ref={sheetRef}
        index={0}
        snapPoints={snapPoints}
        enablePanDownToClose={false}
        handleIndicatorStyle={styles.handleIndicator}
        backgroundStyle={styles.sheetBackground}
      >
        <EchoStatusSheet state={state} />
      </BottomSheet>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000000' },
  backdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: '#000000' },
  handleIndicator: { backgroundColor: '#9DA3AE' },
  sheetBackground: { backgroundColor: '#FFFFFF' },
});

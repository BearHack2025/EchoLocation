import BottomSheet from '@gorhom/bottom-sheet';
import { useIsFocused } from '@react-navigation/native';
import { EchoLidarPreview } from 'echo-lidar';
import { useEffect, useMemo, useRef } from 'react';
import { StyleSheet, useWindowDimensions, View } from 'react-native';

import { EchoDirectionHud } from '@/components/echo-direction-hud';
import { EchoNearestPill } from '@/components/echo-nearest-pill';
import { EchoStatusSheet } from '@/components/echo-status-sheet';
import { useEchoLidar } from '@/hooks/use-echo-lidar';

const PEEK_RATIO = 0.12;

export default function HomeScreen() {
  const state = useEchoLidar();
  const isFocused = useIsFocused();
  const sheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ['12%', '50%', '90%'], []);
  const { height: screenHeight } = useWindowDimensions();
  const hudBottomOffset = Math.round(screenHeight * PEEK_RATIO) + 12;
  const { isSupported, supportsDepth, running, start, stop } = state;

  useEffect(() => {
    if (!isFocused) {
      if (running) {
        void stop();
      }
      return;
    }

    if (isSupported && supportsDepth && !running) {
      void start('describe');
    }
  }, [isFocused, isSupported, running, start, stop, supportsDepth]);

  return (
    <View style={styles.root}>
      {isFocused ? <EchoLidarPreview style={StyleSheet.absoluteFill} /> : <View style={StyleSheet.absoluteFill} />}

      <EchoNearestPill state={state} />
      <EchoDirectionHud state={state} bottomOffset={hudBottomOffset} />

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

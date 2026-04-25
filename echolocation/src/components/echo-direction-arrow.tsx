import { SymbolView } from 'expo-symbols';
import { useEffect } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import type { useEchoLidar } from '@/hooks/use-echo-lidar';

type EchoState = ReturnType<typeof useEchoLidar>;

const ROTATION_DEGREES: Record<string, number> = {
  left: -45,
  center: 0,
  right: 45,
};

const NEUTRAL_COLOR = '#9DA3AE';

function colorForDistance(distance: number | null | undefined): string {
  if (distance == null) return NEUTRAL_COLOR;
  if (distance <= 1.0) return '#FF453A';
  if (distance <= 2.0) return '#FF9F0A';
  if (distance <= 3.0) return '#FFD60A';
  return '#30D158';
}

export function EchoDirectionArrow({
  state,
  bottomOffset,
}: {
  state: EchoState;
  bottomOffset: number;
}) {
  const rotation = useSharedValue(0);

  const direction = state.latest?.direction ?? 'center';
  const distance = state.latest?.nearestDistanceMeters;
  const targetRotation = ROTATION_DEGREES[direction] ?? 0;

  useEffect(() => {
    rotation.value = withTiming(targetRotation, { duration: 150 });
  }, [rotation, targetRotation]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ rotate: `${rotation.value}deg` }],
  }));

  if (!state.running || !state.latest) {
    return null;
  }

  const tint = colorForDistance(distance);

  return (
    <View pointerEvents="none" style={[styles.wrapper, { bottom: bottomOffset }]}>
      <View style={styles.chip}>
        <Animated.View style={animatedStyle}>
          {Platform.OS === 'ios' ? (
            <SymbolView
              name="arrow.up"
              tintColor={tint}
              size={36}
              resizeMode="scaleAspectFit"
            />
          ) : (
            <Text style={[styles.fallback, { color: tint }]}>↑</Text>
          )}
        </Animated.View>
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
  chip: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  fallback: {
    fontSize: 36,
    fontWeight: '800',
    lineHeight: 40,
  },
});

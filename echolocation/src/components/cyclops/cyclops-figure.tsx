import { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, View, useWindowDimensions } from 'react-native';

import type { useEchoLidar } from '@/hooks/use-echo-lidar';

import { SvgBody } from './svg-body';
import { SvgCone } from './svg-cone';
import { SvgEye } from './svg-eye';
import { SvgEyeball } from './svg-eyeball';

type EchoState = ReturnType<typeof useEchoLidar>;

type Props = {
  state: EchoState;
  bottomOffset: number;
  showCone?: boolean;
};

const EYEBALL_SHIFT_RATIO = 0.22;
const CONE_ROTATE_DEG = 45;
const VERTICAL_DROP_RATIO = 0.2;

const DIRECTION_SIGN: Record<string, number> = {
  left: -1,
  center: 0,
  right: 1,
};

const DIRECTION_ROTATE: Record<string, number> = {
  left: -CONE_ROTATE_DEG,
  center: 0,
  right: CONE_ROTATE_DEG,
};

export function CyclopsFigure({ state, bottomOffset, showCone = true }: Props) {
  const { width: screenWidth } = useWindowDimensions();

  const bodyWidth = screenWidth;
  const bodyHeight = (bodyWidth * 212) / 430;

  const eyeWidth = Math.min(170, screenWidth * 0.42);
  const eyeHeight = (eyeWidth * 141) / 166;

  const eyeballWidth = eyeWidth * 0.48;
  const eyeballShiftPx = Math.round(eyeWidth * EYEBALL_SHIFT_RATIO);

  const coneWidth = Math.min(280, screenWidth * 0.7);
  const coneHeight = (coneWidth * 258) / 321;

  const direction = state.latest?.direction ?? 'center';
  const isActive = state.running && state.latest != null;
  const targetOffset = isActive ? (DIRECTION_SIGN[direction] ?? 0) * eyeballShiftPx : 0;
  const targetRotate = isActive ? (DIRECTION_ROTATE[direction] ?? 0) : 0;

  const offsetAnim = useRef(new Animated.Value(targetOffset)).current;
  const rotateAnim = useRef(new Animated.Value(targetRotate)).current;

  useEffect(() => {
    Animated.timing(offsetAnim, {
      toValue: targetOffset,
      duration: 220,
      easing: Easing.out(Easing.quad),
      useNativeDriver: true,
    }).start();
  }, [targetOffset, offsetAnim]);

  useEffect(() => {
    Animated.timing(rotateAnim, {
      toValue: targetRotate,
      duration: 260,
      easing: Easing.out(Easing.quad),
      useNativeDriver: true,
    }).start();
  }, [targetRotate, rotateAnim]);

  const coneRotation = rotateAnim.interpolate({
    inputRange: [-CONE_ROTATE_DEG, 0, CONE_ROTATE_DEG],
    outputRange: [`-${CONE_ROTATE_DEG}deg`, '0deg', `${CONE_ROTATE_DEG}deg`],
  });

  const verticalDrop = bodyHeight * VERTICAL_DROP_RATIO;
  const bodyBottom = Math.max(0, bottomOffset - verticalDrop);
  const eyeBottom = bodyBottom + bodyHeight - eyeHeight * 0.55;
  const eyeballBottom = eyeBottom + eyeHeight * 0.32;
  const eyeballCenterY = eyeballBottom + eyeballWidth / 2;
  const coneBottom = eyeballCenterY;

  return (
    <View pointerEvents="none" style={styles.wrapper}>
      {showCone && isActive ? (
        <Animated.View
          style={[
            styles.layer,
            {
              bottom: coneBottom,
              width: coneWidth,
              height: coneHeight,
              transform: [
                { translateX: offsetAnim },
                { translateY: -coneHeight / 2 },
                { rotate: coneRotation },
                { translateY: coneHeight / 2 },
              ],
            },
          ]}
        >
          <SvgCone width={coneWidth} />
        </Animated.View>
      ) : null}

      <View style={[styles.layer, { bottom: bodyBottom, width: bodyWidth, height: bodyHeight }]}>
        <SvgBody width={bodyWidth} />
      </View>

      <View style={[styles.layer, { bottom: eyeBottom, width: eyeWidth, height: eyeHeight }]}>
        <SvgEye width={eyeWidth} />
      </View>

      <Animated.View
        style={[
          styles.layer,
          {
            bottom: eyeballBottom,
            width: eyeballWidth,
            height: eyeballWidth,
            transform: [{ translateX: offsetAnim }],
          },
        ]}
      >
        <SvgEyeball width={eyeballWidth} />
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    top: 0,
    alignItems: 'center',
  },
  layer: {
    position: 'absolute',
    alignItems: 'center',
    justifyContent: 'center',
  },
});

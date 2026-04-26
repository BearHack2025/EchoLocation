import Svg, { Defs, LinearGradient, Path, Stop } from 'react-native-svg';

type Props = { width: number };

export function SvgBody({ width }: Props) {
  const height = (width * 212) / 430;
  return (
    <Svg width={width} height={height} viewBox="0 0 430 212" fill="none">
      <Defs>
        <LinearGradient id="bodyGrad" x1="214.5" y1="0" x2="214.5" y2="359.227" gradientUnits="userSpaceOnUse">
          <Stop offset="0" stopColor="#CCD7FF" />
          <Stop offset="1" stopColor="#E9E9E9" />
        </LinearGradient>
      </Defs>
      <Path
        d="M-0.182219 214L-1.05707 75.5C46.8942 29.8016 125.572 0 214.5 0C303.428 0 382.106 29.8016 430.057 75.5L429.181 213.128L-0.182219 214Z"
        fill="url(#bodyGrad)"
      />
    </Svg>
  );
}

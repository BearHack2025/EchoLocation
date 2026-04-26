import Svg, { Path } from 'react-native-svg';

type Props = { width: number };

export function SvgCone({ width }: Props) {
  const height = (width * 258) / 321;
  return (
    <Svg width={width} height={height} viewBox="0 0 321 258" fill="none">
      <Path
        opacity={0.76}
        d="M161.099 258L0 54.0103C21.1604 35.3446 76.2974 -0.786894 161.099 0.0130657C245.9 0.813025 306.627 40.511 321 54.0103L161.099 258Z"
        fill="#FFF1DB"
      />
    </Svg>
  );
}

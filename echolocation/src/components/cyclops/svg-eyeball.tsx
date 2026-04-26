import Svg, { Ellipse } from 'react-native-svg';

type Props = { width: number };

export function SvgEyeball({ width }: Props) {
  const height = (width * 82) / 87;
  return (
    <Svg width={width} height={height} viewBox="0 0 87 82" fill="none">
      <Ellipse cx="43.5" cy="41" rx="43.5" ry="41" fill="#3F85F6" />
    </Svg>
  );
}

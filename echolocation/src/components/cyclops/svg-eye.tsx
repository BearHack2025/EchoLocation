import Svg, { Line, Path } from 'react-native-svg';

type Props = { width: number };

const ANTENNA_COLOR = '#3F85F6';

export function SvgEye({ width }: Props) {
  const height = (width * 141) / 166;
  return (
    <Svg width={width} height={height} viewBox="0 0 166 141" fill="none">
      <Path
        d="M166 80.0001C166 113.689 128.84 141 83 141C37.1604 141 0 113.689 0 80.0001C0 46.3107 37.1604 19.0001 83 19.0001C128.84 19.0001 166 46.3107 166 80.0001Z"
        fill="white"
      />
      <Line x1="21.816" y1="16.6151" x2="31.816" y2="32.6151" stroke={ANTENNA_COLOR} strokeWidth="9" />
      <Line x1="147.444" y1="17.5627" x2="136.699" y2="33.0723" stroke={ANTENNA_COLOR} strokeWidth="9" />
      <Line x1="84.5" y1="18.868" x2="84.5" y2="0" stroke={ANTENNA_COLOR} strokeWidth="9" />
    </Svg>
  );
}

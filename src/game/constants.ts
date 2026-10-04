export const GAME_WIDTH = 1280;
export const GAME_HEIGHT = 720;
export const ROUTE_LENGTH = 14_400;
export const ROAD_BASE_Y = 520;

export const COLORS = {
  ink: 0x171a25,
  cream: 0xfff4da,
  orange: 0xf4a53b,
  rust: 0xb95032,
  teal: 0x5bb4a4,
  blue: 0x6397ba,
  sage: 0x81976a,
  dirt: 0x72503e,
  darkDirt: 0x3b3030,
  white: 0xfffbeb,
  black: 0x11131a,
  danger: 0xe25d46,
  success: 0x87bc72
} as const;

export const FONT_HEAD = 'Barlow Condensed, Arial Narrow, sans-serif';
export const FONT_BODY = 'Nunito, Arial, sans-serif';

export type RunResult = {
  won: boolean;
  distance: number;
  time: number;
  scrap: number;
  bestDistance: number;
};

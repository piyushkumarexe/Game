import Phaser from 'phaser';
import { ROAD_BASE_Y, ROUTE_LENGTH } from '../constants';

export type Biome = 'mesa' | 'pine' | 'badlands';

const smoothstep = (edge0: number, edge1: number, value: number): number => {
  const x = Phaser.Math.Clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return x * x * (3 - 2 * x);
};

const seededWave = (x: number, frequency: number, phase: number): number =>
  Math.sin(x * frequency + phase);

export function terrainHeight(x: number): number {
  const clamped = Phaser.Math.Clamp(x, 0, ROUTE_LENGTH + 900);
  const startBlend = smoothstep(120, 850, clamped);
  const finishBlend = 1 - smoothstep(ROUTE_LENGTH - 750, ROUTE_LENGTH - 120, clamped);
  const amplitude = startBlend * Math.max(0.24, finishBlend);

  let height = ROAD_BASE_Y;
  height += seededWave(clamped, 0.00135, 0.4) * 46 * amplitude;
  height += seededWave(clamped, 0.0037, 2.2) * 26 * amplitude;
  height += seededWave(clamped, 0.0084, 1.1) * 8 * amplitude;

  // Three memorable, readable route features: a ravine, a ridge and the final climb.
  height += 68 * Math.exp(-Math.pow((clamped - 3_360) / 310, 2));
  height -= 82 * Math.exp(-Math.pow((clamped - 6_920) / 430, 2));
  height += 52 * Math.exp(-Math.pow((clamped - 9_480) / 270, 2));
  height -= 96 * Math.exp(-Math.pow((clamped - 12_340) / 520, 2));

  return Phaser.Math.Clamp(height, 350, 606);
}

export function terrainSlope(x: number): number {
  const sample = 7;
  return Math.atan2(terrainHeight(x + sample) - terrainHeight(x - sample), sample * 2);
}

export function biomeAt(x: number): Biome {
  if (x < 4_700) return 'mesa';
  if (x < 9_600) return 'pine';
  return 'badlands';
}

export function routeNameAt(x: number): string {
  if (x < 3_100) return 'SUNDOWN WASH';
  if (x < 4_700) return 'COYOTE RAVINE';
  if (x < 7_500) return 'JUNIPER PASS';
  if (x < 9_600) return 'MOSSBACK TRAIL';
  if (x < 12_100) return 'RED KNIFE BASIN';
  return 'LAST LIGHT RIDGE';
}

export function buildTerrainPoints(step = 38): Phaser.Math.Vector2[] {
  const points: Phaser.Math.Vector2[] = [];
  for (let x = -400; x <= ROUTE_LENGTH + 1_100; x += step) {
    points.push(new Phaser.Math.Vector2(x, terrainHeight(Math.max(0, x))));
  }
  return points;
}

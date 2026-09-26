// Level definitions. Pure data + builder calls, shared by server physics and client meshes.

import { SURF_BOUNCE, SURF_CONVEYOR, SURF_SLIP } from './world.js';

const TAU = Math.PI * 2;
const D2R = Math.PI / 180;

// ---------------------------------------------------------------- helpers
function ring(b, cx, cz, radius, count, fn) {
  for (let i = 0; i < count; i++) fn(i, (i / count) * TAU, cx + Math.cos((i / count) * TAU) * radius, cz + Math.sin((i / count) * TAU) * radius);
}

function trackSlab(b, z0, z1, halfW, y = 0, mat = 'track') {
  const len = (z1 - z0) / 2;
  return b.box(0, y - 0.5, (z0 + z1) / 2, halfW, 0.5, len, { vis: { mat } });
}

function rails(b, z0, z1, halfW, y = 0, h = 0.75) {
  const len = (z1 - z0) / 2;
  b.box(halfW + 0.3, y + h / 2, (z0 + z1) / 2, 0.3, h / 2, len, { vis: { mat: 'rail' } });
  b.box(-halfW - 0.3, y + h / 2, (z0 + z1) / 2, 0.3, h / 2, len, { vis: { mat: 'rail' } });
}

// ================================================================ LOBBY
export const LOBBY = {
  id: 'lobby',
  name: 'Warm-Up Island',
  mode: 'lobby',
  killY: -30,
  respawnMode: 'spawn',
  theme: {
    sun: [0.28, 0.42], turbidity: 3.2, rayleigh: 1.4, sky: 0x9fd4ff,
    fog: 0xcfe6ff, fogNear: 60, fogFar: 340,
    palette: { track: 0xf2f3f7, accent: 0xff7a9c, rail: 0x5b6ee1, hazard: 0xff5a4e, metal: 0xb9c2cf, bounce: 0x4ee1a0, goal: 0xffd166, glass: 0x7fd8ff },
  },
  camera: { start: [0, 14, -26] },
  build(b) {
    // main island
    b.cyl(0, -1, 0, 26, 1, { vis: { mat: 'track', seg: 48 } });
    b.cyl(0, -3.2, 0, 22, 1.4, { vis: { mat: 'accent', seg: 48 } });
    // centre fountain
    b.cyl(0, 0.6, 0, 4.2, 0.6, { vis: { mat: 'accent', seg: 36 } });
    b.cyl(0, 1.6, 0, 1.2, 1.6, { vis: { mat: 'glass', seg: 20 } });
    // bounce pads
    ring(b, 0, 0, 14, 5, (i, a, x, z) => {
      b.cyl(x, 0.35, z, 2.1, 0.35, { surface: SURF_BOUNCE, bounce: 15.5, vis: { mat: 'bounce', seg: 24 } });
    });
    // floating rings to jump through
    ring(b, 0, 0, 9, 3, (i, a, x, z) => {
      b.box(x, 3.2, z, 1.6, 0.25, 1.6, {
        ry: a, motion: { k: 'bob', amp: 0.9, speed: 1.2, phase: i * 2.1 }, vis: { mat: 'glass' },
      });
    });
    // slow spinner to goof around on
    b.cyl(0, 3.6, 0, 0.5, 1.8, { vis: { mat: 'metal', seg: 12 } });
    b.box(0, 5.6, 0, 9, 0.3, 0.6, {
      knock: 0.6, motion: { k: 'spin', speed: 1.1, phase: 0 }, vis: { mat: 'hazard' },
    });
    // decorative arch / banner
    b.addDecor({ kind: 'banner', x: 0, y: 9, z: 20, text: 'TUMBLE ROYALE' });
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * TAU, rr = 34 + (i % 3) * 7;
      b.addDecor({ kind: 'cloudIsland', x: Math.cos(a) * rr, y: -6 - (i % 4) * 5, z: Math.sin(a) * rr, s: 3 + (i % 5) });
    }
    for (let i = 0; i < 24; i++) b.spawns.push({ x: Math.cos((i / 24) * TAU) * 17, y: 1.2, z: Math.sin((i / 24) * TAU) * 17, yaw: -(i / 24) * TAU + Math.PI });
  },
};

// ================================================================ ROUND 1 — SKY GAUNTLET
export const GAUNTLET = {
  id: 'gauntlet',
  name: 'Sky Gauntlet',
  tagline: 'Race to the finish. Slowpokes go home.',
  mode: 'race',
  killY: -22,
  respawnMode: 'checkpoint',
  qualifyRatio: 0.6,
  timeLimitMs: 150000,
  theme: {
    sun: [0.34, 0.15], turbidity: 4.5, rayleigh: 2.1, sky: 0x8fc7ff,
    fog: 0xbcd9f5, fogNear: 55, fogFar: 320,
    palette: { track: 0xeceff5, accent: 0x5ad2ff, rail: 0x3552a4, hazard: 0xff5f57, metal: 0xaab4c4, bounce: 0x36e2a4, goal: 0xffd166, glass: 0x8fe4ff },
  },
  camera: { start: [0, 16, -22] },
  build(b) {
    // ---------- START ----------
    trackSlab(b, -10, 16, 13);
    rails(b, -10, 16, 13, 0, 1.2);
    b.box(0, 3.2, -9.4, 13, 0.5, 0.5, { vis: { mat: 'goal' } });
    for (let i = 0; i < 24; i++) {
      const col = i % 6, row = (i / 6) | 0;
      b.spawns.push({ x: -10 + col * 4, y: 0.6, z: -6 + row * 3.2, yaw: 0 });
    }

    // ---------- 1. SPIN BARS ----------
    trackSlab(b, 16, 46, 11);
    rails(b, 16, 46, 11, 0, 1.7);
    for (let i = 0; i < 3; i++) {
      const z = 22 + i * 10;
      b.cyl(0, 1.2, z, 0.45, 1.2, { vis: { mat: 'metal', seg: 14 } });
      for (let k = 0; k < 2; k++) {
        b.box(0, 0.85, z, 10.5, 0.32, 0.42, {
          ry: k * Math.PI / 2,
          knock: 0.55,
          motion: { k: 'spin', speed: (i % 2 ? -1 : 1) * (0.95 + i * 0.16), phase: i * 1.3 + k * Math.PI / 2 },
          vis: { mat: 'hazard', stripe: true },
        });
      }
    }
    b.trigger('checkpoint', 0, 3, 44, 12, 6, 1.5, { idx: 1, progress: 44, rp: { x: 0, y: 0.6, z: 42 } });

    // ---------- 2. HAMMER BRIDGE ----------
    trackSlab(b, 46, 76, 5.2);
    rails(b, 46, 76, 5.2, 0, 0.7);
    for (let i = 0; i < 3; i++) {
      const z = 53 + i * 8;
      const px = i % 2 ? 1.3 : -1.3;
      b.box(px, 9.6, z, 0.3, 0.3, 0.3, { vis: { mat: 'metal' }, solid: false });
      b.box(0, 0, 0, 0.2, 4.2, 0.2, {
        solid: false,
        motion: { k: 'pend', axis: 'z', px, py: 9.6, pz: z, len: 4.2, amp: 1.0, speed: 1.15 + i * 0.11, phase: i * 1.9 },
        vis: { mat: 'metal' },
      });
      b.box(0, 0, 0, 2.3, 1.0, 1.0, {
        knock: 0.8,
        motion: { k: 'pend', axis: 'z', px, py: 9.6, pz: z, len: 8.4, amp: 1.0, speed: 1.15 + i * 0.11, phase: i * 1.9 },
        vis: { mat: 'hazard' },
      });
    }

    // ---------- 3. MOVING PLATFORMS OVER THE VOID ----------
    trackSlab(b, 76, 82, 7);
    // sliding ferries — hop on when they swing past the middle
    b.box(-8, -0.4, 87, 3.2, 0.4, 3.2, {
      motion: { k: 'loop', dx: 16, dy: 0, dz: 0, speed: 0.30, phase: 0.0 },
      vis: { mat: 'glass' },
    });
    b.box(0, -0.4, 96, 3.0, 0.4, 3.0, { vis: { mat: 'track' } });
    b.box(8, -0.4, 104, 3.2, 0.4, 3.2, {
      motion: { k: 'loop', dx: -16, dy: 0, dz: 0, speed: 0.34, phase: 1.0 },
      vis: { mat: 'glass' },
    });
    b.box(0, -0.4, 113, 3.0, 0.4, 3.0, { vis: { mat: 'track' } });
    b.cyl(0, 1.6, 96, 0.35, 1.6, { vis: { mat: 'metal', seg: 12 } });
    b.box(0, 2.9, 96, 4.6, 0.26, 0.4, {
      knock: 0.7, motion: { k: 'spin', speed: 1.5, phase: 0 }, vis: { mat: 'hazard', stripe: true },
    });
    trackSlab(b, 118, 128, 8);
    b.trigger('checkpoint', 0, 3, 126, 9, 6, 1.5, { idx: 2, progress: 126, rp: { x: 0, y: 0.6, z: 124 } });

    // ---------- 4. BUMPER FIELD ----------
    trackSlab(b, 128, 150, 10);
    rails(b, 128, 150, 10, 0, 1.0);
    for (let i = 0; i < 7; i++) {
      const x = -7 + (i % 4) * 4.6 + ((i / 4) | 0) * 2.2;
      const z = 132 + ((i * 3.1) % 14);
      b.sphere(x, 1.5, z, 1.55, {
        knock: 0.85,
        motion: { k: 'loop', dx: (i % 2 ? 5.5 : -5.5), dy: 0, dz: 0, speed: 0.5 + (i % 3) * 0.14, phase: i * 0.7 },
        vis: { mat: 'accent' },
      });
    }

    // ---------- 5. CONVEYOR + DISCS ----------
    trackSlab(b, 150, 154, 9);
    b.box(0, -0.35, 162, 4.2, 0.35, 8, { surface: SURF_CONVEYOR, conveyor: -4.2, vis: { mat: 'metal', belt: -1 } });
    b.box(7.5, -0.35, 162, 3.0, 0.35, 8, { surface: SURF_CONVEYOR, conveyor: 3.0, vis: { mat: 'metal', belt: 1 } });
    b.box(-7.5, -0.35, 162, 3.0, 0.35, 8, { surface: SURF_CONVEYOR, conveyor: 3.0, vis: { mat: 'metal', belt: 1 } });
    rails(b, 154, 170, 10.5, 0, 0.9);
    for (let i = 0; i < 2; i++) {
      const x = i ? 5.4 : -5.4;
      b.cyl(x, -0.1, 162, 3.0, 0.3, {
        motion: { k: 'spin', speed: i ? 2.2 : -2.2, phase: i },
        vis: { mat: 'glass', seg: 28 },
      });
    }

    // ---------- 6. ROLLING LOGS ON BEAMS ----------
    trackSlab(b, 170, 176, 9);
    for (let lane = -1; lane <= 1; lane++) {
      b.box(lane * 4.2, -0.3, 188, 1.7, 0.3, 12, { vis: { mat: 'track' } });
    }
    for (let i = 0; i < 5; i++) {
      const z = 179 + i * 4.4;
      b.box(0, 0.62, z, 7.2, 0.62, 0.62, {
        knock: 0.75,
        motion: { k: 'loop', dx: 9, dy: 0, dz: 0, speed: 0.55 + (i % 3) * 0.12, phase: i * 0.66 },
        vis: { mat: 'hazard', log: true, spinRoll: 2.2 },
      });
    }
    trackSlab(b, 200, 210, 9);
    b.trigger('checkpoint', 0, 3, 206, 10, 6, 2.0, { idx: 3, progress: 206, rp: { x: 0, y: 0.6, z: 203 } });

    // ---------- 7. BOUNCE FINALE ----------
    for (let i = 0; i < 3; i++) {
      b.cyl(-5.5 + i * 5.5, 0.4, 212.5 + (i % 2) * 2.6, 2.35, 0.4, {
        surface: SURF_BOUNCE, bounce: 18.6, vis: { mat: 'bounce', seg: 26 },
      });
    }
    // high landing deck (top surface y = 6.1)
    b.box(0, 5.6, 222, 9, 0.5, 5, { vis: { mat: 'track' } });
    rails(b, 217, 227, 9, 6.1, 0.8);
    // spinning cross on the deck
    b.cyl(0, 7.4, 222, 0.45, 1.3, { vis: { mat: 'metal', seg: 12 } });
    for (let k = 0; k < 3; k++) {
      b.box(0, 7.1, 222, 8.4, 0.3, 0.45, {
        ry: (k * TAU) / 3, knock: 0.85,
        motion: { k: 'spin', speed: -1.7, phase: (k * TAU) / 3 },
        vis: { mat: 'hazard', stripe: true },
      });
    }
    // slippery slide down to the finish straight
    b.box(0, 2.55, 235.46, 9, 0.5, 9, {
      rx: 20 * D2R, surface: SURF_SLIP, vis: { mat: 'glass', slick: true },
    });
    b.trigger('checkpoint', 0, 9.1, 222, 9, 3, 3.0, { idx: 4, progress: 222, rp: { x: 0, y: 6.8, z: 219 } });

    // ---------- FINISH ----------
    trackSlab(b, 243, 268, 11);
    rails(b, 243, 268, 11, 0, 1.0);
    b.box(-9.5, 4.0, 258, 0.6, 4.0, 0.6, { vis: { mat: 'goal' }, solid: false });
    b.box(9.5, 4.0, 258, 0.6, 4.0, 0.6, { vis: { mat: 'goal' }, solid: false });
    b.box(0, 8.2, 258, 10.4, 0.7, 0.6, { vis: { mat: 'goal' }, solid: false });
    b.trigger('finish', 0, 3, 258, 11, 7, 2.0, { progress: 1000 });
    b.addDecor({ kind: 'banner', x: 0, y: 10.0, z: 258, text: 'FINISH' });

    for (let i = 0; i < 20; i++) {
      const s = 4 + (i % 6) * 2.5;
      b.addDecor({ kind: 'cloudIsland', x: (i % 2 ? 1 : -1) * (26 + (i % 5) * 9), y: -10 - (i % 6) * 6, z: -10 + i * 14, s });
    }
  },
  botPath: [
    [0, 8], [0, 18], [1.5, 24], [-1.5, 29], [1.5, 34], [0, 40], [0, 46],
    [0, 52], [0, 58], [0, 64], [0, 70], [0, 78],
    [0, 86], [0, 96], [0, 104], [0, 113], [0, 122],
    [-3, 131], [3, 137], [-3, 143], [0, 149],
    [-7.5, 156], [-7.5, 164], [-3, 170], [0, 174],
    [-4.2, 180], [-4.2, 190], [-2, 198], [0, 205],
    [0, 212], [0, 219], [0, 224], [0, 232], [0, 240],
    [0, 248], [0, 258],
  ],
};

// ================================================================ ROUND 2 — HEX DASH
export const HEXDASH = {
  id: 'hex',
  name: 'Hex Dash',
  tagline: 'Tiles fall the moment you touch them. Keep moving.',
  mode: 'survive',
  killY: -14,
  respawnMode: 'eliminate',
  qualifyRatio: 0.5,
  timeLimitMs: 105000,
  tileFadeTicks: 26,
  theme: {
    sun: [0.22, 0.62], turbidity: 6.5, rayleigh: 1.1, sky: 0xffb38a,
    fog: 0xffc9a8, fogNear: 40, fogFar: 260,
    palette: { track: 0xfff0e2, accent: 0xff9a5c, rail: 0x6b4bb5, hazard: 0xff5a7a, metal: 0xc0b0a4, bounce: 0x4ee1a0, goal: 0xffd166, glass: 0xffd9b8 },
  },
  camera: { start: [0, 40, -34] },
  build(b) {
    const SIZE = 1.78, TR = 1.7;
    const LAYERS = [26, 17, 8];
    const RINGS = 5;
    const layerMats = ['hexA', 'hexB', 'hexC'];
    for (let li = 0; li < LAYERS.length; li++) {
      const y = LAYERS[li];
      for (let q = -RINGS; q <= RINGS; q++) {
        const r1 = Math.max(-RINGS, -q - RINGS), r2 = Math.min(RINGS, -q + RINGS);
        for (let rr = r1; rr <= r2; rr++) {
          const x = SIZE * Math.sqrt(3) * (q + rr / 2);
          const z = SIZE * 1.5 * rr;
          const c = b.cyl(x, y, z, TR, 0.28, {
            vis: { mat: layerMats[li], seg: 6, hex: true, layer: li },
            group: 'tile',
          });
          b.tiles.push({ id: c.id, layer: li, x, y, z });
        }
      }
    }
    // spawn on the top layer, spread over the outer rings
    const cells = [];
    for (let q = -4; q <= 4; q++) {
      for (let rr = -4; rr <= 4; rr++) {
        if (Math.abs(q + rr) > 4) continue;
        const x = SIZE * Math.sqrt(3) * (q + rr / 2);
        const z = SIZE * 1.5 * rr;
        cells.push({ x, z, d: Math.hypot(x, z) });
      }
    }
    cells.sort((a, c) => c.d - a.d);
    for (let i = 0; i < 24; i++) {
      const c = cells[i % cells.length];
      b.spawns.push({ x: c.x, y: LAYERS[0] + 0.5, z: c.z, yaw: Math.atan2(-c.x, -c.z) });
    }
    b.addDecor({ kind: 'lava', y: -6, r: 90 });
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * TAU;
      b.addDecor({ kind: 'cloudIsland', x: Math.cos(a) * (40 + (i % 3) * 12), y: -2 - (i % 5) * 6, z: Math.sin(a) * (40 + (i % 3) * 12), s: 4 + (i % 4) * 2.5 });
    }
  },
};

// ================================================================ ROUND 3 — CROWN CLASH
export const CROWN = {
  id: 'crown',
  name: 'Crown Clash',
  tagline: 'Climb the tower. Grab the crown. Win everything.',
  mode: 'crown',
  killY: -18,
  respawnMode: 'respawn',
  timeLimitMs: 150000,
  theme: {
    sun: [0.15, 0.86], turbidity: 8.5, rayleigh: 0.9, sky: 0x6a5acd,
    fog: 0x4b4088, fogNear: 45, fogFar: 240,
    palette: { track: 0xe9e4ff, accent: 0xb388ff, rail: 0x4a3f8f, hazard: 0xff4d9d, metal: 0xa9a2c9, bounce: 0x3ff2c8, goal: 0xffd94a, glass: 0xa6f0ff },
  },
  camera: { start: [0, 20, -34] },
  crownPos: { x: 0, y: 24.4, z: 0, bob: 0.9, speed: 1.4, r: 1.9 },
  build(b) {
    // ---- base arena ----
    b.cyl(0, -0.6, 0, 21, 0.6, { vis: { mat: 'track', seg: 56 } });
    b.cyl(0, -2.4, 0, 18, 1.4, { vis: { mat: 'accent', seg: 56 } });
    // outer lip so you don't trivially fall
    ring(b, 0, 0, 20.4, 28, (i, a, x, z) => {
      b.box(x, 0.45, z, 2.4, 0.45, 0.35, { ry: -a, vis: { mat: 'rail' } });
    });

    // ---- ground sweepers ----
    b.cyl(0, 1.4, 0, 1.25, 2.0, { vis: { mat: 'metal', seg: 18 } });
    for (let k = 0; k < 3; k++) {
      b.box(0, 0.75, 0, 16, 0.35, 0.5, {
        ry: (k * TAU) / 3, knock: 0.95,
        motion: { k: 'spin', speed: -0.95, phase: (k * TAU) / 3 },
        vis: { mat: 'hazard', stripe: true },
      });
    }

    // ---- launch pads ----
    ring(b, 0, 0, 13.5, 4, (i, a, x, z) => {
      b.cyl(x, 0.5, z, 2.4, 0.5, { surface: SURF_BOUNCE, bounce: 17.2, vis: { mat: 'bounce', seg: 26 } });
    });

    // ---- central spire ----
    b.cyl(0, 12, 0, 1.5, 12, { vis: { mat: 'metal', seg: 24 } });

    // ---- orbiting climb discs ----
    const tiers = [
      { y: 5.2, r: 9.5, n: 3, sp: 0.44, dr: 2.7 },
      { y: 9.4, r: 7.6, n: 3, sp: -0.52, dr: 2.5 },
      { y: 13.6, r: 6.0, n: 3, sp: 0.6, dr: 2.3 },
      { y: 17.8, r: 4.6, n: 2, sp: -0.7, dr: 2.2 },
    ];
    for (let t = 0; t < tiers.length; t++) {
      const tr = tiers[t];
      for (let i = 0; i < tr.n; i++) {
        const ph = (i / tr.n) * TAU + t * 0.7;
        b.cyl(0, tr.y, 0, tr.dr, 0.28, {
          motion: { k: 'orbit', cx: 0, cz: 0, r: tr.r, speed: tr.sp, phase: ph },
          vis: { mat: t % 2 ? 'glass' : 'accent', seg: 28 },
        });
      }
      // hazard arm at each tier
      b.box(0, tr.y + 1.3, 0, tr.r + 2.4, 0.3, 0.42, {
        knock: 0.9,
        motion: { k: 'spin', speed: -tr.sp * 1.8, phase: t * 1.1 },
        vis: { mat: 'hazard', stripe: true },
      });
    }

    // ---- summit ----
    b.cyl(0, 21.4, 0, 3.6, 0.4, { vis: { mat: 'goal', seg: 32 } });
    ring(b, 0, 0, 3.4, 6, (i, a, x, z) => {
      b.box(x, 22.4, z, 0.35, 0.7, 0.35, { vis: { mat: 'metal' }, solid: false });
    });

    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * TAU;
      b.spawns.push({ x: Math.cos(a) * 16.5, y: 0.4, z: Math.sin(a) * 16.5, yaw: Math.atan2(-Math.cos(a), -Math.sin(a)) });
    }
    b.addDecor({ kind: 'crown', x: 0, y: 24.4, z: 0 });
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * TAU;
      b.addDecor({ kind: 'cloudIsland', x: Math.cos(a) * (36 + (i % 4) * 10), y: -6 - (i % 5) * 7, z: Math.sin(a) * (36 + (i % 4) * 10), s: 4 + (i % 5) * 2 });
    }
  },
};

export const LEVELS = { lobby: LOBBY, gauntlet: GAUNTLET, hex: HEXDASH, crown: CROWN };
export const ROUND_ORDER = ['gauntlet', 'hex', 'crown'];
export function getLevel(id) { return LEVELS[id]; }

// Bot brains. They don't cheat — they drive the exact same input struct a human does,
// so they fall off ledges, get hammered, and lose races just like everyone else.

import * as K from '../shared/constants.js';
import { ST_ALIVE } from '../shared/sim.js';
import { makeRng } from '../shared/math.js';

const TAU = Math.PI * 2;

/** Highest walkable surface under (x,z) within a vertical window. Bots use AABB tops — cheap and good enough. */
function groundTopAt(world, x, z, yRef, span = 7) {
  const list = world.queryAabb(x, yRef - span, z, 0.35, span + 2);
  let best = -Infinity, bestC = null;
  for (let i = 0; i < list.length; i++) {
    const c = list[i];
    if (c.dead || !c.solid || c.shape === 2) continue;
    const a = c.aabb;
    if (x < a.x0 - 0.1 || x > a.x1 + 0.1 || z < a.z0 - 0.1 || z > a.z1 + 0.1) continue;
    if (a.y1 > yRef + 1.35) continue;
    if (a.y1 < yRef - span) continue;
    if (a.y1 > best) { best = a.y1; bestC = c; }
  }
  return bestC ? best : null;
}

const _t = { x: 0, y: 0, z: 0 };

/** Closest surface point of a collider to (x,z) at the player's chest height, in XZ. */
function xzDistTo(c, x, y, z) {
  const cy = y + 0.7;
  if (c.shape === 0) {
    const m = c.m, h = c.h;
    const dx = x - c.p.x, dy = cy - c.p.y, dz = z - c.p.z;
    const lx = m[0] * dx + m[3] * dy + m[6] * dz;
    const ly = m[1] * dx + m[4] * dy + m[7] * dz;
    const lz = m[2] * dx + m[5] * dy + m[8] * dz;
    const qx = lx < -h.x ? -h.x : lx > h.x ? h.x : lx;
    const qy = ly < -h.y ? -h.y : ly > h.y ? h.y : ly;
    const qz = lz < -h.z ? -h.z : lz > h.z ? h.z : lz;
    const wx = m[0] * qx + m[1] * qy + m[2] * qz + c.p.x;
    const wy = m[3] * qx + m[4] * qy + m[5] * qz + c.p.y;
    const wz = m[6] * qx + m[7] * qy + m[8] * qz + c.p.z;
    if (wy < y - 0.2 || wy > y + K.P_HEIGHT + 0.3) return Infinity;
    return Math.hypot(wx - x, wz - z);
  }
  if (c.shape === 1) {
    if (c.p.y + c.hy < y - 0.2 || c.p.y - c.hy > y + K.P_HEIGHT) return Infinity;
    return Math.max(0, Math.hypot(x - c.p.x, z - c.p.z) - c.r);
  }
  if (c.p.y + c.r < y - 0.2 || c.p.y - c.r > y + K.P_HEIGHT) return Infinity;
  return Math.max(0, Math.hypot(x - c.p.x, z - c.p.z) - c.r);
}

/** Is a fast-moving knock-collider about to sweep through us? */
function hazardNear(world, p, radius) {
  for (let i = 0; i < world.dynamics.length; i++) {
    const c = world.dynamics[i];
    if (!c.knock || c.dead) continue;
    if (xzDistTo(c, p.x, p.y, p.z) > radius) continue;
    world.carry(c, p.x, p.y + 0.7, p.z, _t);
    const vx = (_t.x - p.x) / K.DT, vz = (_t.z - p.z) / K.DT;
    if (vx * vx + vz * vz > 10) return true;
  }
  return false;
}

export class BotBrain {
  constructor(id, seed) {
    this.id = id;
    this.rng = makeRng((seed * 1e9) | 0 || id * 7919);
    // personality
    this.skill = 0.5 + this.rng() * 0.5;          // 0.5..1.0
    this.speed = 0.78 + this.rng() * 0.22;
    this.jumpy = this.rng();
    this.diveLove = this.rng();
    this.reaction = 3 + Math.floor(this.rng() * 7);
    this.wobblePhase = this.rng() * TAU;
    this.reset(null);
  }

  reset(level) {
    this.wp = 0;
    this.timer = 0;
    this.stuckT = 0;
    this.lastX = 0; this.lastZ = 0;
    this.target = null;
    this.tileTarget = null;
    this.jumpCd = 0;
    this.diveCd = 0;
    this.wanderA = this.rng() * TAU;
    this.wanderT = 0;
    this.waitT = 0;
    this.dangerT = 0;
    this.pendingDive = 0;
  }

  think(p, inp, world, level, room, frozen) {
    inp.jump = false;
    inp.dive = false;
    if (frozen || p.status !== ST_ALIVE || p.spectator) { inp.mx = 0; inp.mz = 0; return; }
    if (this.jumpCd > 0) this.jumpCd--;
    if (this.diveCd > 0) this.diveCd--;
    this.timer++;

    switch (level.mode) {
      case 'race': this.race(p, inp, world, level); break;
      case 'survive': this.survive(p, inp, world, level, room); break;
      case 'crown': this.crown(p, inp, world, level, room); break;
      default: this.idle(p, inp, world); break;
    }
  }

  // ---------------------------------------------------------------- steering
  drive(p, inp, tx, tz, world, opts = {}) {
    let dx = tx - p.x, dz = tz - p.z;
    const d = Math.hypot(dx, dz) || 1;
    dx /= d; dz /= d;

    // wobble so they don't move like robots
    const w = Math.sin(this.timer * 0.06 + this.wobblePhase) * (0.30 * (1.05 - this.skill));
    const ca = Math.cos(w), sa = Math.sin(w);
    let ax = dx * ca - dz * sa;
    let az = dx * sa + dz * ca;

    const halt = () => { inp.mx = 0; inp.mz = 0; this.lastX = p.x; this.lastZ = p.z; };

    // ---- hazard timing: let the hammer / bar sweep past first ----
    if (opts.dodge !== false && p.grounded) {
      const danger = hazardNear(world, p, 2.1 + this.skill * 0.9);
      if (danger) {
        this.dangerT = (this.dangerT || 0) + 1;
        if (this.dangerT < 95) { halt(); return d; }
      } else {
        this.dangerT = 0;
      }
    }

    // ---- ledge / gap probing at three ranges ----
    if (opts.avoidGaps !== false) {
      const nearG = groundTopAt(world, p.x + ax * 1.35, p.z + az * 1.35, p.y);
      if (nearG === null) {
        const midG = groundTopAt(world, p.x + ax * 3.0, p.z + az * 3.0, p.y);
        const farG = groundTopAt(world, p.x + ax * 4.6, p.z + az * 4.6, p.y);
        if (midG !== null || farG !== null) {
          // a real gap with a landing on the other side -> commit
          this.waitT = 0;
          inp.mx = ax * this.speed; inp.mz = az * this.speed;
          if (p.grounded && this.jumpCd === 0) {
            inp.jump = true;
            this.jumpCd = 15;
            if (farG !== null && midG === null && this.diveCd === 0) { this.diveCd = 45; this.pendingDive = 7; }
          }
          this.tickPending(p, inp);
          return d;
        }
        // scan an arc for a safe heading that still makes progress
        let bestScore = -Infinity, bx = ax, bz = az, found = false;
        for (let i = -7; i <= 7; i++) {
          if (i === 0) continue;
          const a = (i / 7) * 2.3;
          const c = Math.cos(a), sn = Math.sin(a);
          const nx = ax * c - az * sn, nz = ax * sn + az * c;
          if (groundTopAt(world, p.x + nx * 1.5, p.z + nz * 1.5, p.y) === null) continue;
          const score = (nx * dx + nz * dz) - Math.abs(i) * 0.04;
          if (score > bestScore) { bestScore = score; bx = nx; bz = nz; found = true; }
        }
        if (found) { ax = bx; az = bz; this.waitT = 0; }
        else {
          this.waitT = (this.waitT || 0) + 1;
          if (this.waitT < 120) { halt(); return d; }
          if (p.grounded && this.jumpCd === 0) { inp.jump = true; this.jumpCd = 20; this.waitT = 0; }
        }
      } else if (nearG > p.y + 0.42 && this.jumpCd === 0 && p.grounded) {
        inp.jump = true;                      // step up onto a ledge
        this.jumpCd = 10;
      }
    }

    // stuck detection
    const moved = Math.hypot(p.x - this.lastX, p.z - this.lastZ);
    this.lastX = p.x; this.lastZ = p.z;
    if (moved < 0.035 && p.grounded) {
      this.stuckT++;
      if (this.stuckT > 25) {
        const a = this.rng() * TAU;
        ax = Math.cos(a); az = Math.sin(a);
        if (this.jumpCd === 0) { inp.jump = true; this.jumpCd = 12; }
        if (this.stuckT > 50) this.stuckT = 0;
      }
    } else this.stuckT = 0;

    const mag = this.speed * (opts.mag || 1);
    inp.mx = ax * mag;
    inp.mz = az * mag;
    this.tickPending(p, inp);
    return d;
  }

  tickPending(p, inp) {
    if (this.pendingDive) {
      this.pendingDive--;
      if (this.pendingDive === 0 && !p.grounded) inp.dive = true;
    }
  }

  // ---------------------------------------------------------------- modes
  race(p, inp, world, level) {
    const path = level.botPath;
    if (!path) return this.idle(p, inp, world);
    // advance along the path by proximity AND by z progress so they never stall
    while (this.wp < path.length - 1) {
      const [wx, wz] = path[this.wp];
      if (p.z > wz - 1.0 || Math.hypot(p.x - wx, p.z - wz) < 3.2) this.wp++;
      else break;
    }
    if (this.wp < 0) this.wp = 0;
    const [tx, tz] = path[Math.min(this.wp, path.length - 1)];
    this.drive(p, inp, tx, tz, world);

    // opportunistic dive to cross the moving-platform void faster
    if (!p.grounded && p.vy < -1 && this.diveCd === 0 && this.diveLove > 0.55 && p.z > 80 && p.z < 125) {
      inp.dive = true; this.diveCd = 50;
    }
  }

  survive(p, inp, world, level, room) {
    // stay on tiles nobody has stepped on; re-target when ours starts crumbling
    const tiles = world.tiles;
    const trig = room.tileTrig;
    const myLayerY = p.y;

    let retarget = !this.tileTarget;
    if (this.tileTarget) {
      const t = this.tileTarget;
      const c = world.byId.get(t.id);
      if (!c || c.dead || Math.abs(t.y - myLayerY) > 5) retarget = true;
      else if (Math.hypot(p.x - t.x, p.z - t.z) < 0.8) retarget = true;
      else if (trig[t.i] > 0 && room.tick - trig[t.i] > 10) retarget = true;
    }

    if (retarget || this.timer % 24 === 0) {
      let best = null, bestScore = -Infinity;
      for (let i = 0; i < tiles.length; i++) {
        const t = tiles[i];
        const c = world.byId.get(t.id);
        if (!c || c.dead) continue;
        if (t.y > p.y + 1.0 || t.y < p.y - 5.0) continue;
        const d = Math.hypot(p.x - t.x, p.z - t.z);
        if (d < 1.4 || d > 9) continue;
        let score = -d * 0.5;
        if (trig[i] > 0) score -= 26;                  // already crumbling
        score -= Math.hypot(t.x, t.z) * 0.07;          // hug the middle, more escapes
        score += this.rng() * 1.5;
        if (score > bestScore) { bestScore = score; best = { id: t.id, x: t.x, y: t.y, z: t.z, i }; }
      }
      if (best) this.tileTarget = best;
    }

    if (this.tileTarget) {
      this.drive(p, inp, this.tileTarget.x, this.tileTarget.z, world);
      // hop between tiles — looks alive and avoids edge snags
      if (p.grounded && this.jumpCd === 0 && this.rng() < 0.05 + this.jumpy * 0.05) {
        inp.jump = true; this.jumpCd = 18;
      }
    } else {
      this.idle(p, inp, world);
    }
  }

  crown(p, inp, world, level, room) {
    const cp = level.crownPos;
    const t = room.worldTime();
    const crownY = cp.y + Math.sin(t * cp.speed) * cp.bob;
    const distToCentre = Math.hypot(p.x - cp.x, p.z - cp.z);

    // Near the summit -> go for the grab
    if (p.y > 19.5) {
      this.drive(p, inp, cp.x, cp.z, world, { avoidGaps: false });
      if (p.grounded && distToCentre < 4.5 && this.jumpCd === 0) { inp.jump = true; this.jumpCd = 14; }
      if (!p.grounded && p.y > crownY - 2.6 && this.diveCd === 0) { inp.dive = true; this.diveCd = 30; }
      return;
    }

    // Find the closest riser: a disc slightly above us
    let best = null, bestScore = -Infinity;
    for (const c of world.dynamics) {
      if (c.shape !== 1 || c.dead) continue;
      const top = c.p.y + c.hy;
      const dy = top - p.y;
      if (dy < 0.3 || dy > 4.6) continue;
      const d = Math.hypot(p.x - c.p.x, p.z - c.p.z);
      if (d > 13) continue;
      const score = dy * 1.6 - d * 0.8;
      if (score > bestScore) { bestScore = score; best = c; }
    }

    if (best) {
      const d = this.drive(p, inp, best.p.x, best.p.z, world, { avoidGaps: false });
      if (p.grounded && d < 4.6 && this.jumpCd === 0) { inp.jump = true; this.jumpCd = 12; }
      if (!p.grounded && d > 2.4 && d < 6 && this.diveCd === 0 && this.diveLove > 0.5) {
        inp.dive = true; this.diveCd = 40;
      }
      return;
    }

    // On the floor: bounce pad hunting
    if (p.y < 3) {
      let pad = null, pd = Infinity;
      for (const c of world.statics) {
        if (c.surface !== 1) continue;
        const d = Math.hypot(p.x - c.p.x, p.z - c.p.z);
        if (d < pd) { pd = d; pad = c; }
      }
      if (pad) {
        this.drive(p, inp, pad.p.x, pad.p.z, world, { avoidGaps: false });
        return;
      }
    }
    this.drive(p, inp, cp.x, cp.z, world, { avoidGaps: false });
  }

  idle(p, inp, world) {
    this.wanderT--;
    if (this.wanderT <= 0) {
      this.wanderT = 40 + Math.floor(this.rng() * 90);
      this.wanderA = this.rng() * TAU;
      this.wanderR = 4 + this.rng() * 12;
    }
    const tx = Math.cos(this.wanderA) * (this.wanderR || 8);
    const tz = Math.sin(this.wanderA) * (this.wanderR || 8);
    this.drive(p, inp, tx, tz, world, { mag: 0.55 });
    if (p.grounded && this.rng() < 0.012) inp.jump = true;
    if (p.grounded && this.rng() < 0.005) inp.dive = true;
  }
}

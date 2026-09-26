// World = a bag of colliders with deterministic, time-driven motion.
// Both server and client build the identical world from a level definition and
// advance it with the same tick number, so client prediction stays in lockstep.

import { basisFromEuler, rotApply, TAU } from './math.js';

export const SHAPE_BOX = 0;
export const SHAPE_CYL = 1;
export const SHAPE_SPH = 2;

export const SURF_NORMAL = 0;
export const SURF_BOUNCE = 1;
export const SURF_CONVEYOR = 2;
export const SURF_SLIP = 3;

let _uid = 0;

function baseCollider(shape) {
  return {
    id: _uid++,
    shape,
    p: { x: 0, y: 0, z: 0 },
    h: { x: 1, y: 1, z: 1 },
    r: 1,
    hy: 1,
    m: basisFromEuler(0, 0, 0),
    // authored rest pose
    bp: { x: 0, y: 0, z: 0 },
    be: { x: 0, y: 0, z: 0 },
    // previous frame transform (for carrying riders)
    pp: { x: 0, y: 0, z: 0 },
    pm: basisFromEuler(0, 0, 0),
    motion: null,
    dynamic: false,
    surface: SURF_NORMAL,
    knock: 0,          // knockback multiplier when struck
    bounce: 0,         // launch velocity for bounce pads
    conveyor: 0,       // m/s along local +Z
    solid: true,
    dead: false,       // disabled (fallen hex tile)
    group: '',
    vis: null,         // renderer hints
  };
}

export class LevelBuilder {
  constructor() {
    this.colliders = [];
    this.decor = [];
    this.triggers = [];
    this.spawns = [];
    this.tiles = [];
  }

  box(x, y, z, hx, hy, hz, opts = {}) {
    const c = baseCollider(SHAPE_BOX);
    c.bp.x = x; c.bp.y = y; c.bp.z = z;
    c.h.x = hx; c.h.y = hy; c.h.z = hz;
    c.be.x = opts.rx || 0; c.be.y = opts.ry || 0; c.be.z = opts.rz || 0;
    Object.assign(c, opts);
    c.vis = { kind: 'box', ...(opts.vis || {}) };
    this.colliders.push(c);
    return c;
  }

  cyl(x, y, z, r, hy, opts = {}) {
    const c = baseCollider(SHAPE_CYL);
    c.bp.x = x; c.bp.y = y; c.bp.z = z;
    c.r = r; c.hy = hy;
    Object.assign(c, opts);
    c.vis = { kind: 'cyl', ...(opts.vis || {}) };
    this.colliders.push(c);
    return c;
  }

  sphere(x, y, z, r, opts = {}) {
    const c = baseCollider(SHAPE_SPH);
    c.bp.x = x; c.bp.y = y; c.bp.z = z;
    c.r = r;
    Object.assign(c, opts);
    c.vis = { kind: 'sph', ...(opts.vis || {}) };
    this.colliders.push(c);
    return c;
  }

  trigger(kind, x, y, z, hx, hy, hz, data = {}) {
    this.triggers.push({ kind, p: { x, y, z }, h: { x: hx, y: hy, z: hz }, ...data });
  }

  addDecor(d) { this.decor.push(d); return d; }
}

/** Evaluate a motion descriptor at time t (seconds) into pos/euler. */
function applyMotion(c, t) {
  const mo = c.motion;
  let px = c.bp.x, py = c.bp.y, pz = c.bp.z;
  let ex = c.be.x, ey = c.be.y, ez = c.be.z;

  switch (mo.k) {
    case 'spin': {
      const a = mo.phase + t * mo.speed;
      ex += (mo.ax || 0) * a;
      ey += (mo.ay === undefined ? 1 : mo.ay) * a;
      ez += (mo.az || 0) * a;
      break;
    }
    case 'path': {
      // ping-pong between base and base+delta using a smooth cosine
      const s = 0.5 - 0.5 * Math.cos(mo.phase + t * mo.speed);
      px += mo.dx * s; py += mo.dy * s; pz += mo.dz * s;
      break;
    }
    case 'loop': {
      // constant-speed linear ping-pong (crisper than cosine for lifts)
      const tri = Math.abs(((mo.phase + t * mo.speed) % 2) - 1);
      px += mo.dx * tri; py += mo.dy * tri; pz += mo.dz * tri;
      break;
    }
    case 'orbit': {
      const a = mo.phase + t * mo.speed;
      px = mo.cx + Math.cos(a) * mo.r;
      pz = mo.cz + Math.sin(a) * mo.r;
      py = c.bp.y;
      if (mo.face) ey += -a;
      break;
    }
    case 'pend': {
      const a = Math.sin(mo.phase + t * mo.speed) * mo.amp;
      if (mo.axis === 'x') {
        ex = a;
        py = mo.py - Math.cos(a) * mo.len;
        pz = mo.pz + Math.sin(a) * mo.len;
      } else {
        ez = a;
        py = mo.py - Math.cos(a) * mo.len;
        px = mo.px - Math.sin(a) * mo.len;
      }
      break;
    }
    case 'bob': {
      py += Math.sin(mo.phase + t * mo.speed) * mo.amp;
      break;
    }
  }
  c.p.x = px; c.p.y = py; c.p.z = pz;
  basisFromEuler(ex, ey, ez, c.m);
  c.eu = c.eu || { x: 0, y: 0, z: 0 };
  c.eu.x = ex; c.eu.y = ey; c.eu.z = ez;
}

export class World {
  constructor(level) {
    this.level = level;
    const b = new LevelBuilder();
    level.build(b);
    this.colliders = b.colliders;
    this.decor = b.decor;
    this.triggers = b.triggers;
    this.spawns = b.spawns;
    this.tiles = b.tiles;
    this.dynamics = [];
    this.statics = [];
    this.byId = new Map();
    this._q = [];

    for (const c of this.colliders) {
      this.byId.set(c.id, c);
      c.dynamic = !!c.motion;
      if (c.dynamic) this.dynamics.push(c); else this.statics.push(c);
      c.p.x = c.bp.x; c.p.y = c.bp.y; c.p.z = c.bp.z;
      basisFromEuler(c.be.x, c.be.y, c.be.z, c.m);
      c.eu = { x: c.be.x, y: c.be.y, z: c.be.z };
      c.pp.x = c.p.x; c.pp.y = c.p.y; c.pp.z = c.p.z;
      c.pm.set(c.m);
      this.computeAabb(c);
    }
    this.tiles.forEach((t, i) => { const c = this.byId.get(t.id); if (c) c.tileIndex = i; });
    this.time = 0;
    this._buildGrid();
  }

  // ---- uniform grid broadphase over static colliders ----
  _buildGrid() {
    const CS = 8;
    this.cellSize = CS;
    this.grid = new Map();
    for (const c of this.statics) {
      const a = c.aabb;
      const x0 = Math.floor(a.x0 / CS), x1 = Math.floor(a.x1 / CS);
      const z0 = Math.floor(a.z0 / CS), z1 = Math.floor(a.z1 / CS);
      for (let gx = x0; gx <= x1; gx++) {
        for (let gz = z0; gz <= z1; gz++) {
          const key = gx * 73856093 ^ gz * 19349663;
          let arr = this.grid.get(key);
          if (!arr) { arr = []; this.grid.set(key, arr); }
          arr.push(c);
        }
      }
    }
  }

  /** Colliders whose AABB overlaps the capsule's swept box. */
  queryAabb(x, y, z, r, h) {
    const out = this._q;
    out.length = 0;
    const pad = r + 0.6;
    const x0 = x - pad, x1 = x + pad;
    const y0 = y - 0.7, y1 = y + h + 0.5;
    const z0 = z - pad, z1 = z + pad;
    const CS = this.cellSize;
    const gx0 = Math.floor(x0 / CS), gx1 = Math.floor(x1 / CS);
    const gz0 = Math.floor(z0 / CS), gz1 = Math.floor(z1 / CS);
    for (let gx = gx0; gx <= gx1; gx++) {
      for (let gz = gz0; gz <= gz1; gz++) {
        const arr = this.grid.get(gx * 73856093 ^ gz * 19349663);
        if (!arr) continue;
        for (let i = 0; i < arr.length; i++) {
          const c = arr[i];
          const a = c.aabb;
          if (a.x1 < x0 || a.x0 > x1 || a.y1 < y0 || a.y0 > y1 || a.z1 < z0 || a.z0 > z1) continue;
          if (out.indexOf(c) === -1) out.push(c);
        }
      }
    }
    for (let i = 0; i < this.dynamics.length; i++) {
      const c = this.dynamics[i];
      const a = c.aabb;
      if (a.x1 < x0 || a.x0 > x1 || a.y1 < y0 || a.y0 > y1 || a.z1 < z0 || a.z0 > z1) continue;
      out.push(c);
    }
    return out;
  }

  computeAabb(c) {
    if (!c.aabb) c.aabb = { x0: 0, y0: 0, z0: 0, x1: 0, y1: 0, z1: 0 };
    const a = c.aabb;
    if (c.shape === SHAPE_BOX) {
      const m = c.m;
      const ex = Math.abs(m[0]) * c.h.x + Math.abs(m[1]) * c.h.y + Math.abs(m[2]) * c.h.z;
      const ey = Math.abs(m[3]) * c.h.x + Math.abs(m[4]) * c.h.y + Math.abs(m[5]) * c.h.z;
      const ez = Math.abs(m[6]) * c.h.x + Math.abs(m[7]) * c.h.y + Math.abs(m[8]) * c.h.z;
      a.x0 = c.p.x - ex; a.x1 = c.p.x + ex;
      a.y0 = c.p.y - ey; a.y1 = c.p.y + ey;
      a.z0 = c.p.z - ez; a.z1 = c.p.z + ez;
    } else if (c.shape === SHAPE_CYL) {
      a.x0 = c.p.x - c.r; a.x1 = c.p.x + c.r;
      a.y0 = c.p.y - c.hy; a.y1 = c.p.y + c.hy;
      a.z0 = c.p.z - c.r; a.z1 = c.p.z + c.r;
    } else {
      a.x0 = c.p.x - c.r; a.x1 = c.p.x + c.r;
      a.y0 = c.p.y - c.r; a.y1 = c.p.y + c.r;
      a.z0 = c.p.z - c.r; a.z1 = c.p.z + c.r;
    }
  }

  /** Advance dynamic transforms to absolute time `t` (seconds since round start). */
  setTime(t) {
    this.time = t;
    for (let i = 0; i < this.dynamics.length; i++) {
      const c = this.dynamics[i];
      c.pp.x = c.p.x; c.pp.y = c.p.y; c.pp.z = c.p.z;
      c.pm.set(c.m);
      applyMotion(c, t);
      this.computeAabb(c);
    }
  }

  /** Where does world point (x,y,z) end up after this collider's last movement? */
  carry(c, x, y, z, out) {
    // local = pmᵀ * (p - pp) ; world = pm_new * local + p_new
    const dx = x - c.pp.x, dy = y - c.pp.y, dz = z - c.pp.z;
    const pm = c.pm;
    const lx = pm[0] * dx + pm[3] * dy + pm[6] * dz;
    const ly = pm[1] * dx + pm[4] * dy + pm[7] * dz;
    const lz = pm[2] * dx + pm[5] * dy + pm[8] * dz;
    rotApply(c.m, lx, ly, lz, out);
    out.x += c.p.x; out.y += c.p.y; out.z += c.p.z;
    return out;
  }

  /** Yaw delta applied by this collider's rotation over the last step. */
  carryYaw(c) {
    const m = c.m, pm = c.pm;
    const aNow = Math.atan2(m[2], m[8]);
    const aPrev = Math.atan2(pm[2], pm[8]);
    let d = aNow - aPrev;
    if (d > Math.PI) d -= TAU;
    if (d < -Math.PI) d += TAU;
    return d;
  }
}

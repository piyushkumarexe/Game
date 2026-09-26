// Deterministic character simulation. Identical code runs on the server (authority)
// and on the client (prediction + replay). Any divergence here shows up as rubber-banding.

import * as K from './constants.js';
import { clamp, dampAngle } from './math.js';
import { makeHit, resolveAgainst } from './collision.js';
import { SURF_BOUNCE, SURF_CONVEYOR, SURF_SLIP } from './world.js';

const hit = makeHit();
const _c = { x: 0, y: 0, z: 0 };
const _c2 = { x: 0, y: 0, z: 0 };

export const ST_ALIVE = 0;
export const ST_RESPAWN = 1;
export const ST_QUALIFIED = 2;
export const ST_OUT = 3;

export function makePlayer(id, name, color) {
  return {
    id, name, color,
    x: 0, y: 2, z: 0,
    vx: 0, vy: 0, vz: 0,
    yaw: 0,
    grounded: false, groundId: -1, coyote: 0, jumpBuf: 0,
    dive: 0, diveT: 0, diveCd: 0, getUp: 0,
    tumble: 0,
    status: ST_ALIVE,
    respawnT: 0,
    checkpoint: 0,
    progress: 0,
    place: 0,
    lastSeq: 0,
    lastGroundY: 2,
    bot: false,
    spectator: false,
    // presentation-only, not part of the authoritative contract
    anim: 0, landImpact: 0,
  };
}

export function emptyInput() {
  return { seq: 0, mx: 0, mz: 0, jump: false, dive: false, yaw: 0 };
}

const contacts = [];

/**
 * Advance one player by exactly one tick.
 * @param {object} pl      player state (mutated)
 * @param {object} inp     input for this tick
 * @param {World}  world
 * @param {object} ev      optional event sink: { onLand, onBonk, onBounce, onTumble }
 */
export function stepPlayer(pl, inp, world, ev) {
  const dt = K.DT;

  if (pl.status === ST_OUT || pl.status === ST_QUALIFIED) {
    return;
  }

  if (pl.status === ST_RESPAWN) {
    pl.respawnT--;
    pl.vx = pl.vy = pl.vz = 0;
    if (pl.respawnT <= 0) pl.status = ST_ALIVE;
    return;
  }

  // ---- ride moving platforms ----
  if (pl.grounded && pl.groundId >= 0) {
    const g = world.byId.get(pl.groundId);
    if (g && g.dynamic && !g.dead) {
      world.carry(g, pl.x, pl.y, pl.z, _c);
      pl.x = _c.x; pl.y = _c.y; pl.z = _c.z;
      const dy = world.carryYaw(g);
      pl.yaw += dy;
    }
  }

  const r = K.P_RADIUS;
  const halfH = K.P_HEIGHT;

  // ---- timers ----
  if (pl.diveCd > 0) pl.diveCd--;
  if (pl.tumble > 0) pl.tumble--;
  if (pl.getUp > 0) pl.getUp--;

  const locked = pl.tumble > 0 || pl.dive === 1 || pl.getUp > 0;

  // ---- desired direction ----
  let wx = inp.mx, wz = inp.mz;
  const wlen = Math.hypot(wx, wz);
  if (wlen > 1) { wx /= wlen; wz /= wlen; }
  const wishMag = Math.min(wlen, 1);

  if (!locked && wishMag > 0.02) {
    pl.yaw = dampAngle(pl.yaw, Math.atan2(wx, wz), K.TURN_RATE, dt);
  }

  // ---- horizontal accel / drag ----
  const accel = pl.grounded ? K.GROUND_ACCEL : K.AIR_ACCEL;
  if (!locked && wishMag > 0.02) {
    const target = K.RUN_SPEED * wishMag;
    const tvx = wx * target, tvz = wz * target;
    let dvx = tvx - pl.vx, dvz = tvz - pl.vz;
    const dlen = Math.hypot(dvx, dvz);
    const maxd = accel * dt;
    if (dlen > maxd) { dvx = (dvx / dlen) * maxd; dvz = (dvz / dlen) * maxd; }
    pl.vx += dvx; pl.vz += dvz;
  }

  // drag
  let drag;
  if (pl.grounded) {
    if (pl.dive === 1) drag = K.DIVE_DRAG_GROUND;
    else if (pl.tumble > 0) drag = 5.5;
    else if (wishMag > 0.02) drag = 1.4;
    else drag = K.GROUND_DRAG;
  } else {
    drag = K.AIR_DRAG;
  }
  const df = Math.exp(-drag * dt);
  pl.vx *= df; pl.vz *= df;

  // ---- jump ----
  if (inp.jump) pl.jumpBuf = K.JUMP_BUFFER_TICKS; else if (pl.jumpBuf > 0) pl.jumpBuf--;
  if (pl.grounded) pl.coyote = K.COYOTE_TICKS; else if (pl.coyote > 0) pl.coyote--;

  if (!locked && pl.jumpBuf > 0 && pl.coyote > 0) {
    pl.vy = K.JUMP_VEL;
    pl.grounded = false;
    pl.groundId = -1;
    pl.coyote = 0;
    pl.jumpBuf = 0;
    if (ev && ev.onJump) ev.onJump(pl);
  }

  // ---- dive ----
  if (inp.dive && pl.dive === 0 && pl.tumble === 0 && pl.getUp === 0 && pl.diveCd === 0) {
    const fx = Math.sin(pl.yaw), fz = Math.cos(pl.yaw);
    const boost = pl.grounded ? K.DIVE_FWD : K.DIVE_FWD * 0.55;
    pl.vx += fx * boost;
    pl.vz += fz * boost;
    if (pl.grounded) pl.vy = K.DIVE_UP;
    pl.dive = 1;
    pl.diveT = K.DIVE_TICKS;
    pl.diveCd = K.DIVE_COOLDOWN_TICKS + K.DIVE_TICKS;
    pl.grounded = false;
    if (ev && ev.onDive) ev.onDive(pl);
  }
  if (pl.dive === 1) {
    pl.diveT--;
    if (pl.diveT <= 0 && pl.grounded) {
      pl.dive = 0;
      pl.getUp = K.DIVE_GET_UP_TICKS;
    }
  }

  // ---- gravity ----
  pl.vy += K.GRAVITY * dt;
  if (pl.vy < K.MAX_FALL) pl.vy = K.MAX_FALL;

  // ---- integrate ----
  const wasGrounded = pl.grounded;
  const fallSpeed = pl.vy;
  pl.x += pl.vx * dt;
  pl.y += pl.vy * dt;
  pl.z += pl.vz * dt;

  // ---- collide ----
  pl.grounded = false;
  pl.groundId = -1;
  let bestGroundY = -2;
  contacts.length = 0;

  const list = world.queryAabb(pl.x, pl.y, pl.z, r, halfH);

  for (let iter = 0; iter < 4; iter++) {
    let moved = false;
    for (let i = 0; i < list.length; i++) {
      const c = list[i];
      if (c.dead || !c.solid) continue;
      const by = pl.y + r;
      const ty = pl.y + halfH - r;
      resolveAgainst(pl.x, by, pl.z, ty, r, c, hit);
      if (!hit.hit) continue;
      const push = hit.depth + 1e-4;
      pl.x += hit.nx * push;
      pl.y += hit.ny * push;
      pl.z += hit.nz * push;
      moved = true;
      if (iter === 0 || contacts.length < 8) {
        contacts.push(c, hit.nx, hit.ny, hit.nz);
      }
      if (hit.ny > bestGroundY) {
        bestGroundY = hit.ny;
        if (hit.ny > K.GROUND_NORMAL_Y) {
          pl.grounded = true;
          pl.groundId = c.id;
        }
      }
    }
    if (!moved) break;
  }

  // ---- contact response ----
  let bounced = 0;
  for (let i = 0; i < contacts.length; i += 4) {
    const c = contacts[i];
    const nx = contacts[i + 1], ny = contacts[i + 2], nz = contacts[i + 3];

    // Surface point velocity of a moving collider at the contact
    let svx = 0, svy = 0, svz = 0;
    if (c.dynamic) {
      world.carry(c, pl.x, pl.y + halfH * 0.5, pl.z, _c2);
      svx = (_c2.x - pl.x) / dt;
      svy = (_c2.y - (pl.y + halfH * 0.5)) / dt;
      svz = (_c2.z - pl.z) / dt;
    }

    // Cancel velocity into the surface (relative to the surface's own motion)
    const rvx = pl.vx - svx, rvy = pl.vy - svy, rvz = pl.vz - svz;
    const vn = rvx * nx + rvy * ny + rvz * nz;
    if (vn < 0) {
      pl.vx -= nx * vn; pl.vy -= ny * vn; pl.vz -= nz * vn;
    }

    // Getting smacked by a spinner / hammer
    if (c.dynamic && c.knock > 0) {
      const sMag = Math.hypot(svx, svz);
      const approach = -(svx * nx + svz * nz);
      if (sMag > 1.2 && approach < 0) {
        const power = Math.min(sMag * c.knock, 13);
        pl.vx += nx * power;
        pl.vz += nz * power;
        pl.vy = Math.max(pl.vy, Math.min(4.0 + power * 0.28, 11));
        if (power > K.BONK_MIN_SPEED && pl.tumble === 0) {
          pl.tumble = K.TUMBLE_TICKS;
          pl.dive = 0;
          if (ev && ev.onTumble) ev.onTumble(pl, power);
        }
      }
    }

    if (c.surface === SURF_BOUNCE && ny > 0.3) {
      pl.vy = c.bounce;
      bounced = c.bounce;
      pl.grounded = false;
      pl.groundId = -1;
      if (ev && ev.onBounce) ev.onBounce(pl, c);
    } else if (c.surface === SURF_CONVEYOR && ny > K.GROUND_NORMAL_Y) {
      // the belt is moving ground: translate the player, don't accelerate them
      const m = c.m;
      pl.x += m[2] * c.conveyor * dt;
      pl.z += m[8] * c.conveyor * dt;
    } else if (c.surface === SURF_SLIP && ny > K.GROUND_NORMAL_Y) {
      // ice: undo most of this tick's ground drag
      pl.vx /= df; pl.vz /= df;
      pl.vx *= 0.995; pl.vz *= 0.995;
    }
  }

  if (pl.grounded && !bounced) {
    if (!wasGrounded) {
      const impact = -fallSpeed;
      if (ev && ev.onLand) ev.onLand(pl, impact);
      if (impact > 24 && pl.tumble === 0 && pl.dive === 0) {
        pl.tumble = Math.floor(K.TUMBLE_TICKS * 0.6);
        if (ev && ev.onTumble) ev.onTumble(pl, impact * 0.4);
      }
    }
    pl.lastGroundY = pl.y;
    if (pl.vy < 0) pl.vy = 0;
  }

  // cap horizontal runaway
  const hs = Math.hypot(pl.vx, pl.vz);
  const cap = 34;
  if (hs > cap) { pl.vx = (pl.vx / hs) * cap; pl.vz = (pl.vz / hs) * cap; }
}

/** Soft body-to-body shoving. Run after all players have stepped. */
export function resolvePlayerCollisions(players, ev) {
  const dt = K.DT;
  const n = players.length;
  const rr = K.P_RADIUS * 2;
  for (let i = 0; i < n; i++) {
    const a = players[i];
    if (a.status !== ST_ALIVE) continue;
    for (let j = i + 1; j < n; j++) {
      const b = players[j];
      if (b.status !== ST_ALIVE) continue;
      const dy = a.y - b.y;
      if (dy > K.P_HEIGHT || dy < -K.P_HEIGHT) continue;
      let dx = a.x - b.x, dz = a.z - b.z;
      let d2 = dx * dx + dz * dz;
      if (d2 > rr * rr || d2 < 1e-9) {
        if (d2 < 1e-9) { dx = 0.01; dz = 0; d2 = 1e-4; } else continue;
      }
      const d = Math.sqrt(d2);
      const overlap = rr - d;
      const nx = dx / d, nz = dz / d;
      const push = overlap * 0.5;
      a.x += nx * push; a.z += nz * push;
      b.x -= nx * push; b.z -= nz * push;

      const rel = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz;
      if (rel < 0) {
        const imp = -rel * 0.5 + K.PUSH_STRENGTH * dt * 0.5;
        a.vx += nx * imp; a.vz += nz * imp;
        b.vx -= nx * imp; b.vz -= nz * imp;
      }

      // A diving player bowls people over
      const aDive = a.dive === 1, bDive = b.dive === 1;
      if (aDive !== bDive) {
        const diver = aDive ? a : b;
        const victim = aDive ? b : a;
        const sp = Math.hypot(diver.vx, diver.vz);
        if (sp > 4.2 && victim.tumble === 0) {
          const sx = victim === a ? nx : -nx;
          const sz = victim === a ? nz : -nz;
          victim.vx += sx * K.DIVE_BONK_IMPULSE;
          victim.vz += sz * K.DIVE_BONK_IMPULSE;
          victim.vy = Math.max(victim.vy, 4.4);
          victim.tumble = K.TUMBLE_TICKS;
          victim.dive = 0;
          if (ev && ev.onBonk) ev.onBonk(diver, victim);
        }
      }
    }
  }
}

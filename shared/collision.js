// Analytic capsule-vs-world collision. Deterministic, allocation-free in the hot path.
//
// The player is ALWAYS an upright capsule:
//   feet at p.y, segment from (p.x, p.y+r, p.z) to (p.x, p.y+h-r, p.z)
//
// Colliders come in three flavours, all resolved by minimum-translation push-out:
//   box      { p:{x,y,z}, h:{x,y,z}, m:Float64Array(9) }   oriented box
//   cyl      { p:{x,y,z}, r, hy }                          vertical cylinder (hy = half-height)
//   sphere   { p:{x,y,z}, r }

import { clamp } from './math.js';

const _a = { x: 0, y: 0, z: 0 };
const _b = { x: 0, y: 0, z: 0 };
const _p = { x: 0, y: 0, z: 0 };
const _q = { x: 0, y: 0, z: 0 };
const _n = { x: 0, y: 0, z: 0 };

/** Result object reused by the resolver. */
export function makeHit() {
  return { hit: false, nx: 0, ny: 0, nz: 0, depth: 0 };
}

function closestOnSeg(ax, ay, az, bx, by, bz, px, py, pz, out) {
  const dx = bx - ax, dy = by - ay, dz = bz - az;
  const dd = dx * dx + dy * dy + dz * dz;
  let t = dd > 1e-12 ? ((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / dd : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  out.x = ax + dx * t;
  out.y = ay + dy * t;
  out.z = az + dz * t;
  return out;
}

/**
 * Capsule (vertical, world) vs oriented box. Writes into `hit`.
 * cx,cy,cz = capsule bottom-sphere centre; ty = top-sphere centre y; r = radius.
 */
export function capsuleBox(cx, cy, cz, ty, r, box, hit) {
  const m = box.m, bp = box.p, bh = box.h;
  // world -> box local (transpose of basis)
  const ax0 = cx - bp.x, ay0 = cy - bp.y, az0 = cz - bp.z;
  const bx0 = cx - bp.x, by0 = ty - bp.y, bz0 = cz - bp.z;
  _a.x = m[0] * ax0 + m[3] * ay0 + m[6] * az0;
  _a.y = m[1] * ax0 + m[4] * ay0 + m[7] * az0;
  _a.z = m[2] * ax0 + m[5] * ay0 + m[8] * az0;
  _b.x = m[0] * bx0 + m[3] * by0 + m[6] * bz0;
  _b.y = m[1] * bx0 + m[4] * by0 + m[7] * bz0;
  _b.z = m[2] * bx0 + m[5] * by0 + m[8] * bz0;

  // Broad reject in local space
  const segMinX = Math.min(_a.x, _b.x), segMaxX = Math.max(_a.x, _b.x);
  const segMinY = Math.min(_a.y, _b.y), segMaxY = Math.max(_a.y, _b.y);
  const segMinZ = Math.min(_a.z, _b.z), segMaxZ = Math.max(_a.z, _b.z);
  if (segMinX - r > bh.x || segMaxX + r < -bh.x ||
      segMinY - r > bh.y || segMaxY + r < -bh.y ||
      segMinZ - r > bh.z || segMaxZ + r < -bh.z) { hit.hit = false; return hit; }

  // Iterate: closest point on segment <-> closest point on box
  closestOnSeg(_a.x, _a.y, _a.z, _b.x, _b.y, _b.z, 0, 0, 0, _p);
  for (let i = 0; i < 3; i++) {
    _q.x = clamp(_p.x, -bh.x, bh.x);
    _q.y = clamp(_p.y, -bh.y, bh.y);
    _q.z = clamp(_p.z, -bh.z, bh.z);
    closestOnSeg(_a.x, _a.y, _a.z, _b.x, _b.y, _b.z, _q.x, _q.y, _q.z, _p);
  }
  _q.x = clamp(_p.x, -bh.x, bh.x);
  _q.y = clamp(_p.y, -bh.y, bh.y);
  _q.z = clamp(_p.z, -bh.z, bh.z);

  let dx = _p.x - _q.x, dy = _p.y - _q.y, dz = _p.z - _q.z;
  let len = Math.sqrt(dx * dx + dy * dy + dz * dz);
  let depth;

  if (len > 1e-6) {
    if (len >= r) { hit.hit = false; return hit; }
    depth = r - len;
    dx /= len; dy /= len; dz /= len;
  } else {
    // Segment point is inside the box — escape along least-penetrating axis.
    const px = bh.x - Math.abs(_p.x);
    const py = bh.y - Math.abs(_p.y);
    const pz = bh.z - Math.abs(_p.z);
    if (py <= px && py <= pz) {
      dx = 0; dy = _p.y >= 0 ? 1 : -1; dz = 0; depth = py + r;
    } else if (px <= pz) {
      dx = _p.x >= 0 ? 1 : -1; dy = 0; dz = 0; depth = px + r;
    } else {
      dx = 0; dy = 0; dz = _p.z >= 0 ? 1 : -1; depth = pz + r;
    }
  }

  // local normal -> world
  hit.nx = m[0] * dx + m[1] * dy + m[2] * dz;
  hit.ny = m[3] * dx + m[4] * dy + m[5] * dz;
  hit.nz = m[6] * dx + m[7] * dy + m[8] * dz;
  hit.depth = depth;
  hit.hit = true;
  return hit;
}

/** Capsule vs vertical cylinder (hexagon tiles, pillars, rollers). */
export function capsuleCylinder(cx, cy, cz, ty, r, cyl, hit) {
  const cp = cyl.p;
  const dx = cx - cp.x, dz = cz - cp.z;
  const distSq = dx * dx + dz * dz;
  const rr = cyl.r + r;
  const capLo = cy - r, capHi = ty + r;
  const cylLo = cp.y - cyl.hy, cylHi = cp.y + cyl.hy;
  if (capLo > cylHi || capHi < cylLo) { hit.hit = false; return hit; }
  if (distSq > rr * rr) { hit.hit = false; return hit; }

  const dist = Math.sqrt(distSq);
  const penH = rr - dist;
  const penUp = cylHi - capLo;   // push capsule up onto the top face
  const penDn = capHi - cylLo;   // push capsule down below the bottom face

  if (penUp <= penDn && penUp <= penH) {
    hit.nx = 0; hit.ny = 1; hit.nz = 0; hit.depth = penUp; hit.hit = true; return hit;
  }
  if (penDn <= penH) {
    hit.nx = 0; hit.ny = -1; hit.nz = 0; hit.depth = penDn; hit.hit = true; return hit;
  }
  if (dist > 1e-6) { hit.nx = dx / dist; hit.nz = dz / dist; }
  else { hit.nx = 1; hit.nz = 0; }
  hit.ny = 0;
  hit.depth = penH;
  hit.hit = true;
  return hit;
}

/** Capsule vs sphere (bumpers, balls). */
export function capsuleSphere(cx, cy, cz, ty, r, sph, hit) {
  closestOnSeg(cx, cy, cz, cx, ty, cz, sph.p.x, sph.p.y, sph.p.z, _n);
  const dx = _n.x - sph.p.x, dy = _n.y - sph.p.y, dz = _n.z - sph.p.z;
  const rr = r + sph.r;
  const d2 = dx * dx + dy * dy + dz * dz;
  if (d2 > rr * rr) { hit.hit = false; return hit; }
  const d = Math.sqrt(d2);
  if (d > 1e-6) { hit.nx = dx / d; hit.ny = dy / d; hit.nz = dz / d; }
  else { hit.nx = 0; hit.ny = 1; hit.nz = 0; }
  hit.depth = rr - d;
  hit.hit = true;
  return hit;
}

export function resolveAgainst(cx, cy, cz, ty, r, col, hit) {
  switch (col.shape) {
    case 0: return capsuleBox(cx, cy, cz, ty, r, col, hit);
    case 1: return capsuleCylinder(cx, cy, cz, ty, r, col, hit);
    default: return capsuleSphere(cx, cy, cz, ty, r, col, hit);
  }
}

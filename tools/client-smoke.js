// Constructs every client-side scene object (levels, characters, particles) for all
// levels using a stubbed 2D canvas. No GPU needed — this catches the "undefined is not
// a function" class of bug that would otherwise only show up in a browser.

import * as THREE from 'three';

// ---------------------------------------------------------------- DOM stub
const ctx2d = new Proxy({}, {
  get(_, k) {
    if (k === 'createImageData') return (w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h });
    if (k === 'measureText') return () => ({ width: 120 });
    if (k === 'createLinearGradient' || k === 'createRadialGradient') return () => ({ addColorStop() {} });
    if (k === 'getImageData') return (x, y, w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h });
    if (k === 'canvas') return { width: 128, height: 128 };
    return () => {};
  },
  set() { return true; },
});

function makeCanvas() {
  return {
    width: 128, height: 128,
    getContext: () => ctx2d,
    toDataURL: () => 'data:,',
    style: {},
    addEventListener() {}, removeEventListener() {},
  };
}

globalThis.document = {
  createElement: (tag) => (tag === 'canvas' ? makeCanvas() : { style: {}, appendChild() {}, addEventListener() {}, classList: { add() {}, remove() {}, toggle() {} } }),
  createElementNS: () => makeCanvas(),
  querySelector: () => null,
  getElementById: () => null,
  addEventListener() {},
};
globalThis.window = { devicePixelRatio: 1, innerWidth: 1280, innerHeight: 720, addEventListener() {} };
try { Object.defineProperty(globalThis, 'navigator', { value: { userAgent: 'node', hardwareConcurrency: 8 }, configurable: true }); } catch {}


// ---------------------------------------------------------------- run
const { World } = await import('../shared/world.js');
const { LEVELS } = await import('../shared/levels.js');
const { LevelView } = await import('../src/render/levelMesh.js');
const { Bean } = await import('../src/render/character.js');
const { FX } = await import('../src/render/fx.js');

let fail = 0;
let totalTris = 0;

for (const [id, level] of Object.entries(LEVELS)) {
  try {
    const scene = new THREE.Scene();
    const world = new World(level);
    world.setTime(0);
    const view = new LevelView(scene, world, level);

    // 24 beans, like a full lobby
    const beans = [];
    for (let i = 0; i < 24; i++) beans.push(new Bean(scene, 'Player' + i, 0xff5f8a, i === 0));
    const fx = new FX(scene);

    // 3 seconds of simulated frames
    const trig = new Int32Array(world.tiles.length);
    for (let i = 0; i < Math.min(trig.length, 40); i++) trig[i] = 10 + i;
    for (let f = 0; f < 180; f++) {
      const t = f / 60;
      world.setTime(t);
      view.update(1 / 60, t, trig, 30 + f, level.tileFadeTicks || 26);
      for (let i = 0; i < beans.length; i++) {
        beans[i].update(1 / 60, {
          x: Math.sin(t + i), y: 1 + (i % 3), z: Math.cos(t + i), yaw: t,
          grounded: f % 40 < 30, dive: f % 97 < 8, tumble: f % 131 < 10,
          getUp: 0, vy: Math.sin(t) * 4, speed: 5, showTag: i !== 0,
        }, { x: 0, y: 5, z: -10 });
      }
      if (f % 20 === 0) { fx.burst(0, 1, 0, 10, 0xff0000); fx.ring(0, 0, 0, 0xffffff); fx.dust(0, 0, 0); }
      if (f === 60) fx.confetti(0, 2, 0, 200);
      fx.update(1 / 60);
    }

    let meshes = 0, tris = 0;
    scene.traverse((o) => {
      if (o.isInstancedMesh) { meshes++; tris += (o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count) / 3 * o.count; }
      else if (o.isMesh) { meshes++; tris += (o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count) / 3; }
    });
    totalTris += tris;
    console.log(`✅ ${id.padEnd(9)} colliders=${String(world.colliders.length).padStart(4)} meshes=${String(meshes).padStart(4)} tris=${String(Math.round(tris)).padStart(7)} dyn=${String(world.dynamics.length).padStart(3)} tiles=${String(world.tiles.length).padStart(4)} spawns=${world.spawns.length}`);

    view.dispose();
  } catch (e) {
    fail++;
    console.log(`❌ ${id}: ${e.message}\n${e.stack.split('\n').slice(1, 5).join('\n')}`);
  }
}

console.log(fail ? `\n${fail} level(s) failed` : '\nAll levels build and animate cleanly.');
process.exit(fail ? 1 : 0);

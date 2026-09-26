import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { buildMaterials } from './materials.js';

const TAU = Math.PI * 2;

function scaleUVs(geo, su, sv) {
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * su, uv.getY(i) * sv);
  uv.needsUpdate = true;
  return geo;
}

function makeBanner(text, w = 9, h = 2.2) {
  const c = document.createElement('canvas');
  c.width = 1024; c.height = 256;
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, 0, 256);
  g.addColorStop(0, '#ff5f8a'); g.addColorStop(1, '#ff2f6d');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 1024, 256);
  ctx.strokeStyle = 'rgba(255,255,255,.85)'; ctx.lineWidth = 12;
  ctx.strokeRect(16, 16, 992, 224);
  ctx.fillStyle = '#fff';
  ctx.font = 'bold 130px system-ui, sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(text, 512, 138);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  const m = new THREE.MeshStandardMaterial({ map: t, roughness: 0.7, side: THREE.DoubleSide, emissiveMap: t, emissive: 0xffffff, emissiveIntensity: 0.18 });
  return new THREE.Mesh(new THREE.PlaneGeometry(w, h), m);
}

function cloudIsland(s, mats) {
  const g = new THREE.Group();
  const rock = new THREE.Mesh(new THREE.ConeGeometry(s * 0.9, s * 1.7, 7, 1), mats.rock);
  rock.rotation.y = Math.random() * TAU;
  rock.position.y = -s * 0.85;
  rock.scale.y = 0.9 + Math.random() * 0.5;
  g.add(rock);
  const top = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.92, s * 0.88, s * 0.28, 9), mats.grass);
  g.add(top);
  for (let i = 0; i < 3; i++) {
    const p = new THREE.Mesh(new THREE.IcosahedronGeometry(s * (0.32 + Math.random() * 0.3), 1), mats.cloud);
    p.position.set((Math.random() - 0.5) * s * 2.6, s * (1.4 + Math.random()), (Math.random() - 0.5) * s * 2.6);
    g.add(p);
  }
  return g;
}

function crownMesh() {
  const g = new THREE.Group();
  const gold = new THREE.MeshPhysicalMaterial({
    color: 0xffd94a, roughness: 0.16, metalness: 1.0,
    emissive: 0xffb300, emissiveIntensity: 0.5, clearcoat: 1,
  });
  const band = new THREE.Mesh(new THREE.CylinderGeometry(0.95, 1.05, 0.6, 24, 1, true), gold);
  band.material.side = THREE.DoubleSide;
  g.add(band);
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * TAU;
    const sp = new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.75, 6), gold);
    sp.position.set(Math.cos(a) * 0.9, 0.62, Math.sin(a) * 0.9);
    g.add(sp);
    const ball = new THREE.Mesh(new THREE.SphereGeometry(0.15, 12, 10), gold);
    ball.position.set(Math.cos(a) * 0.9, 1.05, Math.sin(a) * 0.9);
    g.add(ball);
  }
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({
    map: glowTexture(), color: 0xffdd66, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false,
  }));
  glow.scale.setScalar(9);
  g.add(glow);
  return g;
}

let _glowTex = null;
export function glowTexture() {
  if (_glowTex) return _glowTex;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.28, 'rgba(255,255,255,.55)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128);
  _glowTex = new THREE.CanvasTexture(c);
  return _glowTex;
}

// ------------------------------------------------------------------ lava shader
function lavaMesh(r) {
  const mat = new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 } },
    fog: false,
    vertexShader: `varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `
      uniform float uTime; varying vec2 vP;
      float h(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
      float n(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
        return mix(mix(h(i),h(i+vec2(1,0)),f.x), mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x), f.y); }
      void main(){
        vec2 p = vP*0.055;
        float v = n(p + uTime*0.06) * 0.55 + n(p*2.3 - uTime*0.09) * 0.3 + n(p*5.1 + uTime*0.15)*0.15;
        vec3 col = mix(vec3(0.42,0.04,0.02), vec3(1.0,0.45,0.08), smoothstep(0.35,0.78,v));
        col = mix(col, vec3(1.0,0.92,0.5), smoothstep(0.72,0.92,v));
        float edge = smoothstep(1.0, 0.72, length(vP)/${r.toFixed(1)});
        gl_FragColor = vec4(col*(0.7+0.9*v), edge);
      }`,
    transparent: true,
    depthWrite: false,
  });
  const m = new THREE.Mesh(new THREE.CircleGeometry(r, 64), mat);
  m.rotation.x = -Math.PI / 2;
  m.userData.mat = mat;
  return m;
}

// ------------------------------------------------------------------
export class LevelView {
  constructor(scene, world, level) {
    this.scene = scene;
    this.world = world;
    this.level = level;
    this.mats = buildMaterials(level.theme.palette);
    this.root = new THREE.Group();
    this.dyn = [];
    this.animated = [];
    this.tileMeshes = [];
    this.tileAnim = null;
    scene.add(this.root);
    this.build();
  }

  matFor(vis) {
    const M = this.mats;
    if (vis.slick) return M.slick;
    switch (vis.mat) {
      case 'track': return vis.big ? M.trackAlt : M.track;
      case 'accent': return M.accent;
      case 'rail': return M.rail;
      case 'hazard': return vis.stripe || vis.log ? M.hazard : M.hazardPlain;
      case 'metal': return M.metal;
      case 'bounce': return M.bounce;
      case 'goal': return M.goal;
      case 'glass': return M.glass;
      case 'hexA': return M.hexA;
      case 'hexB': return M.hexB;
      case 'hexC': return M.hexC;
      default: return M.track;
    }
  }

  build() {
    const hexTiles = [];

    for (const c of this.world.colliders) {
      const vis = c.vis || { kind: 'box', mat: 'track' };
      if (vis.hex) { hexTiles.push(c); continue; }

      let geo, mesh;
      if (c.shape === 0) {
        const w = c.h.x * 2, h = c.h.y * 2, d = c.h.z * 2;
        const big = Math.max(w, d) > 8 && h < 2.2 && vis.mat === 'track';
        if (vis.log) {
          geo = new THREE.CylinderGeometry(c.h.y, c.h.y, c.h.x * 2, 20, 1);
          geo.rotateZ(Math.PI / 2);
          scaleUVs(geo, 5, 1);
        } else {
          const rad = Math.min(0.14, Math.min(w, h, d) * 0.24);
          geo = new RoundedBoxGeometry(w, h, d, 2, rad);
          if (vis.stripe) scaleUVs(geo, Math.max(1, w / 1.6), 1);
          else if (big) scaleUVs(geo, w / 4, d / 4);
        }
        mesh = new THREE.Mesh(geo, this.matFor({ ...vis, big }));
      } else if (c.shape === 1) {
        const seg = vis.seg || 24;
        geo = new THREE.CylinderGeometry(c.r, c.r, c.hy * 2, seg, 1);
        if (seg === 6) geo.rotateY(Math.PI / 6);
        mesh = new THREE.Mesh(geo, this.matFor(vis));
      } else {
        geo = new THREE.IcosahedronGeometry(c.r, 3);
        mesh = new THREE.Mesh(geo, this.matFor(vis));
      }

      mesh.castShadow = true;
      mesh.receiveShadow = true;
      mesh.position.set(c.p.x, c.p.y, c.p.z);
      mesh.rotation.order = 'YXZ';
      mesh.rotation.set(c.eu.x, c.eu.y, c.eu.z);
      this.root.add(mesh);
      if (c.dynamic) {
        this.dyn.push({ c, mesh, roll: vis.spinRoll || 0 });
        if (vis.spinRoll) mesh.userData.rollAxis = true;
      }
    }

    // ---------- hex tiles as instanced meshes ----------
    if (hexTiles.length) {
      const byLayer = new Map();
      for (const c of hexTiles) {
        const l = c.vis.layer || 0;
        if (!byLayer.has(l)) byLayer.set(l, []);
        byLayer.get(l).push(c);
      }
      this.tileAnim = [];
      for (const [layer, arr] of byLayer) {
        const g = new THREE.CylinderGeometry(arr[0].r, arr[0].r * 0.94, arr[0].hy * 2, 6, 1);
        g.rotateY(Math.PI / 6);
        const mat = this.matFor({ mat: 'hex' + 'ABC'[layer] }).clone();
        const im = new THREE.InstancedMesh(g, mat, arr.length);
        im.castShadow = true; im.receiveShadow = true;
        im.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        im.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(arr.length * 3).fill(1), 3);
        const dummy = new THREE.Object3D();
        arr.forEach((c, i) => {
          dummy.position.set(c.p.x, c.p.y, c.p.z);
          dummy.rotation.set(0, 0, 0);
          dummy.scale.set(1, 1, 1);
          dummy.updateMatrix();
          im.setMatrixAt(i, dummy.matrix);
          this.tileAnim.push({ c, im, i, base: { x: c.p.x, y: c.p.y, z: c.p.z }, spin: (Math.random() - 0.5) * 6, tipx: (Math.random() - 0.5) * 4, tipz: (Math.random() - 0.5) * 4 });
        });
        im.instanceMatrix.needsUpdate = true;
        this.root.add(im);
        this.tileMeshes.push(im);
      }
      this.tileById = new Map();
      for (const t of this.tileAnim) this.tileById.set(t.c.id, t);
    }

    // ---------- decor ----------
    for (const d of this.world.decor) {
      if (d.kind === 'cloudIsland') {
        const g = cloudIsland(d.s, this.mats);
        g.position.set(d.x, d.y, d.z);
        g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
        this.root.add(g);
      } else if (d.kind === 'banner') {
        const b = makeBanner(d.text);
        b.position.set(d.x, d.y, d.z);
        this.root.add(b);
        const b2 = makeBanner(d.text);
        b2.position.set(d.x, d.y, d.z - 0.05);
        b2.rotation.y = Math.PI;
        this.root.add(b2);
      } else if (d.kind === 'lava') {
        const m = lavaMesh(d.r);
        m.position.set(0, d.y, 0);
        this.root.add(m);
        this.lava = m;
      } else if (d.kind === 'crown') {
        this.crown = crownMesh();
        this.crown.position.set(d.x, d.y, d.z);
        this.root.add(this.crown);
      }
    }
  }

  /** Sync meshes with the (already stepped) physics world. */
  update(dt, time, tileTrig, tick, fadeTicks) {
    for (let i = 0; i < this.dyn.length; i++) {
      const { c, mesh, roll } = this.dyn[i];
      mesh.position.set(c.p.x, c.p.y, c.p.z);
      mesh.rotation.set(c.eu.x, c.eu.y, c.eu.z);
      if (roll) mesh.rotation.x = time * roll;   // rolling logs spin as they slide
      mesh.visible = !c.dead;
    }

    if (this.tileAnim && tileTrig) {
      const dummy = new THREE.Object3D();
      const touched = new Set();
      for (const t of this.tileAnim) {
        const idx = t.c.tileIndex;
        if (idx === undefined) continue;
        const trig = tileTrig[idx] | 0;
        if (!trig) continue;
        const age = (tick - trig) / 30;
        const fade = fadeTicks / 30;
        let dropped = 0, shake = 0;
        if (age < fade) {
          shake = Math.min(1, age / fade);
        } else {
          dropped = age - fade;
        }
        dummy.position.set(
          t.base.x + (Math.random() - 0.5) * shake * 0.05,
          t.base.y - (dropped > 0 ? 0.5 * 26 * dropped * dropped : 0),
          t.base.z + (Math.random() - 0.5) * shake * 0.05,
        );
        dummy.rotation.set(dropped * t.tipx * 0.5, dropped * t.spin * 0.4, dropped * t.tipz * 0.5);
        const s = dropped > 2.2 ? 0 : 1;
        dummy.scale.setScalar(s);
        dummy.updateMatrix();
        t.im.setMatrixAt(t.i, dummy.matrix);
        const warm = Math.min(1, shake);
        t.im.instanceColor.setXYZ(t.i, 1 + warm * 0.9, 1 - warm * 0.55, 1 - warm * 0.72);
        touched.add(t.im);
      }
      for (const im of touched) { im.instanceMatrix.needsUpdate = true; im.instanceColor.needsUpdate = true; }
    }

    if (this.lava) this.lava.userData.mat.uniforms.uTime.value = time;
    if (this.crown) {
      const cp = this.level.crownPos;
      this.crown.position.y = cp.y + Math.sin(time * cp.speed) * cp.bob;
      this.crown.rotation.y = time * 0.9;
    }
  }

  dispose() {
    this.root.traverse((o) => {
      if (o.isMesh || o.isInstancedMesh || o.isSprite) {
        o.geometry?.dispose();
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          if (!m) continue;
          if (m.map && m.map.isCanvasTexture) m.map.dispose();
          if (o.isInstancedMesh || o.isSprite) m.dispose();
        }
      }
      if (o.isInstancedMesh) o.dispose?.();
    });
    for (const k in this.mats) this.mats[k].dispose?.();
    this.scene.remove(this.root);
  }
}

import * as THREE from 'three';
import { glowTexture } from './levelMesh.js';

const MAX = 1400;

const VERT = /* glsl */`
  attribute float aSize;
  attribute float aLife;
  attribute vec3 aColor;
  varying vec3 vColor;
  varying float vLife;
  void main(){
    vColor = aColor; vLife = aLife;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_PointSize = aSize * (300.0 / max(1.0, -mv.z));
    gl_Position = projectionMatrix * mv;
  }
`;
const FRAG = /* glsl */`
  uniform sampler2D uMap;
  varying vec3 vColor;
  varying float vLife;
  void main(){
    if (vLife <= 0.0) discard;
    vec4 t = texture2D(uMap, gl_PointCoord);
    gl_FragColor = vec4(vColor, t.a * vLife);
  }
`;

export class FX {
  constructor(scene) {
    this.scene = scene;
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(MAX * 3);
    this.vel = new Float32Array(MAX * 3);
    this.col = new Float32Array(MAX * 3);
    this.size = new Float32Array(MAX);
    this.life = new Float32Array(MAX);
    this.maxLife = new Float32Array(MAX);
    this.grav = new Float32Array(MAX);
    this.drag = new Float32Array(MAX);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    g.setAttribute('aColor', new THREE.BufferAttribute(this.col, 3));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1));
    g.setAttribute('aLife', new THREE.BufferAttribute(this.life, 1));
    g.setDrawRange(0, MAX);
    this.geo = g;
    this.mat = new THREE.ShaderMaterial({
      uniforms: { uMap: { value: glowTexture() } },
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false, blending: THREE.NormalBlending, fog: false,
    });
    this.points = new THREE.Points(g, this.mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = 5;
    scene.add(this.points);
    this.cursor = 0;

    // expanding shock rings
    this.ringGeo = new THREE.RingGeometry(0.55, 0.78, 32);
    this.ringGeo.rotateX(-Math.PI / 2);
    this.rings = [];
    for (let i = 0; i < 12; i++) {
      const m = new THREE.Mesh(this.ringGeo, new THREE.MeshBasicMaterial({
        color: 0xffffff, transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide, fog: false,
      }));
      m.visible = false;
      scene.add(m);
      this.rings.push({ m, t: 0, dur: 0, scale: 1 });
    }
  }

  _spawn(x, y, z, vx, vy, vz, r, g, b, size, life, grav = -9, drag = 1.6) {
    const i = this.cursor;
    this.cursor = (this.cursor + 1) % MAX;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.col[i * 3] = r; this.col[i * 3 + 1] = g; this.col[i * 3 + 2] = b;
    this.size[i] = size;
    this.life[i] = 1;
    this.maxLife[i] = life;
    this.grav[i] = grav;
    this.drag[i] = drag;
  }

  burst(x, y, z, n, color, opts = {}) {
    const c = new THREE.Color(color);
    const spd = opts.speed ?? 3.2;
    const up = opts.up ?? 1.6;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const r = Math.random();
      this._spawn(
        x + (Math.random() - 0.5) * 0.4, y + Math.random() * 0.3, z + (Math.random() - 0.5) * 0.4,
        Math.cos(a) * spd * r, up * (0.35 + Math.random()), Math.sin(a) * spd * r,
        c.r, c.g, c.b,
        (opts.size ?? 0.5) * (0.6 + Math.random() * 0.8),
        (opts.life ?? 0.7) * (0.7 + Math.random() * 0.6),
        opts.grav ?? -9, opts.drag ?? 2.0,
      );
    }
  }

  dust(x, y, z, n = 6) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      this._spawn(
        x, y + 0.05, z,
        Math.cos(a) * (1 + Math.random() * 2), 0.6 + Math.random() * 1.2, Math.sin(a) * (1 + Math.random() * 2),
        0.95, 0.93, 0.88, 0.55 + Math.random() * 0.5, 0.45 + Math.random() * 0.3, -3.2, 3.4,
      );
    }
  }

  confetti(x, y, z, n = 240) {
    const cols = [0xff5f8a, 0x4fc3ff, 0xffc94a, 0x5ddb8a, 0xb07dff, 0xff8a4a, 0xffffff];
    for (let i = 0; i < n; i++) {
      const c = new THREE.Color(cols[(Math.random() * cols.length) | 0]);
      const a = Math.random() * Math.PI * 2;
      const s = 4 + Math.random() * 9;
      this._spawn(
        x + (Math.random() - 0.5) * 4, y + 2 + Math.random() * 3, z + (Math.random() - 0.5) * 4,
        Math.cos(a) * s * 0.6, 5 + Math.random() * 9, Math.sin(a) * s * 0.6,
        c.r, c.g, c.b, 0.55 + Math.random() * 0.6, 2.6 + Math.random() * 1.6, -7.5, 1.1,
      );
    }
  }

  ring(x, y, z, color, scale = 2.4, dur = 0.42) {
    const r = this.rings.find((q) => !q.m.visible) || this.rings[0];
    r.m.visible = true;
    r.m.position.set(x, y + 0.06, z);
    r.m.material.color.set(color);
    r.m.material.opacity = 0.85;
    r.m.scale.setScalar(0.35);
    r.t = 0; r.dur = dur; r.scale = scale;
  }

  update(dt) {
    const pos = this.pos, vel = this.vel, life = this.life;
    for (let i = 0; i < MAX; i++) {
      if (life[i] <= 0) continue;
      const d = Math.exp(-this.drag[i] * dt);
      vel[i * 3] *= d;
      vel[i * 3 + 1] = (vel[i * 3 + 1] + this.grav[i] * dt) * d;
      vel[i * 3 + 2] *= d;
      pos[i * 3] += vel[i * 3] * dt;
      pos[i * 3 + 1] += vel[i * 3 + 1] * dt;
      pos[i * 3 + 2] += vel[i * 3 + 2] * dt;
      life[i] -= dt / this.maxLife[i];
      if (life[i] < 0) life[i] = 0;
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.aLife.needsUpdate = true;
    this.geo.attributes.aColor.needsUpdate = true;
    this.geo.attributes.aSize.needsUpdate = true;

    for (const r of this.rings) {
      if (!r.m.visible) continue;
      r.t += dt;
      const k = r.t / r.dur;
      if (k >= 1) { r.m.visible = false; continue; }
      r.m.scale.setScalar(0.35 + k * r.scale);
      r.m.material.opacity = 0.85 * (1 - k) * (1 - k);
    }
  }
}

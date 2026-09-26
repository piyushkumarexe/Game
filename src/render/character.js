import * as THREE from 'three';
import * as K from '../../shared/constants.js';
import { glowTexture } from './levelMesh.js';

const TAU = Math.PI * 2;

// Shared geometry — one allocation for every bean in the match.
let G = null;
function geos() {
  if (G) return G;
  const R = K.P_RADIUS;
  G = {
    body: new THREE.CapsuleGeometry(R, K.P_HEIGHT - R * 2 - 0.26, 6, 20),
    limb: new THREE.CapsuleGeometry(0.125, 0.16, 4, 10),
    leg: new THREE.CapsuleGeometry(0.135, 0.1, 4, 10),
    foot: new THREE.SphereGeometry(0.17, 12, 9),
    eyeWhite: new THREE.SphereGeometry(0.125, 16, 12),
    pupil: new THREE.SphereGeometry(0.058, 12, 10),
    mouth: new THREE.SphereGeometry(0.075, 14, 10),
  };
  return G;
}

const SKIN = new THREE.MeshPhysicalMaterial({
  color: 0xffffff, roughness: 0.34, metalness: 0.0,
  clearcoat: 0.9, clearcoatRoughness: 0.2, sheen: 0.4, sheenRoughness: 0.6,
});
const EYE_W = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.12, clearcoat: 1 });
const EYE_P = new THREE.MeshPhysicalMaterial({ color: 0x1b1f2a, roughness: 0.08, clearcoat: 1 });
const MOUTH = new THREE.MeshPhysicalMaterial({ color: 0x2a1f2b, roughness: 0.35 });

function nameSprite(name, color, isYou) {
  const c = document.createElement('canvas');
  c.width = 512; c.height = 128;
  const ctx = c.getContext('2d');
  const hex = '#' + color.toString(16).padStart(6, '0');
  ctx.font = 'bold 62px system-ui, -apple-system, sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const w = Math.min(470, ctx.measureText(name).width + 60);
  ctx.fillStyle = 'rgba(12,14,22,.62)';
  roundRect(ctx, 256 - w / 2, 26, w, 74, 34); ctx.fill();
  ctx.strokeStyle = isYou ? '#ffffff' : hex;
  ctx.lineWidth = isYou ? 7 : 5;
  roundRect(ctx, 256 - w / 2, 26, w, 74, 34); ctx.stroke();
  ctx.fillStyle = '#fff';
  ctx.fillText(name, 256, 66);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, depthTest: true, depthWrite: false, sizeAttenuation: true, fog: false }));
  s.scale.set(2.1, 0.52, 1);
  return s;
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

export class Bean {
  constructor(scene, name, color, isYou) {
    const g = geos();
    this.color = color;
    this.root = new THREE.Group();

    // tilt/squash container so animation never fights networked position
    this.body = new THREE.Group();
    this.root.add(this.body);

    this.skin = SKIN.clone();
    this.skin.color.setHex(color);
    this.skin.sheenColor = new THREE.Color(color).lerp(new THREE.Color(0xffffff), 0.6);

    const bodyY = K.P_HEIGHT - (K.P_HEIGHT - K.P_RADIUS * 2 - 0.26) / 2 - K.P_RADIUS;
    this.torso = new THREE.Mesh(g.body, this.skin);
    this.torso.position.y = bodyY;
    this.torso.castShadow = true;
    this.torso.receiveShadow = true;
    this.body.add(this.torso);

    // eyes
    this.eyes = new THREE.Group();
    this.eyes.position.set(0, bodyY + 0.3, 0);
    for (let i = 0; i < 2; i++) {
      const s = i ? 1 : -1;
      const w = new THREE.Mesh(g.eyeWhite, EYE_W);
      w.position.set(s * 0.155, 0, K.P_RADIUS * 0.84);
      w.scale.set(1, 1.1, 0.92);
      this.eyes.add(w);
      const p = new THREE.Mesh(g.pupil, EYE_P);
      p.position.set(s * 0.152, -0.008, K.P_RADIUS * 0.84 + 0.074);
      this.eyes.add(p);
    }
    this.body.add(this.eyes);

    // mouth
    this.mouth = new THREE.Mesh(g.mouth, MOUTH);
    this.mouth.position.set(0, bodyY + 0.075, K.P_RADIUS * 0.93);
    this.mouth.scale.set(1.5, 0.62, 0.5);
    this.body.add(this.mouth);

    // arms
    this.arms = [];
    for (let i = 0; i < 2; i++) {
      const s = i ? 1 : -1;
      const pivot = new THREE.Group();
      pivot.position.set(s * (K.P_RADIUS - 0.02), bodyY + 0.05, 0);
      const m = new THREE.Mesh(g.limb, this.skin);
      m.position.y = -0.2;
      m.castShadow = true;
      pivot.add(m);
      this.body.add(pivot);
      this.arms.push(pivot);
    }

    // legs
    this.legs = [];
    for (let i = 0; i < 2; i++) {
      const s = i ? 1 : -1;
      const pivot = new THREE.Group();
      pivot.position.set(s * 0.17, 0.34, 0);
      const m = new THREE.Mesh(g.leg, this.skin);
      m.position.y = -0.14;
      m.castShadow = true;
      pivot.add(m);
      const f = new THREE.Mesh(g.foot, this.skin);
      f.position.set(0, -0.26, 0.05);
      f.scale.set(1, 0.68, 1.25);
      pivot.add(f);
      this.body.add(pivot);
      this.legs.push(pivot);
    }

    this.tag = nameSprite(name, color, isYou);
    this.tag.position.y = K.P_HEIGHT + 0.52;
    this.root.add(this.tag);

    // soft contact blob for grounding on low quality / far distance
    this.blob = new THREE.Sprite(new THREE.SpriteMaterial({
      map: glowTexture(), color: 0x000000, transparent: true, opacity: 0.22, depthWrite: false, fog: false,
    }));
    this.blob.scale.setScalar(1.5);
    this.blob.material.rotation = 0;
    this.root.add(this.blob);

    scene.add(this.root);

    this.phase = Math.random() * TAU;
    this.squash = 1;
    this.squashV = 0;
    this.tilt = 0;
    this.rollA = 0;
    this.blink = 2 + Math.random() * 3;
    this.prevY = 0;
    this.emote = 0;
  }

  setName(name, isYou) {
    this.root.remove(this.tag);
    this.tag.material.map.dispose();
    this.tag.material.dispose();
    this.tag = nameSprite(name, this.color, isYou);
    this.tag.position.y = K.P_HEIGHT + 0.52;
    this.root.add(this.tag);
  }

  pop(strength = 1) { this.squashV -= strength * 7; }

  /**
   * @param st {x,y,z,yaw,grounded,dive,tumble,getUp,speed,status}
   */
  update(dt, st, camPos) {
    const r = this.root;
    r.position.set(st.x, st.y, st.z);
    this.body.rotation.set(0, st.yaw, 0);

    const speed = st.speed || 0;
    const moving = speed > 0.6 && st.grounded;
    this.phase += dt * (moving ? 3.0 + speed * 1.55 : 2.2);

    // ---- squash & stretch ----
    const targetSquash = 1;
    this.squashV += (targetSquash - this.squash) * 90 * dt;
    this.squashV *= Math.exp(-11 * dt);
    this.squash += this.squashV * dt;
    this.squash = Math.max(0.55, Math.min(1.5, this.squash));

    let sy = this.squash;
    if (!st.grounded) sy *= 1 + Math.max(-0.16, Math.min(0.16, (st.vy || 0) * 0.014));
    const sxz = 1 / Math.sqrt(Math.max(0.2, sy));
    this.body.scale.set(sxz, sy, sxz);

    // ---- pose ----
    if (st.tumble) {
      this.rollA += dt * 9;
      this.body.rotation.x = Math.sin(this.rollA) * 0.5 + 1.15;
      this.body.rotation.z = Math.cos(this.rollA * 0.8) * 0.55;
      this.arms[0].rotation.x = -2.2; this.arms[1].rotation.x = -2.2;
      this.arms[0].rotation.z = 0.7; this.arms[1].rotation.z = -0.7;
      this.legs[0].rotation.x = 0.9; this.legs[1].rotation.x = 1.3;
    } else if (st.dive) {
      this.body.rotation.x = 1.32;
      this.body.rotation.z *= 0.8;
      this.body.position.y = 0.16;
      this.arms[0].rotation.x = -2.5; this.arms[1].rotation.x = -2.5;
      this.arms[0].rotation.z = 0.25; this.arms[1].rotation.z = -0.25;
      this.legs[0].rotation.x = 0.25; this.legs[1].rotation.x = 0.25;
      this.rollA = 0;
    } else if (st.getUp) {
      const k = 1 - st.getUp;
      this.body.rotation.x = 1.3 * (1 - k);
      this.body.position.y = 0.16 * (1 - k);
      this.arms[0].rotation.x = -1.2 * (1 - k); this.arms[1].rotation.x = -1.2 * (1 - k);
      this.legs[0].rotation.x = 0; this.legs[1].rotation.x = 0;
      this.arms[0].rotation.z = 0; this.arms[1].rotation.z = 0;
      this.rollA = 0;
    } else {
      this.body.position.y = 0;
      this.body.rotation.z = 0;
      this.rollA = 0;
      if (st.grounded) {
        const s = Math.sin(this.phase);
        const c = Math.cos(this.phase);
        const amp = moving ? Math.min(1, speed / K.RUN_SPEED) : 0;
        this.legs[0].rotation.x = s * 0.95 * amp;
        this.legs[1].rotation.x = -s * 0.95 * amp;
        this.arms[0].rotation.x = -s * 0.8 * amp;
        this.arms[1].rotation.x = s * 0.8 * amp;
        this.arms[0].rotation.z = 0.12 + amp * 0.1;
        this.arms[1].rotation.z = -0.12 - amp * 0.1;
        this.body.rotation.x = amp * 0.2 + Math.abs(c) * 0.03 * amp;
        this.torso.position.y = (K.P_HEIGHT - (K.P_HEIGHT - K.P_RADIUS * 2 - 0.26) / 2 - K.P_RADIUS)
          + (moving ? Math.abs(s) * 0.045 : Math.sin(this.phase * 0.5) * 0.018);
      } else {
        const up = (st.vy || 0) > 0;
        this.legs[0].rotation.x = up ? -0.55 : 0.4;
        this.legs[1].rotation.x = up ? -0.3 : 0.55;
        this.arms[0].rotation.x = up ? -2.0 : -0.5;
        this.arms[1].rotation.x = up ? -2.0 : -0.5;
        this.arms[0].rotation.z = 0.35; this.arms[1].rotation.z = -0.35;
        this.body.rotation.x = up ? -0.12 : 0.18;
      }
    }

    if (this.emote > 0) {
      this.emote -= dt;
      const w = Math.sin(this.emote * 22);
      this.arms[0].rotation.x = -2.6 + w * 0.4;
      this.arms[1].rotation.x = -2.6 - w * 0.4;
      this.body.rotation.z = w * 0.12;
    }

    // ---- blink ----
    this.blink -= dt;
    let eyeScale = 1;
    if (this.blink < 0.12) eyeScale = Math.max(0.08, Math.abs(this.blink) / 0.06);
    if (this.blink < 0) this.blink = 2.4 + Math.random() * 3.4;
    this.eyes.scale.y = eyeScale;

    // ---- look at the camera a little (charm) ----
    if (camPos) {
      const dx = camPos.x - st.x, dz = camPos.z - st.z;
      const a = Math.atan2(dx, dz) - st.yaw;
      const la = Math.atan2(Math.sin(a), Math.cos(a));
      this.eyes.rotation.y = Math.max(-0.5, Math.min(0.5, la * 0.35));
    }

    // ---- contact blob ----
    this.blob.position.set(0, 0.04, 0);
    this.blob.material.opacity = st.grounded ? 0.24 : 0;

    this.tag.visible = st.showTag !== false;
  }

  dispose(scene) {
    scene.remove(this.root);
    this.skin.dispose();
    this.tag.material.map.dispose();
    this.tag.material.dispose();
  }
}

import * as THREE from 'three';

/** A subtle procedural roughness/normal detail so big flat surfaces aren't plastic-dead. */
function noiseTexture(size = 256, strength = 0.5) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < size * size; i++) {
    const n = 128 + (Math.random() - 0.5) * 255 * strength;
    img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = n;
    img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

/** Diagonal hazard stripes — instantly readable as "this will hurt". */
function stripeTexture(a = '#ff5a4e', b = '#ffffff') {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const ctx = c.getContext('2d');
  ctx.fillStyle = a; ctx.fillRect(0, 0, 128, 128);
  ctx.strokeStyle = b; ctx.lineWidth = 22;
  for (let i = -128; i < 256; i += 44) {
    ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i + 128, 128); ctx.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function checkerTexture(a = '#ffffff', b = '#e6ebf3') {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const ctx = c.getContext('2d');
  ctx.fillStyle = a; ctx.fillRect(0, 0, 128, 128);
  ctx.fillStyle = b;
  ctx.fillRect(0, 0, 64, 64); ctx.fillRect(64, 64, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

let shared = null;
export function sharedTextures() {
  if (!shared) {
    shared = {
      rough: noiseTexture(256, 0.55),
      stripe: stripeTexture(),
      checker: checkerTexture(),
    };
    shared.rough.repeat.set(8, 8);
  }
  return shared;
}

/**
 * Build the material set for a level palette.
 * Everything is physically based so the sky IBL actually does work.
 */
export function buildMaterials(palette) {
  const tex = sharedTextures();
  const M = {};

  M.track = new THREE.MeshStandardMaterial({
    color: palette.track, roughness: 0.62, metalness: 0.02,
    roughnessMap: tex.rough,
  });
  M.trackAlt = new THREE.MeshStandardMaterial({
    color: palette.track, roughness: 0.5, metalness: 0.02,
    map: tex.checker,
  });
  M.accent = new THREE.MeshPhysicalMaterial({
    color: palette.accent, roughness: 0.34, metalness: 0.0,
    clearcoat: 0.85, clearcoatRoughness: 0.22,
  });
  M.rail = new THREE.MeshPhysicalMaterial({
    color: palette.rail, roughness: 0.38, metalness: 0.12, clearcoat: 0.6,
  });
  M.hazard = new THREE.MeshPhysicalMaterial({
    color: 0xffffff, roughness: 0.42, metalness: 0.05,
    map: tex.stripe, clearcoat: 0.5, emissive: new THREE.Color(palette.hazard), emissiveIntensity: 0.12,
  });
  M.hazardPlain = new THREE.MeshPhysicalMaterial({
    color: palette.hazard, roughness: 0.4, metalness: 0.05, clearcoat: 0.6,
  });
  M.metal = new THREE.MeshStandardMaterial({
    color: palette.metal, roughness: 0.3, metalness: 0.88, roughnessMap: tex.rough,
  });
  M.bounce = new THREE.MeshPhysicalMaterial({
    color: palette.bounce, roughness: 0.28, metalness: 0.0,
    clearcoat: 1.0, clearcoatRoughness: 0.08,
    emissive: new THREE.Color(palette.bounce), emissiveIntensity: 0.55,
  });
  M.goal = new THREE.MeshPhysicalMaterial({
    color: palette.goal, roughness: 0.22, metalness: 0.35,
    clearcoat: 1.0, emissive: new THREE.Color(palette.goal), emissiveIntensity: 0.4,
  });
  M.glass = new THREE.MeshPhysicalMaterial({
    color: palette.glass, roughness: 0.12, metalness: 0.0,
    transmission: 0.0, clearcoat: 1.0, clearcoatRoughness: 0.05,
    emissive: new THREE.Color(palette.glass), emissiveIntensity: 0.16,
  });
  M.slick = new THREE.MeshPhysicalMaterial({
    color: palette.glass, roughness: 0.04, metalness: 0.1, clearcoat: 1.0,
    emissive: new THREE.Color(palette.glass), emissiveIntensity: 0.22,
  });

  // hex layers get distinct hues so depth reads instantly
  const hexCols = [0x7fe4ff, 0xffd166, 0xff7a9c];
  for (let i = 0; i < 3; i++) {
    M['hex' + 'ABC'[i]] = new THREE.MeshPhysicalMaterial({
      color: hexCols[i], roughness: 0.34, metalness: 0.0,
      clearcoat: 0.9, clearcoatRoughness: 0.18,
      emissive: new THREE.Color(hexCols[i]), emissiveIntensity: 0.1,
    });
  }

  M.cloud = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95, metalness: 0 });
  M.rock = new THREE.MeshStandardMaterial({ color: 0x9aa7b8, roughness: 0.9, metalness: 0.02, roughnessMap: tex.rough });
  M.grass = new THREE.MeshStandardMaterial({ color: 0x6fd36f, roughness: 0.85, metalness: 0 });
  M.lava = new THREE.MeshBasicMaterial({ color: 0xff5a2a, fog: false });

  return M;
}

import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';

// ------------------------------------------------------------------ grade pass
const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uVignette: { value: 0.42 },
    uSat: { value: 1.1 },
    uContrast: { value: 1.045 },
    uFlash: { value: 0.0 },
    uFlashColor: { value: new THREE.Color(1, 1, 1) },
    uChroma: { value: 0.0012 },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }
  `,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse;
    uniform float uVignette, uSat, uContrast, uFlash, uChroma;
    uniform vec3 uFlashColor;
    varying vec2 vUv;
    void main(){
      vec2 d = vUv - 0.5;
      float r2 = dot(d,d);
      vec2 off = d * uChroma * (1.0 + r2 * 3.0);
      vec3 c;
      c.r = texture2D(tDiffuse, vUv + off).r;
      c.g = texture2D(tDiffuse, vUv).g;
      c.b = texture2D(tDiffuse, vUv - off).b;

      float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
      c = mix(vec3(l), c, uSat);
      c = (c - 0.5) * uContrast + 0.5;
      float v = smoothstep(0.92, 0.18, r2 * uVignette * 2.6);
      c *= mix(0.72, 1.0, v);
      c = mix(c, uFlashColor, uFlash);
      gl_FragColor = vec4(max(c, 0.0), 1.0);
    }
  `,
};

export function detectQuality() {
  const mob = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
  const cores = navigator.hardwareConcurrency || 4;
  const mem = navigator.deviceMemory || 4;
  if (mob && (cores <= 4 || mem <= 3)) return 'low';
  if (mob) return 'medium';
  if (cores <= 4 || mem <= 4) return 'medium';
  return 'high';
}

const QUALITY = {
  low:    { dpr: 1.0,  shadow: 1024, bloom: false, smaa: false, shadowDist: 32, softShadow: false },
  medium: { dpr: 1.35, shadow: 2048, bloom: true,  smaa: false, shadowDist: 44, softShadow: true },
  high:   { dpr: 1.85, shadow: 4096, bloom: true,  smaa: true,  shadowDist: 58, softShadow: true },
};

export class Renderer3D {
  constructor(canvas, quality = 'high') {
    this.quality = quality;
    this.q = QUALITY[quality] || QUALITY.high;

    this.renderer = new THREE.WebGLRenderer({
      canvas, antialias: !this.q.smaa, powerPreference: 'high-performance',
      stencil: false, alpha: false,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, this.q.dpr));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.06;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = this.q.softShadow ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(58, 1, 0.25, 1200);
    this.camera.position.set(0, 12, -20);

    // ---- sky + image based lighting ----
    this.sky = new Sky();
    this.sky.scale.setScalar(6000);
    this.scene.add(this.sky);
    this.sunDir = new THREE.Vector3();
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.pmrem.compileEquirectangularShader();

    // ---- lights ----
    this.sun = new THREE.DirectionalLight(0xffffff, 3.1);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(this.q.shadow, this.q.shadow);
    this.sun.shadow.bias = -0.0009;
    this.sun.shadow.normalBias = 0.035;
    this.sun.shadow.camera.near = 0.5;
    this.sun.shadow.camera.far = 220;
    this.scene.add(this.sun);
    this.scene.add(this.sun.target);

    this.hemi = new THREE.HemisphereLight(0xbcd8ff, 0x55504a, 0.75);
    this.scene.add(this.hemi);
    this.rim = new THREE.DirectionalLight(0xffd8b0, 0.55);
    this.rim.position.set(-1, 0.6, -1);
    this.scene.add(this.rim);

    // ---- post ----
    this.composer = new EffectComposer(this.renderer);
    this.renderPass = new RenderPass(this.scene, this.camera);
    this.composer.addPass(this.renderPass);

    if (this.q.bloom) {
      this.bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.42, 0.72, 0.86);
      this.composer.addPass(this.bloom);
    }
    this.composer.addPass(new OutputPass());
    this.grade = new ShaderPass(GradeShader);   // after tone-mapping: grade display colour
    this.composer.addPass(this.grade);
    if (this.q.smaa) this.composer.addPass(new SMAAPass());

    this.shake = 0;
    this.flash = 0;
    this._tmp = new THREE.Vector3();
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h, false);
    this.composer.setSize(w, h);
  }

  /** Apply a level theme: sky params, fog, sun angle, env map. */
  applyTheme(theme) {
    const u = this.sky.material.uniforms;
    u.turbidity.value = theme.turbidity;
    u.rayleigh.value = theme.rayleigh;
    u.mieCoefficient.value = 0.0045;
    u.mieDirectionalG.value = 0.82;

    const phi = THREE.MathUtils.degToRad(90 - theme.sun[0] * 90);
    const theta = THREE.MathUtils.degToRad(theme.sun[1] * 360 - 180);
    this.sunDir.setFromSphericalCoords(1, phi, theta);
    u.sunPosition.value.copy(this.sunDir);

    this.sun.position.copy(this.sunDir).multiplyScalar(90);
    this.sun.color.setHex(0xfff2e0);
    this.sun.intensity = 3.2;

    this.scene.fog = new THREE.Fog(theme.fog, theme.fogNear, theme.fogFar);
    this.hemi.color.setHex(theme.sky);
    this.hemi.groundColor.setHex(0x4a4640);

    if (this.envRT) this.envRT.dispose();
    const prevFog = this.scene.fog; this.scene.fog = null;
    this.envRT = this.pmrem.fromScene(this.sky, 0.02);
    this.scene.fog = prevFog;
    this.scene.environment = this.envRT.texture;
    this.scene.environmentIntensity = 0.85;
  }

  /**
   * Keep the shadow frustum tight around the action. The centre is snapped to shadow-map
   * texel increments so edges don't crawl and shimmer while the camera glides.
   */
  focusShadow(x, y, z) {
    const d = this.q.shadowDist;
    const cam = this.sun.shadow.camera;
    if (cam.right !== d) {
      cam.left = -d; cam.right = d; cam.top = d; cam.bottom = -d;
      cam.updateProjectionMatrix();
    }
    const texel = (d * 2) / this.q.shadow;
    const sx = Math.round(x / texel) * texel;
    const sy = Math.round(y / texel) * texel;
    const sz = Math.round(z / texel) * texel;
    this.sun.target.position.set(sx, sy, sz);
    this.sun.target.updateMatrixWorld();
    this.sun.position.set(sx + this.sunDir.x * 90, sy + this.sunDir.y * 90, sz + this.sunDir.z * 90);
  }

  addShake(amount) { this.shake = Math.min(1.4, this.shake + amount); }
  addFlash(amount, color = 0xffffff) {
    this.flash = Math.min(0.75, this.flash + amount);
    this.grade.uniforms.uFlashColor.value.setHex(color);
  }

  render(dt) {
    if (this.shake > 0.0005) {
      const s = this.shake * this.shake;
      this.camera.position.x += (Math.random() - 0.5) * s * 0.9;
      this.camera.position.y += (Math.random() - 0.5) * s * 0.9;
      this.camera.rotateZ((Math.random() - 0.5) * s * 0.05);
      this.shake *= Math.exp(-7 * dt);
    } else this.shake = 0;

    this.flash *= Math.exp(-6.5 * dt);
    this.grade.uniforms.uFlash.value = this.flash;
    this.composer.render(dt);
  }
}

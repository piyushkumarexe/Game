import * as THREE from 'three';
import './ui/styles.css';

import * as K from '../shared/constants.js';
import { World } from '../shared/world.js';
import { getLevel } from '../shared/levels.js';
import { makePlayer, stepPlayer, emptyInput, ST_ALIVE, ST_RESPAWN, ST_QUALIFIED, ST_OUT } from '../shared/sim.js';
import { clamp, dampAngle } from '../shared/math.js';

import { Renderer3D, detectQuality } from './render/scene.js';
import { LevelView } from './render/levelMesh.js';
import { Bean } from './render/character.js';
import { FX } from './render/fx.js';
import { Net } from './net.js';
import { Input } from './input.js';
import { HUD } from './ui/hud.js';
import { Audio } from './audio.js';

const COLORS = [
  0xff5f8a, 0x4fc3ff, 0xffc94a, 0x5ddb8a, 0xb07dff, 0xff8a4a,
  0x44e0d0, 0xff6be0, 0x8fd14f, 0x6d8bff, 0xffa3c4, 0xd6e14f,
];

const canvas = document.getElementById('c');
const hud = new HUD();
const audio = new Audio();
const quality = detectQuality();
const r3d = new Renderer3D(canvas, quality);
const fx = new FX(r3d.scene);
const input = new Input(canvas, document.getElementById('hud'));
const net = new Net();

// ------------------------------------------------------------------ state
let world = null;
let view = null;
let level = null;
let levelId = null;

const self = makePlayer(0, 'you', 0xffffff);
let selfReady = false;
const history = [];
let inputSeq = 0;
let predictTick = 0;
let interpClock = 0;
const beans = new Map();

const renderOffset = new THREE.Vector3();
const camTarget = new THREE.Vector3(0, 2, 0);
const camPos = new THREE.Vector3(0, 14, -22);
let camDist = 8.2;
let started = false;
let lastPhase = -1;
let introShown = -1;
let goShown = -1;

// ------------------------------------------------------------------ menu
const nameInput = document.getElementById('name-input');
const colorsEl = document.getElementById('colors');
let colorIdx = Math.floor(Math.random() * COLORS.length);

nameInput.value = localStorage.getItem('tr_name') || '';
const savedColor = Number(localStorage.getItem('tr_color'));
if (Number.isFinite(savedColor) && savedColor >= 0 && savedColor < COLORS.length) colorIdx = savedColor;

COLORS.forEach((c, i) => {
  const b = document.createElement('button');
  b.className = 'swatch' + (i === colorIdx ? ' sel' : '');
  b.style.background = '#' + c.toString(16).padStart(6, '0');
  b.onclick = () => {
    colorIdx = i;
    audio.resume(); audio.click();
    [...colorsEl.children].forEach((e, j) => e.classList.toggle('sel', j === i));
    localStorage.setItem('tr_color', String(i));
  };
  colorsEl.appendChild(b);
});

const playBtn = document.getElementById('play-btn');
playBtn.onclick = () => {
  audio.resume(); audio.click();
  const name = (nameInput.value || '').trim() || randomName();
  localStorage.setItem('tr_name', name);
  playBtn.disabled = true;
  playBtn.textContent = 'JOINING…';
  net.connect(name, colorIdx);
};
nameInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') playBtn.click(); });

const inviteBtn = document.getElementById('invite-btn');
inviteBtn.onclick = async () => {
  audio.resume(); audio.click();
  const url = location.origin + location.pathname;
  try {
    if (navigator.share && /Mobi/i.test(navigator.userAgent)) {
      await navigator.share({ title: 'Tumble Royale', text: 'Come tumble with me!', url });
    } else {
      await navigator.clipboard.writeText(url);
    }
    inviteBtn.textContent = '✅ LINK COPIED — SEND IT TO FRIENDS';
    inviteBtn.classList.add('done');
  } catch {
    inviteBtn.textContent = url;
  }
  setTimeout(() => { inviteBtn.textContent = '🔗 COPY INVITE LINK'; inviteBtn.classList.remove('done'); }, 3200);
};

document.getElementById('emote-btn').onclick = () => {
  audio.resume(); audio.emote();
  net.send({ t: 'emote', k: 0 });
};

function randomName() {
  const a = ['Wobbly', 'Zesty', 'Turbo', 'Sneaky', 'Jelly', 'Chunky', 'Swift', 'Cosmic', 'Bouncy', 'Mighty'];
  const b = ['Bean', 'Noodle', 'Pickle', 'Comet', 'Muffin', 'Rocket', 'Pebble', 'Mango', 'Tofu', 'Nugget'];
  return a[(Math.random() * a.length) | 0] + b[(Math.random() * b.length) | 0];
}

// ------------------------------------------------------------------ net wiring
net.addEventListener('welcome', () => {
  started = true;
  hud.hideMenu();
  hud.show();
  hud.setConn('connected', 'ok');
  self.id = net.selfId;
  loadLevel(net.levelId, true);
  predictTick = net.serverTick + net.lead;
  interpClock = net.serverTick - 4;
});

net.addEventListener('level', (e) => loadLevel(e.detail.id, true));

net.addEventListener('phase', () => {
  const ph = net.phase;
  if (ph === K.STATE_ROUND_END) {
    hud.clearBig();
    hud.showResults(net.results, net.selfId);
    const you = (net.results?.qualified || []).some((p) => p.id === net.selfId);
    if (you) { audio.qualify(); fx.confetti(self.x, self.y, self.z, 140); }
    else if ((net.results?.out || []).some((p) => p.id === net.selfId)) audio.out();
  } else if (ph === K.STATE_MATCH_END) {
    hud.hideResults();
    const w = net.roster.get(net.winner);
    hud.showWinner(w ? w.name : 'Nobody', net.winner === net.selfId, w?.color);
    audio.win();
    const t = w && beans.get(w.id) ? beans.get(w.id).root.position : { x: self.x, y: self.y, z: self.z };
    fx.confetti(t.x, t.y, t.z, 420);
    r3d.addFlash(0.3, 0xffe9a8);
  } else {
    hud.hideResults();
    hud.hideWinner();
  }
  lastPhase = ph;
});

net.addEventListener('disconnected', () => {
  hud.setConn('disconnected — reload to rejoin', 'err');
  hud.showMenu();
  playBtn.disabled = false;
  playBtn.textContent = 'RECONNECT';
  started = false;
});

net.addEventListener('full', () => {
  hud.setConn('server full — try again shortly', 'err');
  playBtn.disabled = false;
  playBtn.textContent = 'RETRY';
});

// ------------------------------------------------------------------ level
function loadLevel(id, resetSelf) {
  if (id === levelId && world) return;
  levelId = id;
  level = getLevel(id);
  if (!level) return;
  if (view) view.dispose();
  world = new World(level);
  world.setTime(0);
  view = new LevelView(r3d.scene, world, level);
  r3d.applyTheme(level.theme);
  hud.setRound(net.roundIdx, net.roundTotal, level.name);
  introShown = -1;
  goShown = -1;
  history.length = 0;
  if (resetSelf) {
    const sp = world.spawns[0] || { x: 0, y: 3, z: 0 };
    self.x = sp.x; self.y = sp.y; self.z = sp.z;
    self.vx = self.vy = self.vz = 0;
    self.grounded = false; self.groundId = -1;
    camPos.set(sp.x + (level.camera?.start[0] || 0), sp.y + 8, sp.z - 14);
  }
}

// ------------------------------------------------------------------ prediction
function buildInput() {
  const { mx, my, jump, dive } = input.consume();
  const cy = input.camYaw;
  const fx_ = Math.sin(cy), fz_ = Math.cos(cy);
  const rx = Math.cos(cy), rz = -Math.sin(cy);
  const fwd = -my;
  const inp = emptyInput();
  inp.mx = fx_ * fwd + rx * mx;
  inp.mz = fz_ * fwd + rz * mx;
  const l = Math.hypot(inp.mx, inp.mz);
  if (l > 1) { inp.mx /= l; inp.mz /= l; }
  inp.jump = jump;
  inp.dive = dive;
  inp.yaw = cy;
  return inp;
}

function worldTimeFor(tick) { return (tick - net.roundStartTick) * K.DT; }

function frozenNow() {
  // Server freezes players during round intro + results. Mirror it or prediction fights the server.
  if (net.phase === K.STATE_ROUND_END || net.phase === K.STATE_MATCH_END) return true;
  if (net.phase === K.STATE_PLAYING) {
    const introTicks = Math.round((K.ROUND_INTRO_MS / 1000) * K.TICK_HZ);
    return predictTick < net.roundStartTick + introTicks;
  }
  return false;
}

function doTick() {
  if (!world) return;
  predictTick++;
  const inp = buildInput();
  const frozen = frozenNow();
  const used = frozen ? emptyInput() : inp;
  if (frozen) used.yaw = inp.yaw;

  world.setTime(worldTimeFor(predictTick));
  stepPlayer(self, used, world, clientEv);
  pushRemotesAway();

  history.push({ seq: inputSeq, tick: predictTick, inp: { ...used } });
  if (history.length > 80) history.shift();
  net.sendInput(inputSeq, inp);
  inputSeq++;
}

/**
 * Predict body-to-body shoving against the interpolated remotes. Mirrors the server's
 * resolvePlayerCollisions for the local half of each pair, which keeps the reconciliation
 * error small when the arena gets crowded.
 */
function pushRemotesAway() {
  const rr = K.P_RADIUS * 2;
  for (const [id, b] of beans) {
    if (id === net.selfId || !b.root.visible) continue;
    const p = b.lastState;
    if (!p) continue;
    const dy = self.y - p.y;
    if (dy > K.P_HEIGHT || dy < -K.P_HEIGHT) continue;
    const dx = self.x - p.x, dz = self.z - p.z;
    const d2 = dx * dx + dz * dz;
    if (d2 > rr * rr || d2 < 1e-6) continue;
    const d = Math.sqrt(d2);
    const nx = dx / d, nz = dz / d;
    self.x += nx * (rr - d) * 0.5;
    self.z += nz * (rr - d) * 0.5;
    const rel = (self.vx - (p.vx || 0)) * nx + (self.vz - (p.vz || 0)) * nz;
    if (rel < 0) {
      const imp = -rel * 0.5 + K.PUSH_STRENGTH * K.DT * 0.5;
      self.vx += nx * imp;
      self.vz += nz * imp;
    }
  }
}

function reconcile() {
  const s = net.pendingSelf;
  if (!s) return;
  net.pendingSelf = null;
  const [seq, x, y, z, vx, vy, vz, yaw, grounded, groundId, dive, diveT, tumble, getUp, coyote, jumpBuf, diveCd, status, respawnT, checkpoint] = s;

  self.status = status;
  self.respawnT = respawnT;
  self.checkpoint = checkpoint;

  let hi = -1;
  for (let i = 0; i < history.length; i++) if (history[i].seq === seq) { hi = i; break; }

  const err = Math.hypot(self.x - x, self.y - y, self.z - z);
  const needSnap = hi === -1 || err > 3.5 || status !== ST_ALIVE;

  if (!needSnap && err < 0.06) {
    if (hi >= 0) history.splice(0, hi + 1);
    return;
  }

  const preX = self.x, preY = self.y, preZ = self.z;

  // rewind to the authoritative state, then replay everything the server hasn't seen yet
  self.x = x; self.y = y; self.z = z;
  self.vx = vx; self.vy = vy; self.vz = vz;
  self.yaw = yaw;
  self.grounded = !!grounded; self.groundId = groundId;
  self.dive = dive; self.diveT = diveT; self.tumble = tumble; self.getUp = getUp;
  self.coyote = coyote; self.jumpBuf = jumpBuf; self.diveCd = diveCd;

  const replay = hi >= 0 ? history.slice(hi + 1) : [];
  for (const h of replay) {
    world.setTime(worldTimeFor(h.tick));
    stepPlayer(self, h.inp, world, null);
  }
  world.setTime(worldTimeFor(predictTick));
  if (hi >= 0) history.splice(0, hi + 1);
  else history.length = 0;

  // Keep the visual where it was and slide it back over a few frames. Big corrections
  // (respawns, level loads) are allowed to hard-cut.
  if (!needSnap) {
    renderOffset.x += preX - self.x;
    renderOffset.y += preY - self.y;
    renderOffset.z += preZ - self.z;
    const m = renderOffset.length();
    if (m > 1.2) renderOffset.multiplyScalar(1.2 / m);
  } else {
    renderOffset.set(0, 0, 0);
  }
}

// ------------------------------------------------------------------ local fx hooks
const clientEv = {
  onLand: (p, impact) => {
    if (impact < 5) return;
    const f = Math.min(1, impact / 26);
    fx.dust(p.x, p.y, p.z, 4 + (f * 9) | 0);
    if (f > 0.35) fx.ring(p.x, p.y, p.z, 0xffffff, 1.6 + f * 2.2, 0.36);
    audio.land(f);
    const b = beans.get(net.selfId);
    if (b) b.pop(0.35 + f);
    if (f > 0.6) r3d.addShake(f * 0.16);
  },
  onJump: (p) => { fx.dust(p.x, p.y, p.z, 4); audio.jump(); const b = beans.get(net.selfId); if (b) b.pop(-0.4); },
  onDive: (p) => { fx.burst(p.x, p.y + 0.4, p.z, 8, 0xffffff, { speed: 2.2, up: 0.8, size: 0.4, life: 0.45 }); audio.dive(); },
  onBounce: (p, c) => {
    fx.ring(p.x, p.y, p.z, 0x3ee08b, 4.2, 0.5);
    fx.burst(p.x, p.y, p.z, 16, 0x3ee08b, { speed: 3.4, up: 3.4, size: 0.6, life: 0.7 });
    audio.boing();
    const b = beans.get(net.selfId); if (b) b.pop(1.3);
  },
  onTumble: (p, pw) => {
    fx.burst(p.x, p.y + 0.7, p.z, 14, 0xffd166, { speed: 3.6, up: 2.4, size: 0.55, life: 0.6 });
    audio.tumble();
    r3d.addShake(0.3);
  },
};

// ------------------------------------------------------------------ beans
function syncBeans() {
  for (const [id, r] of net.roster) {
    if (!beans.has(id)) {
      beans.set(id, new Bean(r3d.scene, r.name, r.color, id === net.selfId));
    }
  }
  for (const [id, b] of beans) {
    if (!net.roster.has(id)) { b.dispose(r3d.scene); beans.delete(id); }
  }
}

// ------------------------------------------------------------------ events from server
function drainEvents() {
  for (const e of net.events) {
    const b = beans.get(e.id);
    const r = net.roster.get(e.id);
    const mine = e.id === net.selfId;
    const pos = b ? b.root.position : null;
    switch (e.e) {
      case 'land':
        if (!mine && pos) { fx.dust(pos.x, pos.y, pos.z, 3 + (e.f * 6) | 0); if (b) b.pop(0.3 + e.f); }
        break;
      case 'jump': if (!mine && pos) { fx.dust(pos.x, pos.y, pos.z, 3); if (b) b.pop(-0.3); } break;
      case 'boing':
        if (!mine && pos) { fx.ring(pos.x, pos.y, pos.z, 0x3ee08b, 3.6, 0.45); if (b) b.pop(1.2); }
        break;
      case 'tumble':
        if (!mine && pos) fx.burst(pos.x, pos.y + 0.7, pos.z, 8, 0xffd166, { speed: 3, up: 2, size: 0.5, life: 0.5 });
        break;
      case 'bonk':
        if (pos) fx.burst(pos.x, pos.y + 0.8, pos.z, 16, 0xff5f8a, { speed: 4, up: 2.4, size: 0.6, life: 0.6 });
        if (mine) { r3d.addShake(0.42); audio.bonk(); }
        else audio.bonk();
        {
          const by = net.roster.get(e.by);
          if (by && r) hud.toast(`<b>${by.name}</b> bowled over <b>${r.name}</b>`, by.id === net.selfId ? 'good' : '');
        }
        break;
      case 'qualify':
        if (r) {
          hud.toast(`<b>${r.name}</b> qualified ${e.place ? `#${e.place}` : ''}`, mine ? 'good' : '');
          if (pos) fx.confetti(pos.x, pos.y, pos.z, mine ? 200 : 60);
          if (mine) { audio.qualify(); r3d.addFlash(0.18, 0x9dffd0); }
        }
        break;
      case 'out':
        if (r) { hud.toast(`<b>${r.name}</b> is out`, mine ? 'bad' : ''); if (mine) audio.out(); }
        break;
      case 'fall':
        if (mine) { hud.toast('You fell! Respawning…', 'bad'); r3d.addFlash(0.2, 0xff5f8a); audio.out(); }
        break;
      case 'crown':
        if (pos) fx.confetti(pos.x, pos.y, pos.z, 300);
        r3d.addFlash(0.35, 0xffe9a8);
        break;
      case 'emote':
        if (b) { b.emote = 0.9; b.pop(0.5); }
        if (pos) fx.burst(pos.x, pos.y + 1.4, pos.z, 12, 0xffd166, { speed: 2, up: 2.4, size: 0.45, life: 0.8, grav: -3 });
        break;
      case 'join': if (e.name && started && !e.bot) hud.toast(`<b>${e.name}</b> joined`); break;
    }
  }
  net.events.length = 0;
}

// ------------------------------------------------------------------ camera
function updateCamera(dt) {
  let tx = self.x + renderOffset.x, ty = self.y + renderOffset.y, tz = self.z + renderOffset.z;
  const spectating = self.status === ST_OUT || net.roster.get(net.selfId)?.spec;

  if (spectating) {
    // follow whoever is doing best
    let best = null, bestScore = -Infinity;
    for (const [id, r] of net.roster) {
      if (r.status === ST_OUT || r.spec) continue;
      const b = beans.get(id);
      if (!b) continue;
      const s = level?.mode === 'race' ? b.root.position.z : b.root.position.y;
      if (s > bestScore) { bestScore = s; best = b; }
    }
    if (best) { tx = best.root.position.x; ty = best.root.position.y; tz = best.root.position.z; }
  }

  camTarget.x += (tx - camTarget.x) * Math.min(1, dt * 14);
  camTarget.y += (ty + 1.25 - camTarget.y) * Math.min(1, dt * 9);
  camTarget.z += (tz - camTarget.z) * Math.min(1, dt * 14);

  const speed = Math.hypot(self.vx, self.vz);
  const wanted = (7.9 + Math.min(2.6, speed * 0.22)) * input.zoom;
  camDist += (wanted - camDist) * Math.min(1, dt * 4);

  const yaw = input.camYaw;
  const pitch = input.camPitch;
  const hx = Math.sin(yaw) * Math.cos(pitch);
  const hz = Math.cos(yaw) * Math.cos(pitch);
  const hy = Math.sin(pitch);

  const desiredX = camTarget.x - hx * camDist;
  const desiredY = camTarget.y + hy * camDist + 1.4;
  const desiredZ = camTarget.z - hz * camDist;

  const k = Math.min(1, dt * 15);
  camPos.x += (desiredX - camPos.x) * k;
  camPos.y += (desiredY - camPos.y) * k;
  camPos.z += (desiredZ - camPos.z) * k;

  r3d.camera.position.copy(camPos);
  r3d.camera.lookAt(camTarget.x, camTarget.y + 0.25, camTarget.z);
  r3d.focusShadow(camTarget.x, camTarget.y, camTarget.z);
}

// ------------------------------------------------------------------ HUD sync
let hudAcc = 0;
function updateHud(dt) {
  hudAcc += dt;
  if (hudAcc < 0.12) return;
  hudAcc = 0;

  const rows = [];
  let alive = 0, qualified = 0;
  for (const [id, r] of net.roster) {
    if (r.spec) continue;
    if (r.status === ST_QUALIFIED) qualified++;
    if (r.status !== ST_OUT) alive++;
    rows.push({ ...r, you: id === net.selfId });
  }
  rows.sort((a, b) => {
    const rank = (p) => (p.status === ST_QUALIFIED ? 0 : p.status === ST_OUT ? 2 : 1);
    if (rank(a) !== rank(b)) return rank(a) - rank(b);
    if (a.place && b.place) return a.place - b.place;
    return a.name.localeCompare(b.name);
  });
  hud.setStandings(rows.slice(0, 12));
  hud.setAlive(alive);

  const mode = level?.mode;
  if (mode === 'survive') hud.setQualify(Math.max(0, alive - qualified), net.qualify, mode);
  else if (mode === 'crown') hud.setQualify(0, 0, mode);
  else if (mode === 'race') hud.setQualify(qualified, net.qualify, mode);
  else hud.setQualify(0, 0, mode);

  hud.setRound(net.roundIdx, net.roundTotal, level?.name || '');
  hud.setStats(fps, net.rtt);

  const me = net.roster.get(net.selfId);
  const specNote = document.getElementById('spectate-note');
  const isSpec = !!(me && me.spec) && net.phase !== K.STATE_LOBBY;
  const isOut = !!(me && me.status === ST_OUT) && !isSpec && net.phase === K.STATE_PLAYING;
  specNote.classList.toggle('hidden', !(isSpec || isOut));
  if (isSpec) specNote.innerHTML = "👀 Spectating — you're in the <b>next</b> match";
  else if (isOut) specNote.innerHTML = '👀 Knocked out — watching the <b>leader</b>';

  const elapsed = (performance.now() - net.phaseAt) / 1000;
  const remain = Math.max(0, net.phaseEndsIn - elapsed);
  if (net.phase === K.STATE_ROUND_END) hud.countdown(hud.el.resNext, remain);
  if (net.phase === K.STATE_MATCH_END) hud.countdown(hud.el.winNext, remain);
}

let lastCountdownSec = -1;
function updateBanners() {
  const elapsed = (performance.now() - net.phaseAt) / 1000;
  const remain = Math.max(0, net.phaseEndsIn - elapsed);

  if (net.phase === K.STATE_COUNTDOWN) {
    const s = Math.ceil(remain);
    hud.bigPersist(s > 0 ? String(s) : 'GO!', s <= 3 ? '#ff9040' : '#fff');
    hud.el.sub.textContent = 'Match starting';
    hud.el.sub.style.opacity = '1';
    if (s !== lastCountdownSec) { lastCountdownSec = s; if (s <= 5 && s > 0) audio.tick(); }
  } else if (net.phase === K.STATE_PLAYING) {
    const introTicks = Math.round((K.ROUND_INTRO_MS / 1000) * K.TICK_HZ);
    const intoRound = net.serverTick - net.roundStartTick;
    if (intoRound < introTicks) {
      if (introShown !== net.roundIdx) {
        introShown = net.roundIdx;
        hud.bigPersist(level?.name || '', '#fff');
        hud.el.sub.textContent = level?.tagline || '';
        hud.el.sub.style.opacity = '1';
      }
    } else if (goShown !== net.roundIdx) {
      goShown = net.roundIdx;
      hud.big('GO!', '', '#3ee08b');
      audio.go();
      lastCountdownSec = -1;
    }
  } else if (net.phase === K.STATE_LOBBY) {
    if (lastCountdownSec !== -2) {
      lastCountdownSec = -2;
      hud.clearBig();
      hud.el.sub.textContent = '';
    }
  }
}

// ------------------------------------------------------------------ main loop
let last = performance.now();
let acc = 0;
let fps = 60;
let fpsAcc = 0, fpsCount = 0;

function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last) / 1000;
  last = now;
  if (dt > 0.1) dt = 0.1;

  fpsAcc += dt; fpsCount++;
  if (fpsAcc > 0.5) { fps = fpsCount / fpsAcc; fpsAcc = 0; fpsCount = 0; }

  if (started && world) {
    syncBeans();
    reconcile();

    // keep the prediction clock gently locked to server tick + lead
    const target = net.serverTick + net.lead;
    const drift = target - predictTick;
    if (Math.abs(drift) > 12) predictTick = target;
    const scale = 1 + clamp(drift * 0.03, -0.2, 0.25);

    acc += dt * scale;
    let steps = 0;
    while (acc >= K.DT && steps < 4) { acc -= K.DT; doTick(); steps++; }

    // remote interpolation clock
    const itarget = net.serverTick - Math.ceil((K.INTERP_DELAY_MS / 1000) * K.TICK_HZ);
    if (Math.abs(itarget - interpClock) > 10) interpClock = itarget;
    interpClock += dt * K.TICK_HZ * (1 + clamp((itarget - interpClock) * 0.03, -0.2, 0.2));

    drainEvents();
    updateRender(dt);
    updateCamera(dt);
    updateHud(dt);
    updateBanners();
  }

  fx.update(dt);
  r3d.render(dt);
}

function updateRender(dt) {
  renderOffset.multiplyScalar(Math.exp(-13 * dt));
  if (renderOffset.lengthSq() < 1e-8) renderOffset.set(0, 0, 0);

  // local player
  const myBean = beans.get(net.selfId);
  if (myBean) {
    myBean.update(dt, {
      x: self.x + renderOffset.x, y: self.y + renderOffset.y, z: self.z + renderOffset.z, yaw: self.yaw,
      grounded: self.grounded, dive: self.dive === 1,
      tumble: self.tumble > 0, getUp: self.getUp / K.DIVE_GET_UP_TICKS,
      vy: self.vy, speed: Math.hypot(self.vx, self.vz),
      showTag: false,
    }, camPos);
    myBean.root.visible = self.status !== ST_OUT || net.phase === K.STATE_LOBBY;
  }

  // remotes
  for (const [id, b] of beans) {
    if (id === net.selfId) continue;
    const s = net.sample(id, interpClock);
    if (!s) { b.root.visible = false; continue; }
    const r = net.roster.get(id);
    b.root.visible = !(r && r.spec);
    b.lastState = s;
    b.update(dt, {
      x: s.x, y: s.y, z: s.z, yaw: s.yaw,
      grounded: !!(s.f & 1), dive: !!(s.f & 2), tumble: !!(s.f & 4), getUp: (s.f & 8) ? 0.5 : 0,
      vy: s.vy, speed: Math.hypot(s.vx, s.vz),
      showTag: true,
    }, camPos);
  }

  if (view) {
    view.update(dt, world.time, net.tileTrig, predictTick, level.tileFadeTicks || 26);
  }
}

// ------------------------------------------------------------------ boot
hud.setConn('ready', 'ok');
hud.hideLoading();
requestAnimationFrame(frame);

// warm the shaders on the lobby so the first frame after joining isn't a stall
loadLevel('lobby', true);
r3d.camera.position.set(0, 16, -30);
r3d.camera.lookAt(0, 2, 0);
(function idleSpin() {
  if (started) return;
  const t = performance.now() / 1000;
  camTarget.set(0, 3, 0);
  camPos.set(Math.sin(t * 0.12) * 30, 13 + Math.sin(t * 0.3) * 2, Math.cos(t * 0.12) * 30);
  r3d.camera.position.copy(camPos);
  r3d.camera.lookAt(0, 3.4, 0);
  r3d.focusShadow(0, 0, 0);
  if (world) world.setTime(t);
  if (view) view.update(1 / 60, t, null, 0, 26);
  requestAnimationFrame(idleSpin);
})();

window.addEventListener('pointerdown', () => audio.resume(), { once: true });
window.addEventListener('keydown', () => audio.resume(), { once: true });

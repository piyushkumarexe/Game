// Headless client that runs the REAL prediction + reconciliation path against a live
// server, and reports how far prediction drifts from authority. This is the test that
// catches sim divergence — the bug class that makes multiplayer feel like rubber.

import WebSocket from 'ws';
import * as K from '../shared/constants.js';
import { World } from '../shared/world.js';
import { getLevel } from '../shared/levels.js';
import { makePlayer, stepPlayer, emptyInput, ST_ALIVE } from '../shared/sim.js';

const URL = process.env.URL || 'ws://127.0.0.1:8080/ws';
const DURATION = Number(process.env.SECS || 45) * 1000;
const NAME = process.env.NAME || 'PredictBot';

const ws = new WebSocket(URL);
const self = makePlayer(0, NAME, 0xffffff);
let world = null, level = null, levelId = null;
let selfId = 0, serverTick = 0, roundStartTick = 0, phase = 0, rtt = 60;
let predictTick = 0, inputSeq = 0;
const history = [];
let pendingSelf = null;
let tileTrig = new Int32Array(0);

const stats = { snaps: 0, snaps_ok: 0, errs: [], snapsBig: 0, replays: 0, maxErr: 0, levels: [] };

function loadLevel(id) {
  if (id === levelId) return;
  levelId = id;
  level = getLevel(id);
  world = new World(level);
  world.setTime(0);
  history.length = 0;
  stats.levels.push(id);
}

function worldTimeFor(t) { return (t - roundStartTick) * K.DT; }
const lead = () => Math.ceil((rtt / 2000) * K.TICK_HZ) + 2;

function frozenNow() {
  if (phase === K.STATE_ROUND_END || phase === K.STATE_MATCH_END) return true;
  if (phase === K.STATE_PLAYING) {
    const introTicks = Math.round((K.ROUND_INTRO_MS / 1000) * K.TICK_HZ);
    return predictTick < roundStartTick + introTicks;
  }
  return false;
}

// a simple "player" that runs forward and jumps, to exercise real movement
function makeInput() {
  const inp = emptyInput();
  const t = predictTick / K.TICK_HZ;
  inp.mx = Math.sin(t * 0.7) * 0.35;
  inp.mz = 1;
  inp.jump = predictTick % 37 === 0;
  inp.dive = predictTick % 151 === 0;
  return inp;
}

function reconcile() {
  const s = pendingSelf;
  if (!s) return;
  pendingSelf = null;
  const [seq, x, y, z, vx, vy, vz, yaw, grounded, groundId, dive, diveT, tumble, getUp, coyote, jumpBuf, diveCd, status, respawnT, checkpoint] = s;
  self.status = status; self.respawnT = respawnT; self.checkpoint = checkpoint;

  let hi = -1;
  for (let i = 0; i < history.length; i++) if (history[i].seq === seq) { hi = i; break; }

  const err = Math.hypot(self.x - x, self.y - y, self.z - z);
  stats.snaps++;
  if (status === ST_ALIVE && hi >= 0) {
    stats.errs.push(err);
    stats.maxErr = Math.max(stats.maxErr, err);
    if (err < 0.25) stats.snaps_ok++; else stats.snapsBig++;
  }

  const needSnap = hi === -1 || err > 3.5 || status !== ST_ALIVE;
  if (!needSnap && err < 0.06) { if (hi >= 0) history.splice(0, hi + 1); return; }

  self.x = x; self.y = y; self.z = z;
  self.vx = vx; self.vy = vy; self.vz = vz; self.yaw = yaw;
  self.grounded = !!grounded; self.groundId = groundId;
  self.dive = dive; self.diveT = diveT; self.tumble = tumble; self.getUp = getUp;
  self.coyote = coyote; self.jumpBuf = jumpBuf; self.diveCd = diveCd;

  const replay = hi >= 0 ? history.slice(hi + 1) : [];
  if (replay.length) stats.replays++;
  for (const h of replay) { world.setTime(worldTimeFor(h.tick)); stepPlayer(self, h.inp, world, null); }
  world.setTime(worldTimeFor(predictTick));
  if (hi >= 0) history.splice(0, hi + 1); else history.length = 0;
}

ws.on('open', () => ws.send(JSON.stringify({ t: 'join', name: NAME, color: 3 })));
ws.on('message', (raw) => {
  const m = JSON.parse(raw);
  if (m.t === 'welcome') {
    selfId = m.id; serverTick = m.tick; roundStartTick = m.rst; phase = m.phase;
    loadLevel(m.level);
    predictTick = serverTick + lead();
  } else if (m.t === 'level') {
    loadLevel(m.id);
    tileTrig = Int32Array.from(m.tiles || []);
  } else if (m.t === 'phase') {
    phase = m.ph;
    if (m.rst !== undefined) roundStartTick = m.rst;
    if (m.level) loadLevel(m.level);
  } else if (m.t === 's') {
    serverTick = m.k;
    if (m.you) pendingSelf = m.you;
  } else if (m.t === 'pong') {
    rtt = rtt * 0.7 + (Date.now() - m.c) * 0.3;
  }
});

setInterval(() => { if (ws.readyState === 1) ws.send(JSON.stringify({ t: 'ping', c: Date.now() })); }, 2000);

// client-side fixed loop, same structure as the browser
let acc = 0, last = Date.now();
const loop = setInterval(() => {
  const now = Date.now();
  let dt = (now - last) / 1000; last = now;
  if (dt > 0.1) dt = 0.1;
  if (!world || !selfId) return;

  reconcile();
  const target = serverTick + lead();
  const drift = target - predictTick;
  if (Math.abs(drift) > 12) predictTick = target;
  const scale = 1 + Math.max(-0.2, Math.min(0.25, drift * 0.03));
  acc += dt * scale;

  let steps = 0;
  while (acc >= K.DT && steps < 4) {
    acc -= K.DT; steps++;
    predictTick++;
    const inp = makeInput();
    const frozen = frozenNow();
    const used = frozen ? emptyInput() : inp;
    world.setTime(worldTimeFor(predictTick));
    stepPlayer(self, used, world, null);
    history.push({ seq: inputSeq, tick: predictTick, inp: { ...used } });
    if (history.length > 80) history.shift();
    ws.send(JSON.stringify({ t: 'in', s: inputSeq, x: used.mx, z: used.mz, j: used.jump ? 1 : 0, d: used.dive ? 1 : 0, a: 0 }));
    inputSeq++;
  }
}, 8);

setTimeout(() => {
  clearInterval(loop);
  const e = stats.errs.sort((a, b) => a - b);
  const pct = (p) => (e.length ? e[Math.floor(e.length * p)] : 0);
  console.log('\n──────── client prediction report ────────');
  console.log(` levels visited : ${stats.levels.join(' → ')}`);
  console.log(` snapshots      : ${stats.snaps}  (measured while alive: ${e.length})`);
  console.log(` within 0.25 m  : ${((stats.snaps_ok / Math.max(1, e.length)) * 100).toFixed(1)} %`);
  console.log(` error  p50     : ${pct(0.5).toFixed(4)} m`);
  console.log(` error  p95     : ${pct(0.95).toFixed(4)} m`);
  console.log(` error  p99     : ${pct(0.99).toFixed(4)} m`);
  console.log(` error  max     : ${stats.maxErr.toFixed(3)} m`);
  console.log(` replays        : ${stats.replays}`);
  console.log('──────────────────────────────────────────\n');
  const ok = pct(0.5) < 0.02 && pct(0.95) < 0.35;
  console.log(ok ? '✅ prediction is in lockstep with the server' : '❌ prediction drifts — investigate sim divergence');
  process.exit(ok ? 0 : 1);
}, DURATION);

import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import compression from 'compression';
import { WebSocketServer } from 'ws';

import * as K from '../shared/constants.js';
import { Room } from './room.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.PORT || 8080);

const app = express();
app.disable('x-powered-by');
app.use(compression());

const DIST = path.join(ROOT, 'dist');
app.use(express.static(DIST, { maxAge: '1h', index: false }));
app.get('/health', (_req, res) => res.json({ ok: true, players: room.players.size, tick: room.tick }));
// SPA fallback (Express 5 dropped the bare '*' route pattern)
app.use((req, res, next) => {
  if (req.method !== 'GET' || req.path.startsWith('/ws')) return next();
  res.sendFile(path.join(DIST, 'index.html'), (err) => { if (err) next(); });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws', perMessageDeflate: false });

// ------------------------------------------------------------------ room
const sockets = new Set();

function broadcast(obj) {
  const s = JSON.stringify(obj);
  for (const ws of sockets) {
    if (ws.readyState === 1) ws.send(s);
  }
}

const room = new Room(broadcast);
room.ev = {
  onLand: (p, impact) => { if (impact > 11) room.pushEvent({ e: 'land', id: p.id, f: Math.min(1, impact / 26) }); },
  onJump: (p) => room.pushEvent({ e: 'jump', id: p.id }),
  onDive: (p) => room.pushEvent({ e: 'dive', id: p.id }),
  onBounce: (p) => room.pushEvent({ e: 'boing', id: p.id }),
  onTumble: (p, pw) => room.pushEvent({ e: 'tumble', id: p.id, f: Math.min(1, pw / 14) }),
  onBonk: (a, b) => room.pushEvent({ e: 'bonk', id: b.id, by: a.id }),
};

// ------------------------------------------------------------------ sockets
wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  ws.playerId = 0;
  sockets.add(ws);
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    if (!msg || typeof msg.t !== 'string') return;

    switch (msg.t) {
      case 'join': {
        if (ws.playerId) return;
        const p = room.addHuman(ws, msg.name, msg.color | 0);
        if (!p) { ws.send(JSON.stringify({ t: 'full' })); return ws.close(); }
        ws.playerId = p.id;
        ws.send(JSON.stringify({
          t: 'welcome',
          v: K.PROTOCOL_VERSION,
          id: p.id,
          tick: room.tick,
          level: room.levelId,
          rst: room.roundStartTick,
          phase: room.phase,
          endsIn: Math.max(0, room.phaseEndTick - room.tick) * K.DT,
          roundIdx: room.roundIdx,
          roundTotal: 3,
          qualify: room.qualifyTarget,
          roster: room.roster(),
          tiles: Array.from(room.tileTrig || []),
          results: room.lastResults || null,
          winner: room.winnerId,
        }));
        break;
      }
      case 'in': {
        const inp = room.inputs.get(ws.playerId);
        const p = room.players.get(ws.playerId);
        if (!inp || !p) return;
        inp.mx = clampf(msg.x, -1.2, 1.2);
        inp.mz = clampf(msg.z, -1.2, 1.2);
        inp.yaw = typeof msg.a === 'number' ? msg.a : inp.yaw;
        if (msg.j) inp.jump = true;
        if (msg.d) inp.dive = true;
        p.lastSeq = msg.s | 0;
        break;
      }
      case 'ping':
        ws.send(JSON.stringify({ t: 'pong', c: msg.c, k: room.tick }));
        break;
      case 'start':
        room.requestStart();
        break;
      case 'emote':
        if (ws.playerId) room.pushEvent({ e: 'emote', id: ws.playerId, k: (msg.k | 0) % 6 });
        break;
      case 'name': {
        const p = room.players.get(ws.playerId);
        if (p && typeof msg.name === 'string') {
          p.name = msg.name.replace(/[^\w \-'!?.]/g, '').trim().slice(0, 14) || p.name;
          broadcast({ t: 'roster', roster: room.roster() });
        }
        break;
      }
    }
  });

  ws.on('close', () => {
    sockets.delete(ws);
    if (ws.playerId) {
      room.removePlayer(ws.playerId);
      broadcast({ t: 'roster', roster: room.roster() });
    }
  });
  ws.on('error', () => {});
});

const heartbeat = setInterval(() => {
  for (const ws of sockets) {
    if (!ws.isAlive) { ws.terminate(); sockets.delete(ws); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch {}
  }
}, 15000);

// ------------------------------------------------------------------ game loop
let rosterDirty = false;
const origPush = room.pushEvent.bind(room);
room.pushEvent = (e) => {
  origPush(e);
  if (e.e === 'join' || e.e === 'leave' || e.e === 'qualify' || e.e === 'out') rosterDirty = true;
};

let acc = 0;
let last = process.hrtime.bigint();
let tickCount = 0;

function loop() {
  const now = process.hrtime.bigint();
  let delta = Number(now - last) / 1e9;
  last = now;
  if (delta > 0.25) delta = 0.25;
  acc += delta;

  let steps = 0;
  while (acc >= K.DT && steps < 5) {
    acc -= K.DT;
    steps++;
    tickCount++;
    room.update();

    if (tickCount % K.SNAPSHOT_EVERY === 0) {
      const shared = room.snapshotShared();
      for (const ws of sockets) {
        if (ws.readyState !== 1 || !ws.playerId) continue;
        const p = room.players.get(ws.playerId);
        shared.you = p ? room.selfState(p) : undefined;
        ws.send(JSON.stringify(shared));
      }
      room.events.length = 0;
    }

    if (rosterDirty) {
      rosterDirty = false;
      broadcast({ t: 'roster', roster: room.roster() });
    }
  }
}

const loopTimer = setInterval(loop, 1000 / (K.TICK_HZ * 2));

function clampf(v, a, b) {
  v = Number(v);
  if (!Number.isFinite(v)) return 0;
  return v < a ? a : v > b ? b : v;
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  🎪  Tumble Royale server listening on http://0.0.0.0:${PORT}\n`);
});

function shutdown() {
  clearInterval(heartbeat);
  clearInterval(loopTimer);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

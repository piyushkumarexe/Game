import * as K from '../shared/constants.js';
import { makePlayer, emptyInput } from '../shared/sim.js';

const INTERP_TICKS = Math.ceil((K.INTERP_DELAY_MS / 1000) * K.TICK_HZ);

export class Net extends EventTarget {
  constructor() {
    super();
    this.ws = null;
    this.selfId = 0;
    this.connected = false;
    this.roster = new Map();      // id -> {id,name,color,bot,status,place,spec}
    this.remote = new Map();      // id -> { buf: [], render: {} }
    this.serverTick = 0;
    this.rtt = 60;
    this.levelId = 'lobby';
    this.roundStartTick = 0;
    this.phase = K.STATE_LOBBY;
    this.phaseEndsIn = 0;
    this.phaseAt = 0;
    this.roundIdx = -1;
    this.roundTotal = 3;
    this.qualify = 0;
    this.results = null;
    this.winner = 0;
    this.tileTrig = new Int32Array(0);
    this.pendingSelf = null;
    this.events = [];
    this.lastPing = 0;
  }

  connect(name, colorIdx) {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${proto}//${location.host}/ws`;
    this.name = name;
    this.colorIdx = colorIdx;
    const ws = new WebSocket(url);
    this.ws = ws;
    ws.onopen = () => {
      this.connected = true;
      ws.send(JSON.stringify({ t: 'join', name, color: colorIdx }));
      this.pingTimer = setInterval(() => this.ping(), 2000);
      this.ping();
    };
    ws.onclose = () => {
      this.connected = false;
      clearInterval(this.pingTimer);
      this.dispatchEvent(new CustomEvent('disconnected'));
    };
    ws.onerror = () => {};
    ws.onmessage = (e) => this.onMessage(JSON.parse(e.data));
  }

  ping() {
    if (this.ws?.readyState === 1) {
      this.lastPing = performance.now();
      this.ws.send(JSON.stringify({ t: 'ping', c: this.lastPing }));
    }
  }

  send(o) { if (this.ws?.readyState === 1) this.ws.send(JSON.stringify(o)); }

  sendInput(seq, inp) {
    this.send({ t: 'in', s: seq, x: round3(inp.mx), z: round3(inp.mz), j: inp.jump ? 1 : 0, d: inp.dive ? 1 : 0, a: round3(inp.yaw) });
  }

  onMessage(m) {
    switch (m.t) {
      case 'welcome': {
        this.selfId = m.id;
        this.serverTick = m.tick;
        this.applyPhase(m);
        this.setRoster(m.roster);
        this.tileTrig = Int32Array.from(m.tiles || []);
        this.dispatchEvent(new CustomEvent('welcome', { detail: m }));
        break;
      }
      case 'level': {
        this.levelId = m.id;
        this.tileTrig = Int32Array.from(m.tiles || []);
        this.dispatchEvent(new CustomEvent('level', { detail: m }));
        break;
      }
      case 'phase': {
        this.applyPhase(m);
        this.dispatchEvent(new CustomEvent('phase', { detail: m }));
        break;
      }
      case 'roster':
        this.setRoster(m.roster);
        this.dispatchEvent(new CustomEvent('roster'));
        break;
      case 'pong':
        this.rtt = this.rtt * 0.7 + (performance.now() - m.c) * 0.3;
        break;
      case 'full':
        this.dispatchEvent(new CustomEvent('full'));
        break;
      case 's':
        this.onSnapshot(m);
        break;
    }
  }

  applyPhase(m) {
    if (m.level !== undefined && m.level !== this.levelId) {
      this.levelId = m.level;
      this.dispatchEvent(new CustomEvent('level', { detail: { id: m.level } }));
    }
    this.phase = m.ph !== undefined ? m.ph : m.phase;
    this.phaseEndsIn = m.endsIn || 0;
    this.phaseAt = performance.now();
    if (m.rst !== undefined) this.roundStartTick = m.rst;
    if (m.roundIdx !== undefined) this.roundIdx = m.roundIdx;
    if (m.roundTotal !== undefined) this.roundTotal = m.roundTotal;
    if (m.qualify !== undefined) this.qualify = m.qualify;
    this.results = m.results || null;
    this.winner = m.winner || 0;
  }

  setRoster(list) {
    const seen = new Set();
    for (const r of list) {
      seen.add(r.id);
      const cur = this.roster.get(r.id);
      if (cur) Object.assign(cur, r);
      else this.roster.set(r.id, r);
    }
    for (const id of [...this.roster.keys()]) if (!seen.has(id)) { this.roster.delete(id); this.remote.delete(id); }
  }

  onSnapshot(m) {
    this.serverTick = m.k;
    for (const row of m.p) {
      const [id, x, y, z, yaw, f, status, vx, vy, vz] = row;
      let r = this.remote.get(id);
      if (!r) { r = { buf: [], last: null }; this.remote.set(id, r); }
      r.buf.push({ k: m.k, x, y, z, yaw, f, status, vx, vy, vz });
      if (r.buf.length > 24) r.buf.shift();
      const rs = this.roster.get(id);
      if (rs) rs.status = status;
    }
    if (m.you) this.pendingSelf = m.you;
    if (m.ev) {
      for (const e of m.ev) {
        if (e.e === 'tile') {
          if (e.i < this.tileTrig.length) this.tileTrig[e.i] = e.k;
        }
        this.events.push(e);
      }
    }
  }

  /** Sample a remote player at an interpolated tick. */
  sample(id, atTick) {
    const r = this.remote.get(id);
    if (!r || !r.buf.length) return null;
    const buf = r.buf;
    if (atTick <= buf[0].k) return buf[0];
    if (atTick >= buf[buf.length - 1].k) return buf[buf.length - 1];
    for (let i = buf.length - 1; i > 0; i--) {
      const b = buf[i], a = buf[i - 1];
      if (atTick >= a.k && atTick <= b.k) {
        const span = b.k - a.k || 1;
        const t = (atTick - a.k) / span;
        let dy = b.yaw - a.yaw;
        if (dy > Math.PI) dy -= Math.PI * 2;
        if (dy < -Math.PI) dy += Math.PI * 2;
        return {
          x: a.x + (b.x - a.x) * t,
          y: a.y + (b.y - a.y) * t,
          z: a.z + (b.z - a.z) * t,
          yaw: a.yaw + dy * t,
          f: b.f, status: b.status,
          vx: a.vx + (b.vx - a.vx) * t,
          vy: a.vy + (b.vy - a.vy) * t,
          vz: a.vz + (b.vz - a.vz) * t,
        };
      }
    }
    return buf[buf.length - 1];
  }

  get interpTick() { return this.serverTick - INTERP_TICKS; }

  /** How far ahead of the server the client should predict. */
  get lead() { return Math.ceil((this.rtt / 2000) * K.TICK_HZ) + 2; }
}

const round3 = (v) => Math.round(v * 1000) / 1000;

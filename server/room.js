import * as K from '../shared/constants.js';
import { World } from '../shared/world.js';
import { LEVELS, ROUND_ORDER, getLevel } from '../shared/levels.js';
import { makePlayer, stepPlayer, resolvePlayerCollisions, emptyInput, ST_ALIVE, ST_RESPAWN, ST_QUALIFIED, ST_OUT } from '../shared/sim.js';
import { makeRng, hash01 } from '../shared/math.js';
import { BotBrain } from './bots.js';

const BOT_NAMES = [
  'Pixel', 'Waffle', 'Nova', 'Bloop', 'Zigzag', 'Mochi', 'Turbo', 'Pebble',
  'Sprout', 'Cosmo', 'Jelly', 'Rocket', 'Dizzy', 'Momo', 'Ziggy', 'Bubbles',
  'Ranger', 'Peanut', 'Comet', 'Tofu', 'Sparky', 'Yuki', 'Bolt', 'Coco',
];

export const COLORS = [
  0xff5f8a, 0x4fc3ff, 0xffc94a, 0x5ddb8a, 0xb07dff, 0xff8a4a,
  0x44e0d0, 0xff6be0, 0x8fd14f, 0x6d8bff, 0xffa3c4, 0xd6e14f,
];

let nextId = 1;

export class Room {
  constructor(broadcast) {
    this.broadcast = broadcast;
    this.players = new Map();       // id -> player
    this.clients = new Map();       // id -> ws
    this.inputs = new Map();        // id -> pending input
    this.bots = new Map();          // id -> BotBrain
    this.tick = 0;
    this.phase = K.STATE_LOBBY;
    this.phaseEndTick = 0;
    this.roundIdx = -1;
    this.levelId = 'lobby';
    this.events = [];
    this.rng = makeRng(Date.now() & 0xffffffff);
    this.matchResults = [];
    this.winnerId = 0;
    this.crownHolder = 0;
    this.roundStartTick = 0;
    this.finishOrder = [];
    this.qualifyTarget = 0;
    this.spawnCursor = 0;
    this.loadLevel('lobby');
  }

  // ------------------------------------------------------------------ level
  loadLevel(id) {
    this.levelId = id;
    this.level = getLevel(id);
    this.world = new World(this.level);
    this.roundStartTick = this.tick;
    this.tileTrig = new Int32Array(this.world.tiles.length);
    this.tileByCollider = new Map();
    this.world.tiles.forEach((t, i) => this.tileByCollider.set(t.id, i));
    this.spawnCursor = 0;
    this.finishOrder = [];
    this.crownHolder = 0;
    this.world.setTime(0);
  }

  worldTime() { return (this.tick - this.roundStartTick) * K.DT; }

  // ------------------------------------------------------------------ players
  addHuman(ws, name, colorIdx) {
    if (this.players.size >= K.MAX_PLAYERS) return null;
    const id = nextId++;
    const safe = (name || '').replace(/[^\w \-'!?.]/g, '').trim().slice(0, 14) || 'Player';
    const p = makePlayer(id, safe, COLORS[colorIdx % COLORS.length]);
    p.bot = false;
    this.players.set(id, p);
    this.clients.set(id, ws);
    this.inputs.set(id, emptyInput());
    this.spawnPlayer(p, true);
    if (this.phase !== K.STATE_LOBBY) {
      p.status = ST_OUT;     // joined mid-match -> spectate until next match
      p.spectator = true;
    }
    this.pushEvent({ e: 'join', id, name: p.name, color: p.color, bot: false });
    return p;
  }

  addBot() {
    const id = nextId++;
    const n = BOT_NAMES[(id * 7) % BOT_NAMES.length];
    const p = makePlayer(id, n, COLORS[(id * 5) % COLORS.length]);
    p.bot = true;
    this.players.set(id, p);
    this.inputs.set(id, emptyInput());
    this.bots.set(id, new BotBrain(id, hash01(id * 977 + 13)));
    this.spawnPlayer(p, true);
    this.pushEvent({ e: 'join', id, name: p.name, color: p.color, bot: true });
    return p;
  }

  removePlayer(id) {
    this.players.delete(id);
    this.clients.delete(id);
    this.inputs.delete(id);
    this.bots.delete(id);
    this.pushEvent({ e: 'leave', id });
  }

  spawnPlayer(p, reset) {
    const sp = this.world.spawns[this.spawnCursor % Math.max(1, this.world.spawns.length)] || { x: 0, y: 3, z: 0, yaw: 0 };
    this.spawnCursor++;
    p.x = sp.x; p.y = sp.y + 0.05; p.z = sp.z; p.yaw = sp.yaw || 0;
    p.vx = p.vy = p.vz = 0;
    p.grounded = false; p.groundId = -1;
    p.dive = 0; p.diveT = 0; p.tumble = 0; p.getUp = 0; p.diveCd = 0;
    p.lastGroundY = p.y;
    if (reset) {
      p.status = ST_ALIVE;
      p.checkpoint = 0;
      p.progress = 0;
      p.place = 0;
      p.spectator = false;
      p.respawnT = 0;
    }
  }

  respawnAtCheckpoint(p) {
    const lvl = this.level;
    if (lvl.respawnMode === 'checkpoint') {
      const cps = this.world.triggers.filter((t) => t.kind === 'checkpoint');
      const cp = cps.find((c) => c.idx === p.checkpoint);
      if (cp && cp.rp) { p.x = cp.rp.x + (this.rng() - 0.5) * 7; p.y = cp.rp.y + 0.4; p.z = cp.rp.z; }
      else { const sp = this.world.spawns[(p.id * 3) % this.world.spawns.length]; p.x = sp.x; p.y = sp.y; p.z = sp.z; }
      p.yaw = 0;
    } else {
      const sp = this.world.spawns[(p.id * 3) % this.world.spawns.length];
      p.x = sp.x; p.y = sp.y + 0.1; p.z = sp.z; p.yaw = sp.yaw || 0;
    }
    p.vx = p.vy = p.vz = 0;
    p.grounded = false; p.groundId = -1;
    p.dive = 0; p.tumble = 0; p.getUp = 0;
    p.status = ST_RESPAWN;
    p.respawnT = Math.round(1.3 * K.TICK_HZ);
  }

  pushEvent(e) { this.events.push(e); }

  humans() { let n = 0; for (const p of this.players.values()) if (!p.bot) n++; return n; }
  contenders() { return [...this.players.values()].filter((p) => !p.spectator); }

  // ------------------------------------------------------------------ phases
  setPhase(ph, durationMs) {
    this.phase = ph;
    this.phaseEndTick = this.tick + Math.round((durationMs / 1000) * K.TICK_HZ);
    this.broadcastPhase();
  }

  broadcastPhase(extra = {}) {
    this.broadcast({
      t: 'phase',
      ph: this.phase,
      level: this.levelId,
      tick: this.tick,
      rst: this.roundStartTick,
      endsIn: Math.max(0, this.phaseEndTick - this.tick) * K.DT,
      roundIdx: this.roundIdx,
      roundTotal: ROUND_ORDER.length,
      qualify: this.qualifyTarget,
      winner: this.winnerId,
      results: this.lastResults || null,
      ...extra,
    });
  }

  startMatch() {
    // top up with bots so a solo player still gets a real show
    const want = Math.max(K.TARGET_LOBBY_SIZE, Math.min(K.MAX_PLAYERS, this.humans() + 3));
    let guard = 0;
    while (this.players.size < want && guard++ < 40) this.addBot();
    for (const p of this.players.values()) { p.spectator = false; p.status = ST_ALIVE; p.place = 0; }
    this.matchResults = [];
    this.winnerId = 0;
    this.roundIdx = -1;
    this.nextRound();
  }

  nextRound() {
    this.roundIdx++;
    const alive = this.contenders().filter((p) => p.status !== ST_OUT);
    if (this.roundIdx >= ROUND_ORDER.length || alive.length <= 1) {
      return this.endMatch(alive[0]);
    }
    const id = ROUND_ORDER[this.roundIdx];
    this.loadLevel(id);
    this.spawnCursor = 0;
    const lvl = this.level;
    const contenders = this.contenders().filter((p) => p.status !== ST_OUT);
    for (const p of contenders) this.spawnPlayer(p, true);
    for (const p of this.players.values()) {
      if (p.status === ST_OUT) p.spectator = true;
      const b = this.bots.get(p.id);
      if (b) b.reset(this.level);
    }
    this.qualifyTarget = lvl.qualifyRatio
      ? Math.max(1, Math.min(contenders.length - 1, Math.round(contenders.length * lvl.qualifyRatio)))
      : 1;
    if (contenders.length <= 2) this.qualifyTarget = 1;
    this.lastResults = null;
    this.roundDeadline = this.tick + Math.round((lvl.timeLimitMs / 1000) * K.TICK_HZ) + Math.round((K.ROUND_INTRO_MS / 1000) * K.TICK_HZ);
    this.graceTick = 0;
    this.setPhase(K.STATE_PLAYING, K.ROUND_INTRO_MS);
    this.introUntil = this.phaseEndTick;
    this.broadcast({ t: 'level', id, tiles: Array.from(this.tileTrig) });
  }

  endRound() {
    const contenders = this.contenders();
    const qualified = [];
    const out = [];
    for (const p of contenders) {
      if (p.status === ST_QUALIFIED) qualified.push(p);
      else if (p.status !== ST_OUT) { p.status = ST_OUT; out.push(p); }
      else out.push(p);
    }
    qualified.sort((a, b) => a.place - b.place);
    this.lastResults = {
      qualified: qualified.map((p) => ({ id: p.id, name: p.name, color: p.color, place: p.place, bot: p.bot })),
      out: out.map((p) => ({ id: p.id, name: p.name, color: p.color, bot: p.bot })),
    };
    for (const p of qualified) p.status = ST_ALIVE;
    this.setPhase(K.STATE_ROUND_END, K.ROUND_END_MS);
  }

  endMatch(winner) {
    this.winnerId = winner ? winner.id : 0;
    const all = [...this.players.values()];
    this.lastResults = {
      winner: winner ? { id: winner.id, name: winner.name, color: winner.color, bot: winner.bot } : null,
      standings: all.map((p) => ({ id: p.id, name: p.name, color: p.color, bot: p.bot })),
    };
    this.setPhase(K.STATE_MATCH_END, K.MATCH_END_MS);
  }

  returnToLobby() {
    // clear bots between matches so the lobby doesn't bloat
    for (const [id, p] of [...this.players]) if (p.bot) this.removePlayer(id);
    this.roundIdx = -1;
    this.winnerId = 0;
    this.lastResults = null;
    this.loadLevel('lobby');
    this.spawnCursor = 0;
    for (const p of this.players.values()) { this.spawnPlayer(p, true); p.spectator = false; }
    this.setPhase(K.STATE_LOBBY, 999999);
    this.broadcast({ t: 'level', id: 'lobby', tiles: [] });
    this.countdownStarted = false;
  }

  requestStart() {
    if (this.phase !== K.STATE_LOBBY) return;
    this.setPhase(K.STATE_COUNTDOWN, 3200);
  }

  // ------------------------------------------------------------------ tick
  update() {
    this.tick++;
    const wt = this.worldTime();
    this.world.setTime(wt);

    // dead tiles
    if (this.world.tiles.length) {
      const fade = this.level.tileFadeTicks || 26;
      for (let i = 0; i < this.world.tiles.length; i++) {
        const trig = this.tileTrig[i];
        if (trig > 0) {
          const c = this.world.byId.get(this.world.tiles[i].id);
          if (c && !c.dead && this.tick - trig >= fade) c.dead = true;
        }
      }
    }

    const intro = this.phase === K.STATE_PLAYING && this.tick < this.introUntil;
    const frozen = intro || this.phase === K.STATE_ROUND_END || this.phase === K.STATE_MATCH_END;

    // ---- bots think ----
    for (const [id, brain] of this.bots) {
      const p = this.players.get(id);
      if (!p) continue;
      const inp = this.inputs.get(id);
      brain.think(p, inp, this.world, this.level, this, frozen);
    }

    // ---- step everyone ----
    const list = [];
    for (const p of this.players.values()) {
      if (p.spectator) continue;
      const inp = this.inputs.get(id0(p)) || emptyInput();
      if (frozen) {
        const held = emptyInput();
        held.yaw = inp.yaw;
        stepPlayer(p, held, this.world, this.ev);
      } else {
        stepPlayer(p, inp, this.world, this.ev);
        inp.jump = false;
        inp.dive = false;
      }
      list.push(p);
    }
    resolvePlayerCollisions(list, this.ev);

    if (!frozen) this.postPhysics(list);
    this.runPhase();
  }

  postPhysics(list) {
    const lvl = this.level;
    const killY = lvl.killY;

    for (const p of list) {
      if (p.status === ST_OUT || p.status === ST_QUALIFIED) continue;

      // tile triggers
      if (p.grounded && p.groundId >= 0 && this.tileByCollider.size) {
        const ti = this.tileByCollider.get(p.groundId);
        if (ti !== undefined && this.tileTrig[ti] === 0) {
          this.tileTrig[ti] = this.tick;
          this.pushEvent({ e: 'tile', i: ti, k: this.tick });
        }
      }

      // triggers (checkpoints / finish)
      if (p.status === ST_ALIVE) {
        for (const tg of this.world.triggers) {
          if (Math.abs(p.x - tg.p.x) > tg.h.x || Math.abs(p.z - tg.p.z) > tg.h.z) continue;
          if (p.y + K.P_HEIGHT < tg.p.y - tg.h.y || p.y > tg.p.y + tg.h.y) continue;
          if (tg.kind === 'checkpoint') {
            if (tg.idx > p.checkpoint) { p.checkpoint = tg.idx; p.progress = tg.progress; }
          } else if (tg.kind === 'finish') {
            this.qualifyPlayer(p);
          }
        }
        if (lvl.mode === 'race') p.progress = Math.max(p.progress, p.z);
      }

      // crown grab
      if (lvl.mode === 'crown' && p.status === ST_ALIVE) {
        const cp = lvl.crownPos;
        const cy = cp.y + Math.sin(this.worldTime() * cp.speed) * cp.bob;
        const dx = p.x - cp.x, dz = p.z - cp.z, dy = (p.y + K.P_HEIGHT * 0.8) - cy;
        if (dx * dx + dz * dz + dy * dy < (cp.r + K.P_RADIUS) * (cp.r + K.P_RADIUS)) {
          this.crownHolder = p.id;
          this.pushEvent({ e: 'crown', id: p.id });
          return this.endMatch(p);
        }
      }

      // fell off the world
      if (p.y < killY) {
        if (lvl.respawnMode === 'eliminate') {
          p.status = ST_OUT;
          p.place = this.contenders().filter((q) => q.status !== ST_OUT).length + 1;
          this.pushEvent({ e: 'out', id: p.id });
        } else {
          this.pushEvent({ e: 'fall', id: p.id });
          this.respawnAtCheckpoint(p);
        }
      }
    }
  }

  qualifyPlayer(p) {
    if (p.status !== ST_ALIVE) return;
    p.status = ST_QUALIFIED;
    p.place = this.finishOrder.length + 1;
    this.finishOrder.push(p.id);
    this.pushEvent({ e: 'qualify', id: p.id, place: p.place });
    const need = this.qualifyTarget;
    if (this.finishOrder.length >= need && !this.graceTick) {
      this.graceTick = this.tick + Math.round(4.0 * K.TICK_HZ);
      this.broadcastPhase({ grace: 4.0 });
    }
  }

  runPhase() {
    const now = this.tick;
    switch (this.phase) {
      case K.STATE_LOBBY: {
        if (this.humans() >= 1 && !this.countdownStarted) {
          this.countdownStarted = true;
          this.setPhase(K.STATE_COUNTDOWN, K.LOBBY_COUNTDOWN_MS);
        }
        if (this.humans() === 0) this.countdownStarted = false;
        break;
      }
      case K.STATE_COUNTDOWN: {
        if (this.humans() === 0) { this.countdownStarted = false; this.setPhase(K.STATE_LOBBY, 999999); break; }
        if (now >= this.phaseEndTick) this.startMatch();
        break;
      }
      case K.STATE_PLAYING: {
        if (now < this.introUntil) break;
        const lvl = this.level;
        const contenders = this.contenders();
        const alive = contenders.filter((p) => p.status === ST_ALIVE || p.status === ST_RESPAWN);
        const qualified = contenders.filter((p) => p.status === ST_QUALIFIED);

        if (lvl.mode === 'survive') {
          if (alive.length <= this.qualifyTarget || now >= this.roundDeadline) {
            alive.sort((a, b) => b.y - a.y);
            let rank = this.finishOrder.length;
            for (const p of alive) { p.status = ST_QUALIFIED; p.place = ++rank; this.finishOrder.push(p.id); }
            this.endRound();
          }
        } else if (lvl.mode === 'race') {
          if (alive.length === 0) this.endRound();
          else if (this.graceTick && now >= this.graceTick) this.endRound();
          else if (now >= this.roundDeadline) {
            // time's up: the furthest-along runners still advance so the bracket stays full
            const slots = this.qualifyTarget - qualified.length;
            if (slots > 0) {
              alive.sort((a, b) => b.progress - a.progress);
              for (let i = 0; i < Math.min(slots, alive.length); i++) {
                const p = alive[i];
                p.status = ST_QUALIFIED;
                p.place = this.finishOrder.length + 1;
                this.finishOrder.push(p.id);
                this.pushEvent({ e: 'qualify', id: p.id, place: p.place, late: 1 });
              }
            }
            this.endRound();
          }
        } else if (lvl.mode === 'crown') {
          if (alive.length === 1 && qualified.length === 0) this.endMatch(alive[0]);
          else if (alive.length === 0) this.endMatch(null);
          else if (now >= this.roundDeadline) {
            alive.sort((a, b) => b.y - a.y);
            this.endMatch(alive[0]);
          }
        }
        break;
      }
      case K.STATE_ROUND_END: {
        if (now >= this.phaseEndTick) this.nextRound();
        break;
      }
      case K.STATE_MATCH_END: {
        if (now >= this.phaseEndTick) this.returnToLobby();
        break;
      }
    }
  }

  // ------------------------------------------------------------------ net
  snapshotShared() {
    const arr = [];
    for (const p of this.players.values()) {
      let f = 0;
      if (p.grounded) f |= 1;
      if (p.dive === 1) f |= 2;
      if (p.tumble > 0) f |= 4;
      if (p.getUp > 0) f |= 8;
      if (p.spectator) f |= 16;
      arr.push([
        p.id,
        r2(p.x), r2(p.y), r2(p.z),
        r2(p.yaw),
        f, p.status,
        r1(p.vx), r1(p.vy), r1(p.vz),
      ]);
    }
    return { t: 's', k: this.tick, p: arr, ev: this.events.length ? this.events : undefined };
  }

  selfState(p) {
    return [
      p.lastSeq, p.x, p.y, p.z, p.vx, p.vy, p.vz, p.yaw,
      p.grounded ? 1 : 0, p.groundId, p.dive, p.diveT, p.tumble, p.getUp,
      p.coyote, p.jumpBuf, p.diveCd, p.status, p.respawnT, p.checkpoint,
    ];
  }

  rosterEntry(p) {
    return { id: p.id, name: p.name, color: p.color, bot: p.bot, status: p.status, place: p.place, spec: !!p.spectator };
  }

  roster() { return [...this.players.values()].map((p) => this.rosterEntry(p)); }
}

function id0(p) { return p.id; }
const r2 = (v) => Math.round(v * 100) / 100;
const r1 = (v) => Math.round(v * 10) / 10;

// Headless full-match simulation. Verifies every round resolves and a winner emerges,
// and reports how fast the server sim runs relative to realtime.

import { Room } from '../server/room.js';
import * as K from '../shared/constants.js';

const RUNS = Number(process.env.RUNS || 3);
let allOk = true;

for (let run = 0; run < RUNS; run++) {
  const log = [];
  const room = new Room((m) => {
    if (m.t === 'phase') {
      log.push(`ph${m.ph} ${m.level} r${m.roundIdx}${m.results?.qualified ? ` adv:${m.results.qualified.length}` : ''}`);
    }
  });
  room.ev = {};
  for (let i = 0; i < 7; i++) room.addBot();
  room.startMatch();

  const t0 = Date.now();
  let ticks = 0;
  while (ticks++ < 30 * 900) {
    room.update();
    if (room.phase === K.STATE_MATCH_END) break;
  }
  const ms = Date.now() - t0;
  const winner = room.players.get(room.winnerId);
  const rounds = new Set(log.map((l) => l.split(' ')[1]));
  const ok = !!winner && rounds.has('gauntlet') && rounds.has('hex') && rounds.has('crown');
  if (!ok) allOk = false;

  console.log(`${ok ? '✅' : '❌'} run ${run + 1}: ${[...rounds].join(' → ')} · winner ${winner ? winner.name : 'NONE'} · ` +
    `${(ticks / 30).toFixed(0)}s of play simulated in ${ms}ms (${Math.round(ticks / (ms / 1000)).toLocaleString()} ticks/s, ` +
    `${Math.round(ticks / (ms / 1000) / 30)}× realtime)`);
  console.log(`   ${log.join(' | ')}`);
}

console.log(allOk ? '\nAll matches completed all three rounds with a winner.' : '\nSome matches failed.');
process.exit(allOk ? 0 : 1);

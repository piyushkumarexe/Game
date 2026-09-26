// One command to run the game server + Vite with HMR side by side.
import { spawn } from 'node:child_process';

const procs = [];
function run(name, cmd, args, color) {
  const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], shell: process.platform === 'win32' });
  const tag = `\x1b[${color}m[${name}]\x1b[0m `;
  const pipe = (stream) => stream.on('data', (d) => {
    process.stdout.write(String(d).replace(/^/gm, tag).replace(/\n$/, '\n'));
  });
  pipe(p.stdout); pipe(p.stderr);
  procs.push(p);
  return p;
}

run('server', 'node', ['server/index.js'], '36');
run('client', 'npx', ['vite'], '35');

const bye = () => { for (const p of procs) p.kill('SIGTERM'); process.exit(0); };
process.on('SIGINT', bye);
process.on('SIGTERM', bye);

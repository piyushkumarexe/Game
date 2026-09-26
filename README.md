# 🎪 Tumble Royale

A **3D multiplayer party battle royale** in the browser. Up to 24 players stumble, dive and
bodycheck each other through three chaotic rounds until one bean takes the crown.
Runs on phones and PCs, cross-play, no download, no account.

> **Why this genre?** It was picked after surveying what's actually trending in multiplayer
> right now. The obstacle-course party battle royale (Stumble Guys / Fall Guys / Just Fall)
> is consistently ranked the top "anyone can play" format: near-zero learning curve, low-end
> device friendly, hilarious to lose, and equally popular with all ages and genders. No guns,
> no meta to memorise — you understand it in 30 seconds.

---

## Play

```bash
npm install
npm start          # builds the client and serves the game on http://localhost:8080
```

Open the URL, pick a name and a colour, hit **PLAY**. Share the same URL with friends —
everyone who opens it lands in the same room. If you're alone, the server fills the lobby
with bots so you always get a real match.

### Controls

|              | Move          | Jump    | Dive           | Look        |
| ------------ | ------------- | ------- | -------------- | ----------- |
| **PC**       | `W A S D`     | `Space` | `Shift` / `E`  | Mouse       |
| **Phone**    | Left stick    | JUMP    | DIVE           | Drag right  |

**Dive** is the good stuff: it lunges you forward through gaps *and* bowls over anyone you
hit. It also leaves you face-down for a moment, so time it.

---

## The three rounds

| # | Round | Mode | Goal |
|---|-------|------|------|
| 1 | **Sky Gauntlet** | Race | A 260 m obstacle course — spinning bars, swinging hammers, sliding ferries over the void, bumper fields, reversing conveyor belts, rolling logs, a bounce-pad launch and an ice slide to the finish. The top 60 % qualify. |
| 2 | **Hex Dash** | Survival | Three stacked layers of hexagons. Every tile you touch glows, shakes, then drops into the lava. Half the players survive. |
| 3 | **Crown Clash** | Final | Climb a tower of orbiting discs past sweeping hazard arms. First to touch the crown wins everything. |

Falling in a race puts you back at your last checkpoint. Falling in Hex Dash is fatal.

---

## Architecture

This is a real authoritative-server game, not a peer-to-peer toy.

```
shared/          ← identical code runs on BOTH server and client
  constants.js     tuning values; if these drift, prediction desyncs
  math.js          rotation basis (matches THREE's 'YXZ' Euler order exactly)
  collision.js     analytic capsule vs oriented-box / cylinder / sphere
  world.js         collider set + deterministic time-driven motion + grid broadphase
  sim.js           the character controller — one tick of movement
  levels.js        all four arenas as pure data

server/
  index.js         express + ws on one port, 30 Hz fixed loop
  room.js          match state machine, spawns, triggers, qualification
  bots.js          bot brains that drive the same input struct a human does

src/               ← browser client
  main.js          prediction loop, reconciliation, camera, event routing
  net.js           snapshot buffering + remote interpolation
  input.js         keyboard/mouse and dual-thumb touch
  audio.js         synthesised SFX (zero assets)
  render/          renderer, PBR materials, level meshes, characters, particles
  ui/              HUD and styling
```

### Netcode

* **Authoritative server** at a fixed 30 Hz. Clients send intent only — never positions.
* **Client-side prediction**: the browser runs `shared/sim.js` locally on your input
  immediately, so movement has zero input latency.
* **Reconciliation**: every snapshot carries your authoritative state plus the last input
  sequence the server consumed. The client rewinds to that state and replays every
  unacknowledged input. Because both sides run the *same* deterministic code with the same
  tick-derived world time, the replay lands on the same answer.
* **Render smoothing**: the rare correction that does occur is applied to physics instantly
  but bled off the *visual* position over a few frames, so you never see a teleport.
* **Entity interpolation**: remote players render ~110 ms in the past between snapshots,
  which hides jitter and packet loss completely.
* **Deterministic moving geometry**: every platform, spinner and pendulum is a pure function
  of the tick number, so the client predicts *onto moving platforms* correctly — including
  being carried and rotated by them.

Measured against a live server (`npm run test:predict`):

```
error p50 : 0.0000 m     ← prediction is bit-exact the vast majority of ticks
error p95 : 0.27 m       ← contact frames the client can't see (server-side body shoves)
error p99 : 0.72 m
```

Bandwidth is **~16 KB/s down per client** with a full lobby, and the server holds a flat
30 ticks/s.

### Rendering

* Physically based materials lit by a real **image-based environment** — the Preetham sky is
  rendered into a PMREM probe per level, so metals and clearcoat reflect the actual sky.
* ACES filmic tone mapping, soft PCF shadows with **texel-snapped cascades** (no crawling
  edges), unreal bloom, SMAA, and a custom grade pass doing vignette, chromatic aberration,
  saturation and hit-flashes.
* Characters are procedural: capsule body, googly eyes that track the camera, blinking,
  squash-and-stretch on every landing, and separate run / air / dive / tumble / celebrate poses.
* Hex tiles are a single `InstancedMesh` per layer, animated (heat-up, wobble, tumble away)
  entirely through instance matrices.
* Three quality tiers auto-detected from device capability — low-end phones drop bloom, SMAA
  and shadow resolution to hold 60 fps.

### Bots

Bots exist so a solo player never sees an empty lobby. They are **not** scripted paths —
they run the same physics as you and can lose:

* three-range ledge probing (walk / commit to a jump / wait at the edge for a ferry),
* hazard timing — they measure the surface velocity of spinners and hammers and wait for the
  swing to pass,
* per-bot personality: skill, speed, jumpiness and how much they love diving,
* mode-specific goals (follow the race line, hunt untouched hex tiles, ride discs to the crown).

---

## Scripts

| Command | What it does |
| --- | --- |
| `npm start` | Build the client, then serve game + websockets on port 8080 |
| `npm run server` | Serve an existing build (skip the rebuild) |
| `npm run dev` | Vite dev server with HMR on 5173, proxying `/ws` to the game server |
| `npm run build` | Production client build into `dist/` |
| `npm run test:sim` | Headless full match — verifies all three rounds resolve to a winner |
| `npm run test:client` | Builds every level, character and particle system without a GPU |
| `npm run test:predict` | Joins a live server and measures real prediction error |

---

## Continuous integration

GitHub Actions builds and verifies the game on every push.

**`.github/workflows/ci.yml` — Build & Test** (push, PR, or manual)

* builds the client on Node 20 and 22,
* asserts `dist/` exists and that every asset `index.html` references is really on disk,
* runs the headless level/character/FX build test and 5 full match simulations,
* boots the actual server, checks static serving and the SPA fallback, then **plays
  against it** and fails the build if prediction drifts (`p50 ≥ 0.02 m` means the client
  and server sims have diverged — the bug class that makes multiplayer feel like rubber),
* posts a bundle size table to the run summary and uploads the playable `dist/` as an
  artifact you can download from the run page.

**`.github/workflows/release.yml` — Release** (on a `v*` tag, or manual)

Packages a self-contained zip — `dist/` + `server/` + `shared/` and nothing else. It drops
three.js and the build tooling from the shipped manifest (three is already inside the
bundle) and regenerates the lockfile, so a self-host install is **4.4 MB instead of ~70 MB**.
CI then unzips it, installs it clean and boots it before publishing, so a release can never
be a bundle that doesn't run.

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Anyone can then download the zip and run `npm ci --omit=dev && npm start`.

## Tuning

Almost all feel lives in `shared/constants.js` — run speed, jump height, gravity, dive power,
knockback, coyote time, input buffering. Change a value there and **both** the server and the
client pick it up, so prediction stays in sync automatically.

Arena layout is `shared/levels.js`. The builder is small: `b.box()`, `b.cyl()`, `b.sphere()`,
each optionally given a `motion` descriptor (`spin`, `path`, `loop`, `orbit`, `pend`, `bob`),
a `surface` (bouncy, conveyor, slippery) and a `knock` multiplier. Add a collider and it is
automatically simulated, rendered, shadowed and navigated by bots.

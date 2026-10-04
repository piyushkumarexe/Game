# Dustbound RV

A mobile-first, physics-flavoured road-trip game for the web. Guide a tired old RV across ravines, pine passes, boulder fields, and one final ridge before sunset.

> Dustbound RV is an original game with original procedural/vector art. It takes inspiration from the *chaotic road-trip* genre, but does not copy another game's code, branding, models, textures, audio, or level design.

## Play

The production build is configured for GitHub Pages at:

**https://piyushkumarexe.github.io/Game/**

For the best experience, turn a phone sideways and add the game to the home screen. It is an installable PWA and works offline after its first load.

### Controls

| Touch | Keyboard | Action |
|---|---|---|
| **Drive** | `W` / `↑` | Accelerate |
| **Brake** | `S` / `↓` | Brake and reverse |
| **Tilt** | `A D` / `← →` | Balance the RV in the air |
| **Cable** | `Space` | Pull out of a bad climb |
| **Patch** | Touch button | Spend two parts to repair |
| Pause | `P` | Pause the run |

Collect fuel cans and spare parts, stop at both trail camps, and manage the rig's health. Hard landings and boulders damage the RV.

## Features

- Responsive touch controls designed for landscape phones
- Custom suspension, airborne rotation, terrain, and vehicle handling
- A 14.4 km handcrafted procedural route with three distinct biomes
- Fuel, damage, repair, recovery-cable, checkpoint, and best-run systems
- Dynamic sky, parallax scenery, dust, screen shake, haptics, and synthesized Web Audio
- No downloaded or copyrighted game assets — all visuals are generated from Phaser primitives and original SVGs
- Installable, offline-capable PWA
- Automated GitHub Actions build and GitHub Pages deployment

## Local development

Requirements: Node.js 22 or newer.

```bash
npm install
npm run dev
```

Open the URL shown by Vite. To verify the production bundle:

```bash
npm run build
npm run preview
```

## Stack

- [Phaser 4](https://phaser.io/) — game rendering and input
- [Vite](https://vite.dev/) — development and production bundling
- [TypeScript](https://www.typescriptlang.org/) — strict game code
- [vite-plugin-pwa](https://vite-pwa-org.netlify.app/) — manifest, service worker, and offline cache

Dependency versions are pinned in `package.json` and `package-lock.json` for reproducible GitHub builds.

## Deployment

- `.github/workflows/ci.yml` type-checks and builds every push and pull request.
- `.github/workflows/deploy-pages.yml` publishes `dist/` to GitHub Pages after changes reach `main`, and also supports manual runs.

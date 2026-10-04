# Dustbound Expeditions

A true 3D, first-/third-person single-player mobile physics adventure built with Godot 4.7.2.

Version 0.6 is a **single-player stability and rendering rebuild** with an original map, physical RV, missions, recovery tools, hazards, viewport-level multi-touch controls, and Android/iOS export configuration. Multiplayer and proximity voice are deliberately dormant until the core phone experience is stable.

> This is an original game in the cooperative road-trip genre. It does not copy or redistribute another game's protected maps, textures, models, audio, characters, branding, or code.

## The expedition

You leave Redmesa Trail Camp in one unreliable RV. Pack the supplies and find Route 17 before the rig comes apart.

The handcrafted route contains:

1. **Redmesa Trail Camp** — load three supply crates and start the RV.
2. **Dry Creek Overlook** — learn the weight and manual gearbox.
3. **Broken Span** — carry and secure two planks across a ravine.
4. **Lantern Post Garage** — repair the frame and collect fuel.
5. **Mudwater Bog** — attach a front or rear cable and winch through.
6. **Last Light Pass** — climb switchbacks through wildlife and rockfall.
7. **Route 17 Exit** — get the RV and crew home.

## Implemented systems

### 3D vehicle

- Four-wheel `VehicleBody3D` RV with suspension, steering and rear-wheel traction
- Low-center-of-mass stability tuning, parked braking, velocity guards and a sane 115 km/h ceiling
- Reverse, neutral and five forward gear ratios
- Fuel, layered health, impact damage and performance degradation
- Breakable/damage-reactive exterior details
- Synthesized positional engine audio

### Single-player stability release

- One local driver with networking and microphone services disabled
- A unified viewport-level touch router for movement, look and every action button
- End-to-end automated touch tests that physically move, rotate and jump the player
- Terrain-aware camp spawning plus a guaranteed physical safety surface
- Automatic on-foot recovery from invalid/falling states
- Immediate RV recovery from out-of-bounds or prolonged upside-down states
- Initial supply objective gates access to the driver seat
- Multiplayer code is retained only for a later, separately tested release

### Recovery and missions

- Independent front and rear physics winches
- Environmental cable anchors and progressive cable tension
- Carryable bridge planks and placement sockets
- Supply crates, fuel cans and a repair garage
- Checkpoint recovery for the RV
- Eight-step single-player mission chain
- Ridge-boar AI and a triggered physics rockfall

### Mobile presentation

- Strict landscape launch on Android and iOS, with an expanding widescreen viewport
- Left movement/driving stick plus direct right-side swipe free-look (no camera joystick)
- Collision-aware **VIEW 1P / 3P** switch for walking and driving
- Context-sensitive touch actions for interaction, sprint, jump, gears and both winches
- Mission, speed, gear, fuel and RV-integrity HUD
- Two-sided, occlusion-safe Android terrain with baked color variation, a flattened trail camp, and a canyon-basin fail-safe
- A 512×512 seamless multi-scale ground texture with far less visible repetition
- Textured and animated Quaternius CC0 survivor with idle, walk, run and jump locomotion
- Original modeled RV coach, cockpit, signs and supply props combined with selected Kenney CC0 environment models
- Painted terrain/model textures and a live 3D campsite home screen
- Original generated app/key artwork, with no remote runtime assets

## Controls

| Action | Touch | Keyboard/gamepad |
|---|---|---|
| Walk / drive | Left stick | `WASD` / left stick |
| Look | Swipe/drag the right side | Mouse / right stick |
| First-/third-person view | **VIEW 1P / 3P** | `C` |
| Interact / enter / exit | **USE** | `E` |
| Jump | **JUMP** | `Space` |
| Sprint | **SPRINT** | `Shift` |
| Shift down / up | **GEAR − / +** | `Z / X` |
| Front cable | **FRONT CABLE** | `Q` |
| Rear cable | **REAR CABLE** | `R` |

## Engine

- Godot **4.7.2 stable**
- GDScript only; no third-party runtime plugins
- Android 7.0+ / arm64 export preset
- iOS 15+ Xcode export preset
- Multiplayer/voice implementation retained but disabled in the 0.6 stability UI and runtime

Selected tree, rock, campsite and supply GLBs come from Kenney's CC0 asset packs. The animated survivor comes from Quaternius' CC0 Zombie Apocalypse Kit. Provenance is documented under [`assets/third_party`](assets/third_party). The RV, map and game-specific assets remain original.

See [`docs/game-research.md`](docs/game-research.md) for the researched mechanic breakdown and the original-design boundary.

## Run locally

Install Godot 4.7.2 and open `project.godot`, or run:

```bash
godot --editor --path .
```

The 0.6 menu intentionally exposes only **START SINGLE-PLAYER EXPEDITION**.

## GitHub mobile builds

`.github/workflows/ci.yml`:

1. imports the project and validates every GDScript;
2. launches the actual expedition in a windowed OpenGL session, verifies its local player/current camera/RV/3D mesh count and saves a world-only render proof;
3. exports a debug-signed Android APK and verifies its manifest is locked to landscape;
4. exports an unsigned, build-ready iOS Xcode project archive.

CI intentionally uses Godot's project-only iOS export so no Apple credentials are stored in the repository. Open the artifact in Xcode and select your Apple Developer team; a certificate and provisioning profile are required before installation on a physical iPhone or TestFlight submission.

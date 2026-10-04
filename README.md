# Dustbound Expeditions

A true 3D, first-/third-person, 1–4 player mobile co-op physics adventure built with Godot 4.7.2.

This branch replaces the earlier 2D prototype. The current project is a playable **3D vertical slice** with an original map, physical RV, multiplayer, proximity voice, missions, recovery tools, hazards, native touch controls, and Android/iOS export configuration.

> This is an original game in the cooperative road-trip genre. It does not copy or redistribute another game's protected maps, textures, models, audio, characters, branding, or code.

## The expedition

Your crew leaves Redmesa Trail Camp in one shared, unreliable RV. Pack the supplies, assign roles, and find Route 17 before the rig comes apart.

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
- Server-authoritative transform and status synchronization

### Co-op

- 1–4 players using Godot ENet multiplayer
- Host and join by LAN/direct IP on UDP port `24817`
- Named crew roster and Driver/Mechanic/Scout/Navigator roles
- Replicated first-person players, RV, wildlife, interactions and progress
- Positional proximity voice chat with mobile microphone permission
- Shared missions and checkpoints

Direct-IP internet games require the host to forward UDP `24817`. A production release should add a relay/lobby service for zero-configuration internet matchmaking.

### Recovery and missions

- Independent front and rear physics winches
- Environmental cable anchors and progressive cable tension
- Carryable bridge planks and networked placement sockets
- Supply crates, fuel cans and a repair garage
- Checkpoint recovery for the RV
- Eight-step cooperative mission chain
- Ridge-boar AI and a triggered physics rockfall

### Mobile presentation

- Strict landscape launch on Android and iOS, with an expanding widescreen viewport
- Left movement/driving stick plus direct right-side swipe free-look (no camera joystick)
- Collision-aware **VIEW 1P / 3P** switch for walking and driving
- Context-sensitive touch actions for interaction, sprint, jump, gears and both winches
- Mission, crew, speed, gear, fuel and RV-integrity HUD
- Android-safe `StandardMaterial3D` terrain with baked color variation, plus reduced mobile terrain density
- Original cockpit, first-person hands, signs and supply models combined with selected Kenney CC0 vehicle, crew and nature models
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
- Godot ENet networking and AudioEffectCapture voice pipeline

Selected vehicle, crew, tree, rock and campsite GLBs come from Kenney's CC0 asset packs. Their provenance and license are documented in [`assets/third_party/kenney/LICENSE.md`](assets/third_party/kenney/LICENSE.md).

See [`docs/game-research.md`](docs/game-research.md) for the researched mechanic breakdown and the original-design boundary.

## Run locally

Install Godot 4.7.2 and open `project.godot`, or run:

```bash
godot --editor --path .
```

For two local peers, start one instance with **HOST CREW**, then join `127.0.0.1` from the second instance.

## GitHub mobile builds

`.github/workflows/ci.yml`:

1. imports the project and validates every GDScript;
2. launches the actual expedition in a windowed OpenGL session, verifies its local player/current camera/RV/3D mesh count and saves a world-only render proof;
3. exports a debug-signed Android APK and verifies its manifest is locked to landscape;
4. exports an unsigned, build-ready iOS Xcode project archive.

CI intentionally uses Godot's project-only iOS export so no Apple credentials are stored in the repository. Open the artifact in Xcode and select your Apple Developer team; a certificate and provisioning profile are required before installation on a physical iPhone or TestFlight submission.

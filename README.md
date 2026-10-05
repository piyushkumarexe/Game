# Dustbound Expeditions

A true 3D, first-/third-person single-player mobile physics adventure built with Godot 4.7.2.

Version 0.10 is an **in-development physical-device correction release** for the RV shell/cockpit, suspension clearance, animated mechanisms, rounded crew character, and forest density. It is not stable until fresh Android device screenshots pass the visual and physics checklist. Multiplayer and proximity voice remain deliberately dormant until the core phone experience is stable.

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

- Six-wheel tandem-axle `VehicleBody3D` motorhome with suspension, front steering and rear-bogie traction
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
- Bright, two-sided, occlusion-safe Android forest terrain with baked meadow/cliff/trail variation and a canyon-basin fail-safe
- Neutral-detail terrain and dedicated gravel textures that preserve readable color instead of multiplying the world almost black
- A brighter live 3D campsite home screen and deliberately clustered opening forest
- Fully draggable, persistent mobile control layout with adjustable size, opacity, swipe sensitivity, and FAST/BALANCED/HIGH quality profiles
- Context-sensitive mobile BRAKE plus movement, use, sprint, jump, view, gears, and twin-winch controls
- Professionally modeled and skinned Quaternius CC0 crew base/Ranger outfit with normal facial spacing, original cap, sunglasses and padded-vest styling, named-bone idle/walk/run/jump/landing motion, and travel-facing rotation
- Karol Miklas' professionally shaped CC-BY vintage GMC motorhome hero mesh with curved coachwork, PBR paint/glazing, fascia, lamps, mirrors, trim, roof rack and six separated suspension-driven tire/rim assemblies
- Genuinely opened passenger doorway with three exterior steps, unobstructed split shell collision, and a connected modeled cockpit/living interior containing movable steering, physical gear lever, dashboard, gauges, seats, refrigerator, kitchen, dinette, storage and bed—driver-eye view uses world geometry rather than an overlay
- Layered near/mid/far forest with HIGH-only 5.8k-triangle EZ-Tree conifers, textured Quaternius CC0 undergrowth/rocks, and mobile-batched Kenney distance scenery
- Centered non-overhead chase camera plus separate modeled-cockpit render validation
- Reduced shadow resolution, quality-scaled scenery/shadows, a batched distant forest, batched RV materials, and throttled vehicle HUD updates for mobile performance
- Coherent lit forest/campsite palette replacing cyan trees, pink canvas, and white unlit stones
- Collision-aware deterministic walking around the RV, tent, fire ring, and camp sign
- Static parking state that prevents the unoccupied RV from settling or tipping before the player enters it
- Original generated app/key artwork, with no remote runtime assets

## Controls

| Action | Touch | Keyboard/gamepad |
|---|---|---|
| Walk / drive | Left stick | `WASD` / left stick |
| Look | Swipe/drag the right side | Mouse / right stick |
| First-/third-person view | **VIEW 1P / 3P** | `C` / gamepad Y |
| Interact / enter / exit | **USE** | `E` / gamepad X |
| Jump | **JUMP** | `Space` / gamepad A |
| Sprint | **SPRINT** | `Shift` / left-stick click |
| Shift down / up | **GEAR − / +** | `Z / X` / left/right shoulder |
| Brake / handbrake | **BRAKE** | `Space` / gamepad B |
| Front cable | **FRONT CABLE** | `Q` / D-pad up |
| Rear cable | **REAR CABLE** | `R` / D-pad down |
| Customize layout | **LAYOUT**, then drag/save | Main-menu **CONTROLS & PERFORMANCE** |

## Engine

- Godot **4.7.2 stable**
- GDScript only; no third-party runtime plugins
- Android 7.0+ / arm64 export preset
- iOS 15+ Xcode export preset
- Multiplayer/voice implementation retained but disabled in the 0.10 correction UI and runtime

Selected tree, rock, campsite and supply GLBs come from Kenney's CC0 asset packs. Quaternius' CC0 work supplies the textured nature layer and the professionally rigged crew base/Ranger clothing. HIGH also uses deterministic mobile-detail conifer geometry generated with Daniel Greenheck's MIT-licensed EZ-Tree 1.1.0. The hero exterior is based on Karol Miklas' “FREE GMC Motorhome reimagined low poly” under CC-BY-4.0. Dustbound's connected interior, functional doorway/steps, character accessories, map, mechanisms and game-specific assets are original. Exact provenance, modifications and preserved license notices are documented under [`assets/third_party`](assets/third_party).

See [`docs/game-research.md`](docs/game-research.md) for the researched mechanic breakdown and the original-design boundary.

## Run locally

Install Godot 4.7.2 and open `project.godot`, or run:

```bash
godot --editor --path .
```

The 0.10 menu intentionally exposes only **START SINGLE-PLAYER EXPEDITION** plus local **CONTROLS & PERFORMANCE** settings.

## GitHub mobile builds

`.github/workflows/ci.yml`:

1. imports the project and validates every GDScript;
2. launches the actual expedition in a windowed OpenGL session, drives the mobile controls, verifies locomotion/facing, the detailed RV and both cameras, then saves full-coach chase, open-doorway, modeled-cockpit and front-facing character proofs;
3. exports a debug-signed Android APK and verifies its manifest is locked to landscape;
4. exports an unsigned, build-ready iOS Xcode project archive.

CI intentionally uses Godot's project-only iOS export so no Apple credentials are stored in the repository. Open the artifact in Xcode and select your Apple Developer team; a certificate and provisioning profile are required before installation on a physical iPhone or TestFlight submission.

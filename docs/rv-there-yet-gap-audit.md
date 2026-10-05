# RV There Yet-style target and major gap audit

Audit date: 5 October 2026

## Product direction (locked)

Dustbound Expeditions should become an **original Android/iOS-first game in the same systemic co-op RV-adventure genre as _RV There Yet?_**: one shared, physically simulated RV; 1–4 first-person players; touch-first vehicle operation; physical tools/cargo; layered damage and repair; player-placed winches/planks; proximity communication; and a hand-authored journey whose obstacles produce emergent teamwork and comedy. Keyboard bindings are diagnostic scaffolding only, never a product priority or player-facing dependency.

This is a mechanical and quality target, not a cloning instruction. Keep Dustbound's own name, Redmesa setting, Route 17, map layout, story, characters, UI, models, textures, audio and code. Do not copy protected content from the reference game.

## Executive assessment

The repository is currently a **single-player mobile vertical prototype**, not yet a systemic co-op game. It has an impressive amount of presentation scaffolding and a playable route on paper, but many headline mechanics are scripted approximations. The largest risk is investing further in visuals before replacing those approximations with a robust interaction/physics/network foundation.

## P0 — blockers to the target experience

### 1. Multiplayer is deliberately disabled

- The menu exposes only single-player.
- README calls multiplayer and microphone services dormant.
- The core appeal of the target is several players sharing one failure-prone vehicle.
- Existing ENet code is not evidence of a production-ready co-op loop; it has no demonstrated reconnect, host migration, latency compensation, interest management, authority transfer, or physical-object replication test coverage.

**Required:** restore a two-player host/join slice early and validate driver + passenger + one replicated loose object + one replicated winch before adding more content.

### 2. On-foot movement bypasses real character physics

`scripts/player/player_controller.gd` directly writes `global_position`, obtains height from a custom terrain function and uses hand-written RV/door constraints. It does not use `move_and_slide()` for normal movement.

Consequences:

- World collisions are not authoritative for the player.
- New props, movable objects, bridges and dynamic hazards will need custom constraint code.
- Standing and walking inside a moving RV cannot behave naturally.
- Slopes, steps, pushing, falling objects and multiplayer correction will be inconsistent.

**Required:** use a real CharacterBody3D movement/collision controller, moving-platform velocity and robust step/slope handling. Terrain-height recovery should be an emergency fallback only.

### 3. The RV stops being physical when unoccupied — first correction implemented

The original RV began frozen and exiting snapped it upright, zeroed velocity and froze it again. The first correction now keeps the rig continuously simulated after ignition, parks with brakes, preserves exit momentum and carries cabin passengers through the RV's transform delta. Pre-departure staging remains frozen for spawn stability. This still needs physical-device and multiplayer validation.

**Remaining:** validate suspension stability, moving passengers, exits at speed and checkpoint restoration on physical devices and with network clients.

### 4. Core physical interactions are scripted pickups — foundation in progress

Supply crates and planks have now been converted to rigid-body `PhysicsCargo` objects with pickup, drop, inherited momentum, RV stowage and physical bridge delivery. Fuel and repair remain instant scripted interactions, and the new cargo path still needs multiplayer authority/replication and device validation.

The remaining legacy interaction layer still has limitations:

- Fuel instantly adds a number and vanishes.
- Repair station instantly adds health.
- Planks still resolve into predetermined bridge geometry at fixed sockets.
- Cargo has no throw strength, two-handed weight behavior or multiplayer ownership yet.

**Required:** extend the framework with network authority, throwing, heavy items, free plank placement, storage slots and stable client-side moving-vehicle behavior.

### 5. Player-operated winches — foundation implemented

On-foot players can now aim the reticle at a marked tree/post and independently attach or detach the front or rear cable. Attachment begins with slack instead of automatically pulling. Any nearby crew member can hold REEL IN/OUT; cable length changes deliberately, tension is shown on the HUD, force is applied at the correct front/rear hook, and excessive shock load snaps the line rather than launching the RV. Drivers retain a nearest-anchor fallback for mobile accessibility. Cable length, tension and anchor live in the replicated winch dictionaries.

**Remaining:** the controller/hook are not carryable physical objects, attachment RPC/server validation is incomplete, cables cannot wrap around geometry, portable poles are fixed world anchors, and multiple players currently share one reel command rather than explicit remote ownership.

### 6. Vehicle component damage — foundation implemented

The RV now tracks exterior/body, frame, engine and all six wheels independently. Impacts distribute deterministic damage across systems; frame, engine and average tire condition independently reduce acceleration/steering; critical body/frame/engine failure stops the run; checkpoint recovery restores only minimum serviceable values. The HUD reports component condition and four distinct garage interactions represent hammer, welder, motor oil and power drill repairs. Component state is included in RV network snapshots.

Repair tools are now real carryable rigid bodies: hammer, welder, oil cans and power drill. Matching service points reject the wrong tool, durable tools remain carried after use, and oil is physically consumed. All six wheels have independent condition and installed state. A critically damaged wheel visibly disappears, loses its suspension/support fallback and traction, persists as missing through checkpoint recovery, and requires a modeled physical spare tire carried to the tire station. Replacement state is included in network snapshots.

A low-integrity engine can now ignite. Fire grows over time, damages engine/body and eventually frame, stops the engine on critical failure, renders mobile-safe engine-bay flames/light, reports a HUD percentage and replicates in RV snapshots. Physical extinguishers spawn at camp/garage, have five finite bursts and must be carried near the RV and activated with the dedicated tool control.

**Remaining:** freeform repair targeting/animations are not implemented; individual wheel-bolt interaction is abstracted into drill condition repair; removed tires do not yet spawn as detached debris; panels are not persistent detached rigid bodies; fire has no smoke propagation or audio; tools still need authoritative multiplayer ownership and runtime/device validation.

### 7. Manual drivetrain — foundation implemented

The driver now enters with the engine off and neutral selected. Ignition is a deliberate input; starting in gear requires the clutch. Reverse, neutral and five forward gears are clutch-gated; clutchless shifts grind and damage the engine; releasing the clutch at a standstill without throttle stalls the engine. RPM responds to throttle, road speed, gear and clutch coupling, drives synthesized engine pitch, appears on the HUD and is included in network snapshots. Touch, keyboard and gamepad controls now expose ignition and clutch.

**Remaining:** replace the simplified force multiplier with a proper torque curve and differential model, add engine braking and progressive analog clutch bite, animate pedals/ignition, and provide optional auto-clutch/accessibility assists for mobile.

## P1 — major quality and architecture problems

### 8. Almost the entire game is constructed in code

`scenes/main.tscn` is only a bootstrap, while `expedition_world.gd` is over 1,000 lines, `rv_controller.gd` about 750, and `main.gd` about 740. World geometry, UI and the RV are assembled procedurally in large scripts.

Consequences:

- Visual iteration in the Godot editor is difficult.
- Designers cannot author routes and encounters safely.
- Merge conflicts and regressions concentrate in a few files.
- Automated tests are mixed into application/menu code.

**Required:** split into authored scenes/resources: RV, wheel, interior, player, item, tool, checkpoint, hazard, route segment, HUD and menus. Move tuning into typed Resources. Move smoke tests to a separate test harness.

### 9. The current map is a short checklist, not a systemic journey

Only four world checkpoints are created. The mission chain gates a predetermined sequence: three crates, engine, checkpoint, two socketed planks, repair, winch, finish. This limits alternate solutions, scouting and replayability.

**Required:** obstacle sandboxes with multiple anchor points and routes, optional supply locations, meaningful consequences, recovery spaces and 8–12 escalating route beats for the first production map.

### 10. Moving RV interior is mostly presentation

The project contains a connected-looking interior and traversable doorway, but normal play teleports the driver to a seat transform and freezes the RV without a driver. There is no proven capability for passengers to walk, carry cargo, repair or communicate inside a moving vehicle.

**Required:** validate moving-platform passenger locomotion, seat interactions, interior collision, loose cargo containment, doors under motion and network synchronization.

### 11. Networking trust and synchronization are incomplete

The retained code sends vehicle transforms and dictionaries frequently and player transforms directly, but lacks a complete server-validated interaction model. Progress state is global, while carried item state and many physical interactions are not fully replicated. Voice sends raw 12 kHz PCM-like packets without a real voice codec, jitter buffer, VAD, mute/device controls or permission UX.

**Required:** define authority per actor, use snapshot interpolation/prediction, validate every interaction server-side, replicate item and component states, and use a production voice solution/codec with platform permissions and moderation controls.

### 12. Vehicle recovery masks physics faults

The RV has aggressive stabilization, speed caps, hidden wheel contact cylinders, terrain springs/fallback behavior, automatic upside-down recovery and exit snapping. Some safeguards are suitable for mobile, but together they can make handling feel artificial and hide collision/suspension defects.

**Required:** establish measurable handling targets, remove overlapping contact hacks where possible, test slopes/curbs/rocks at fixed masses and use recovery as an explicit player/checkpoint action.

### 13. No automated gameplay test suite independent of screenshots

The project embeds a long smoke test in `main.gd`, but there are no unit/integration tests for mission transitions, damage components, item ownership, network joins, authority, checkpoint restoration, winch tension or save/load. The current environment also does not have a Godot executable available, so this audit could not execute the project locally.

**Required:** headless test scenes/scripts and deterministic physics scenarios, plus physical-device performance tests.

## P2 — missing content and polish

- No player health, poison, revive or teammate rescue loop.
- Wildlife is basic and does not form a broader survival ecosystem.
- No cooking/food/medical supply loop.
- No physical map/navigation role.
- No cassette/lore collectible framework or substantial environmental narrative.
- No cosmetics/progression loop.
- No full inventory/storage organization gameplay.
- No weather/time/environment-state system.
- Limited environmental audio and music identity.
- No save-slot/resume flow for a long expedition.
- No accessibility coverage beyond control layout and quality settings.
- No demonstrated low/mid/high Android profiling despite a mobile-first target.

## Recommended build order

1. **Physics foundation:** continuously simulated RV, real character collisions and moving-interior passenger test.
2. **Physical item foundation:** grab/drop/store/throw and network ownership.
3. **Two-player vertical slice:** host/join, one driver, one passenger, one loose crate.
4. **Real winch:** manual hook placement and reel controls.
5. **Component damage/tools:** body, frame, engine and individual wheels.
6. **Driving depth:** ignition, clutch, RPM, stall and accessible mobile assists.
7. **Systemic obstacle slice:** one ravine with at least three valid solutions.
8. **Checkpoint/save/recovery:** restore RV, players, item inventory and component state.
9. **Content production:** expand Redmesa into escalating route segments.
10. **Survival, narrative and polish:** wildlife, medical items, cooking, tapes, cosmetics, weather and audio.

## Definition of a credible next milestone

A host and one client can enter the same build. Both can walk with real collision in and around a continuously simulated RV. One drives using ignition, clutch and gears while the other moves inside, carries a replicated crate and manually operates a front winch. The RV can suffer wheel and engine damage, each repaired with a distinct physical tool. Both players reach and restore from one checkpoint without state divergence.

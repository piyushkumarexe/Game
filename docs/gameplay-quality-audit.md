# Gameplay and presentation audit

This checklist is the release gate for the 0.9 line. A green export is necessary but is not treated as proof of visual or physical-device quality.

## RV presentation

- Replaced the rejected single-mesh box camper and detached dashboard overlay with one original Class C RV scene containing a tapered cab, over-cab sleeper, split windshield, mirrors, four suspension-driven tire/rim assemblies, wheel wells, bumpers, grille, working light nodes, entry door and step, service hatches, roof rack, solar array, vents, air conditioner, awning, cargo, rear spare, ladder and camera.
- Modeled a continuous interior: dashboard, gauges, navigation screen, movable steering wheel, pedals, driver/passenger seats, belts, cab trim, kitchen, sink, stove, cabinets, dinette, rear bed, storage, map and ceiling fixtures.
- Driver-eye first person now occupies the real cockpit and keeps the RV shell visible. The old camera-attached `rv_cockpit.gltf` overlay was removed.
- Chase view is centered behind the full vehicle at a non-overhead angle. Spring-arm collision still excludes the occupied RV so it does not collapse into the shell.
- Exterior static geometry is batched to 35 material primitives; each detailed wheel is batched to 3 primitives. This preserves mobile draw-call discipline despite the added detail.
- CI captures both chase-view exterior and modeled-cockpit images and verifies physical wheels, key model components, camera placement and shell visibility.

## Character and controls

- Quaternius CC0 skinned survivor remains the character source.
- The visible body now turns toward actual camera-relative travel, so forward, reverse and lateral input no longer produce a sideways static slide.
- Locomotion state selection covers `Idle`, `Walk`, `Run`, `Jump`, airborne `Jump_Idle` and `Jump_Land`, with blended transitions and explicit landing time.
- CI holds the routed mobile stick, verifies real travel, verifies an active walk/run clip and checks that the model's forward axis aligns with travel.
- Viewport-level pointer-ID routing continues to support simultaneous movement, swipe look and action touches.
- Gamepad parity now includes jump, interact, sprint, view toggle, handbrake, both shifts, both winches and pause in addition to both analog sticks.
- The persisted layout editor continues to support button position, scale, opacity and touch-look sensitivity.

## World, missions and physics

- Player spawn remains clamped to the campsite terrain and deterministic terrain-following prevents the reported endless fall.
- Parked RV static freeze, upright parking, finite-state recovery, speed caps, anti-roll torque and suspension remain active.
- The bog now changes vehicle traction and adds physical drag instead of being visual paint only; winch force remains available to recover the rig.
- Supplies still gate the driver seat. Gears, fuel, damage, repair, bridge construction, twin winches, rockfall, checkpoints and finish flow remain intact.
- Terrain, underlay, road, camp blockers and batched distant forest safeguards remain active.

## Validation still required before calling the build final

- Install the generated APK on representative low/mid/high Android devices.
- Capture landscape screenshots of menu, walking third person, RV chase view and driver-eye cockpit.
- Drive the full route with multi-touch, including sprint/jump while looking, manual shifting, braking, bridge, mud/winch, repair, checkpoint recovery and finish.
- Check frame pacing, thermals, memory pressure, steering feel, wheel contact, camera clipping and text/button safe areas.
- Test the unsigned iOS Xcode export after signing on a physical iPhone.

Any physical-device regression reopens the relevant section even if GitHub validation remains green.

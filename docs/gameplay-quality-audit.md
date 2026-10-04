# Gameplay and presentation audit

This checklist is the release gate for the wholesale RV-replacement line. A green export is necessary but is not proof of visual or physical-device quality. The rejected 0.9 and 0.10 captures remain baseline regressions that the replacement must visibly fix; neither build is a release candidate.

The first 0.10 phone capture improved the character and made the cockpit readable, but still failed release: its generic Class-C truck/box silhouette was fundamentally wrong, the wheels looked floating or buried, the cockpit could be occluded, and the overall vehicle did not approach the supplied *RV There Yet?* presentation. That mesh has now been removed rather than cosmetically patched.

## RV presentation and physics

- The replacement is an original vintage Class-A expedition motorhome: full-height flat nose, tall panoramic split windshield, open side glazing, squared old-coach shoulders, cut wheel wells, four separated suspension-driven tire/rim assemblies, broad bumper/grille, mirrors, working lights, hinged entry door and step, service hatches, roof cage, solar array, vents, air conditioner, awning, cargo, rear spare and ladder.
- The removed truck hood, tapered delivery-van cab and over-cab sleeper must not reappear. Source and CI assertions treat those components as regressions.
- Exterior coach skin, living interior and cockpit frame are separate render batches. Driver-eye view culls only the opaque exterior skin while preserving the actual dashboard, frame, glazing and interior; it does not use a camera-attached overlay.
- The continuous interior includes dashboard, gauges, navigation screen, movable steering wheel, physical animated gear gate/lever, pedals, driver/passenger seats, belts, cab trim, refrigerator, kitchen, sink, stove, cabinets, dinette, rear bed, storage, map and ceiling fixtures.
- The passenger entry door is an independently modeled mechanism with a world-space hinge, animated open/close state and physical interaction target. The coach uses a seven-piece hollow compound collider with a split passenger wall, so opening the door provides a real path into the connected cabin instead of exposing a solid invisible box.
- Chassis/floor collision ends above the wheel contact region. Each tire has a solid inner contact core plus a damped per-wheel terrain spring fallback for missed first-frame VehicleWheel rays. CI releases the full 3.6-ton RV into physics and rejects any wheel centre that settles below the terrain-clearance gate.
- Chase view uses a slightly elevated three-quarter angle that exposes the wheel contact and coach side instead of staring level into the full-height rear wall. Spring-arm collision excludes the occupied RV so it does not collapse into the shell.
- The driver eye sits ahead of the seat back/headrest at `(0.53, 1.48, -1.55)` in coach space; seat upholstery must not appear as giant screen-covering slabs.
- Exterior, interior and cockpit are independently asserted in CI; chase and driver-eye screenshots are captured separately.

## Character and controls

- The old mismatched survivor has been replaced by an original rounded, stout crew character with a large expressive head, cap, sunglasses, vest, articulated arms and articulated legs.
- Procedural locomotion covers `Idle`, `Walk`, `Run`, `Jump`, airborne `Jump_Idle` and `Jump_Land`, with visible opposing arm/leg swing, body lean and landing compression.
- The visible body turns toward camera-relative travel so forward, reverse and lateral input do not produce sideways sliding.
- CI holds the routed mobile stick, verifies real travel, verifies walk/run state and checks that the model's forward axis aligns with travel.
- Viewport-level pointer-ID routing continues to support simultaneous movement, swipe look and action touches.
- Gamepad parity includes jump, interact, sprint, view toggle, handbrake, both shifts, both winches and pause in addition to both analog sticks.
- The persisted layout editor supports button position, scale, opacity and touch-look sensitivity.

## World, missions and performance

- Terrain now uses layered near/mid/far vegetation: textured Quaternius CC0 hero trees, bushes, ferns, flowers, grasses and rocks near the route; mobile-light Kenney scenery at mid range; and batched distant forest coverage.
- Player spawn remains clamped to campsite terrain and deterministic terrain-following prevents the reported endless fall.
- Parked RV static freeze, upright parking, finite-state recovery, speed caps, anti-roll torque and suspension remain active.
- The bog changes vehicle traction and adds physical drag; winch force remains available to recover the rig.
- Supplies gate the driver seat. Gears, fuel, damage, repair, bridge construction, twin winches, rockfall, checkpoints and finish flow remain intact.
- Low quality disables expensive hero-tree shadows and forest-floor shadows are disabled on all profiles.

## Validation still required before calling the build stable

- Install the generated APK on representative low/mid/high Android devices.
- Capture landscape screenshots of menu, rounded character in motion, door open, RV chase view after at least 30 seconds of driving, and unobstructed driver-eye cockpit.
- In chase view, verify all four tire sidewalls remain visible and carry the coach after parking freeze is released.
- In driver-eye view, verify windshield, dashboard, wheel, gear mechanism and road are visible with no opaque cream wall covering the camera.
- Drive the full route with multi-touch, including sprint/jump while looking, manual shifting, braking, bridge, mud/winch, repair, checkpoint recovery and finish.
- Check frame pacing, thermals, memory pressure, steering feel, wheel contact, camera clipping and text/button safe areas.
- Test the unsigned iOS Xcode export after signing on a physical iPhone.

Any physical-device regression reopens the relevant section even if GitHub validation remains green.

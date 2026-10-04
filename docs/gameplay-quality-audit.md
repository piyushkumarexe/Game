# Gameplay and presentation audit

This checklist is the release gate for the wholesale RV-replacement line. A green export is necessary but is not proof of visual or physical-device quality. The rejected 0.9 and 0.10 captures remain baseline regressions that the replacement must visibly fix; neither build is a release candidate.

The `f781fe1` physical-phone captures failed release wholesale: the procedural coach still read as a rectangular slab, its wheels looked floating/buried and visually detached, the doorway did not read as traversable, the cockpit clipped, the chase camera became a roof view, and the generated character had unacceptable facial placement. Those hero assets are no longer the rendered exterior/character; green automation for that build is explicitly withdrawn.

## RV presentation and physics

- The replacement hero exterior is Karol Miklas' 43.4k-triangle CC-BY vintage GMC Class-A motorhome: curved/chamfered coachwork, panoramic glazing, formed fascia, grille, lamps, mirrors, trim, wheel wells, service detail and roof rack replace the rejected generated slab.
- Its three real axle pairs were separated into six suspension-driven tire/rim assemblies at the authored wheelbase and 0.43 m radius. The removed tiny grey cylinders and four-wheel box stance must not reappear.
- Exterior coach skin and connected living interior are separate render groups. Driver-eye view keeps the professional exterior/glazing present and relies on correct interior-facing culling; it does not hide the vehicle or use a camera-attached overlay.
- The continuous interior includes dashboard, gauges, navigation screen, movable steering wheel, physical animated gear gate/lever, pedals, driver/passenger seats, belts, cab trim, refrigerator, kitchen, sink, stove, cabinets, dinette, rear bed, storage, map and ceiling fixtures.
- The source side panel/glazing is physically opened at the passenger entry. An independently modeled door uses a world-space hinge, three visible exterior treads bridge terrain to the threshold, and the seven-piece hollow collider splits around the same aperture so the route continues directly onto the modeled floor.
- Chassis/floor collision ends above the wheel contact region. Each tire has a smaller hidden contact core plus a damped per-wheel terrain spring fallback for missed first-frame VehicleWheel rays. CI releases the full 3.6-ton RV into physics and rejects centres outside the new 0.32–0.62 m clearance envelope.
- Chase view trails 7.6 m from a window-height, rear-right three-quarter pivot; it must show coach side and wheel contact rather than the roof-dominated physical screenshot. Spring-arm collision excludes the occupied RV so it does not collapse into the shell.
- The driver eye sits at `(0.53, 1.30, -2.30)` in coach space, behind the dashboard and within the panoramic windshield, with clearance from seat back, header, steering rim and console.
- Exterior, interior and cockpit are independently asserted in CI; chase and driver-eye screenshots are captured separately.

## Character and controls

- The rejected generated survivor is replaced by Quaternius' professionally modeled/skinned CC0 male base head and Ranger outfit. The normal-spaced authored eyes and facial texture are retained; an original cap, compact sunglasses and padded vest panels move the silhouette toward the supplied road-trip character.
- Locomotion drives the imported named skeletons for `Idle`, `Walk`, `Run`, `Jump`, airborne `Jump_Idle` and `Jump_Land`, with opposing arm/leg swing, knee flex, body lean and landing compression.
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
- Capture landscape screenshots of menu, professional character face/in-motion pose, door open and traversed, RV chase view after at least 30 seconds of driving, and unobstructed driver-eye cockpit.
- In chase view, verify the front and tandem-rear tire sidewalls read as real wheels, remain correctly seated in all wheel wells, and carry the coach after parking freeze is released.
- In driver-eye view, verify windshield, dashboard, wheel, gear mechanism and road are visible with no opaque cream wall covering the camera.
- Drive the full route with multi-touch, including sprint/jump while looking, manual shifting, braking, bridge, mud/winch, repair, checkpoint recovery and finish.
- Check frame pacing, thermals, memory pressure, steering feel, wheel contact, camera clipping and text/button safe areas.
- Test the unsigned iOS Xcode export after signing on a physical iPhone.

Any physical-device regression reopens the relevant section even if GitHub validation remains green.

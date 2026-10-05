extends Node
## Application shell: cinematic menu, network lobby and expedition lifecycle.

const WorldScript = preload("res://scripts/world/expedition_world.gd")
const HUDScript = preload("res://scripts/ui/expedition_hud.gd")
const MenuDioramaScript = preload("res://scripts/ui/menu_diorama.gd")
const ControlLayoutEditorScript = preload("res://scripts/ui/control_layout_editor.gd")

var menu_layer: CanvasLayer
var name_input: LineEdit
var address_input: LineEdit
var role_picker: OptionButton
var status_label: Label
var active_world: ExpeditionWorld
var active_hud: ExpeditionHUD
var menu_world: MenuDiorama
var settings_editor: ControlLayoutEditor

func _ready() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	Net.joined_server.connect(_on_joined_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	GameSession.run_finished.connect(_show_results)
	if "--smoke-expedition" in OS.get_cmdline_user_args():
		_run_expedition_smoke_test()
	else:
		_show_main_menu()

func _show_main_menu() -> void:
	_clear_game()
	GameSession.mode = GameSession.Mode.MENU
	if menu_world and is_instance_valid(menu_world):
		menu_world.queue_free()
	menu_world = MenuDioramaScript.new()
	add_child(menu_world)

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 50
	add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(root)

	var cinematic_shade := ColorRect.new()
	cinematic_shade.color = Color(0.015, 0.022, 0.032, 0.24)
	cinematic_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cinematic_shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.025
	panel.anchor_top = 0.035
	panel.anchor_right = 0.43
	panel.anchor_bottom = 0.965
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.032, 0.045, 0.93), Color(0.93, 0.62, 0.25, 0.34), 18))
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := _label("DUSTBOUND", 49, Color("fff0d1"), true)
	content.add_child(title)
	var subtitle := _label("E X P E D I T I O N S", 17, Color("eea23b"), true)
	content.add_child(subtitle)
	var pitch := _label("ONE DRIVER. ONE RIG. A VERY BAD ROAD HOME.", 13, Color("d7d2c4"), true)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(pitch)
	var separator := HSeparator.new()
	separator.modulate = Color(0.9, 0.59, 0.25, 0.45)
	content.add_child(separator)

	var profile_label := _label("SINGLE-PLAYER PROFILE", 12, Color("eea23b"), true)
	content.add_child(profile_label)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Callsign"
	name_input.text = GameSession.player_name
	name_input.custom_minimum_size = Vector2(210, 46)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_field(name_input)
	content.add_child(name_input)
	# Keep a driver-only picker object for the existing profile API, but do not
	# expose unfinished co-op roles in this stabilization release.
	role_picker = OptionButton.new()
	role_picker.add_item("DRIVER")

	var solo := _button("START SINGLE-PLAYER EXPEDITION", Vector2.ZERO, Vector2(0, 58), Color("dd8f33"))
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.pressed.connect(_start_solo)
	content.add_child(solo)
	var settings := _button("CONTROLS & PERFORMANCE", Vector2.ZERO, Vector2(0, 46), Color("315c61"))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_font_size_override("font_size", 14)
	settings.pressed.connect(_show_control_settings)
	content.add_child(settings)

	status_label = _label("SINGLE-PLAYER MOBILE BUILD • CUSTOM CONTROLS", 11, Color("bcb9ae"), true)
	status_label.custom_minimum_size.y = 34
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)
	var feature := _label("SWIPE FREE-LOOK  •  FIRST/THIRD PERSON  •  PHYSICS RV\nMANUAL GEARS  •  REPAIRS  •  MISSIONS  •  WINCHES", 11, Color("f1d6a9"), true)
	feature.add_theme_constant_override("line_spacing", 5)
	content.add_child(feature)

	var badge := Label.new()
	badge.text = "LIVE 3D CAMPSITE  •  SINGLE-PLAYER STABILITY BUILD"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.anchor_left = 0.68
	badge.anchor_top = 0.885
	badge.anchor_right = 0.975
	badge.anchor_bottom = 0.95
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("fff0d1"))
	badge.add_theme_stylebox_override("normal", _style(Color(0.03, 0.04, 0.055, 0.72), Color(1, 1, 1, 0.16), 14))
	root.add_child(badge)

func _show_control_settings() -> void:
	if is_instance_valid(settings_editor):
		return
	settings_editor = ControlLayoutEditorScript.new()
	settings_editor.setup(func() -> void: settings_editor = null)
	get_tree().root.add_child(settings_editor)

func _start_solo() -> void:
	_save_profile()
	Net.start_solo()
	_start_expedition()

func _host_game() -> void:
	_save_profile()
	var error := Net.host_game(GameSession.player_name, GameSession.selected_role)
	if error == OK:
		status_label.text = "CREW LOBBY OPEN ON %s:%d — STARTING…" % [Net._best_local_address(), Net.PORT]
		_start_expedition()

func _join_game() -> void:
	_save_profile()
	status_label.text = "CONTACTING HOST…"
	Net.join_game(address_input.text, GameSession.player_name, GameSession.selected_role)

func _on_joined_server() -> void:
	_start_expedition()

func _on_connection_failed(reason: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = reason.to_upper()

func _on_disconnected() -> void:
	_show_main_menu()
	if status_label:
		status_label.text = "HOST DISCONNECTED — RUN ENDED"

func _start_expedition() -> void:
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	if menu_world and is_instance_valid(menu_world):
		menu_world.queue_free()
		menu_world = null
	GameSession.reset_run()
	active_world = WorldScript.new()
	add_child(active_world)
	active_hud = HUDScript.new()
	add_child(active_hud)

func _inject_screen_touch(pointer: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)

func _inject_screen_drag(pointer: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = pointer
	event.position = position
	event.relative = relative
	event.screen_relative = relative
	Input.parse_input_event(event)

func _tap_control(control: Control, pointer: int) -> void:
	var center := control.get_global_rect().get_center()
	_inject_screen_touch(pointer, center, true)
	_inject_screen_touch(pointer, center, false)

func _run_expedition_smoke_test() -> void:
	GameSession.player_name = "Render Scout"
	GameSession.selected_role = GameSession.Role.DRIVER
	Net.start_solo()
	_start_expedition()
	await get_tree().create_timer(3.0).timeout
	var failures: Array[String] = []
	if not active_world or not is_instance_valid(active_world):
		failures.append("expedition world missing")
	if not GameSession.local_player or not is_instance_valid(GameSession.local_player):
		failures.append("local player missing")
	if not GameSession.rv or not is_instance_valid(GameSession.rv):
		failures.append("physics RV missing")
	if Net.is_online:
		failures.append("single-player stability build unexpectedly enabled networking")

	# Exercise both camera modes instead of merely checking that camera nodes
	# exist. The screenshot is intentionally captured in third person so the
	# player, detailed RV exterior and collision-aware chase framing are proven.
	if GameSession.local_player and is_instance_valid(GameSession.local_player):
		var local_player: ExpeditionPlayer = GameSession.local_player as ExpeditionPlayer
		if not local_player.global_position.is_finite() or local_player.global_position.y < 1.0:
			failures.append("player fell below the campsite (y=%.2f)" % local_player.global_position.y)
		if not local_player.grounded:
			failures.append("player is not grounded after campsite spawn")
		if local_player.velocity.length() > 1.5:
			failures.append("idle player is unstable (%.2f m/s)" % local_player.velocity.length())
		if local_player.find_child("ProximityVoice", true, false):
			failures.append("single-player spawned a voice/network component")
		if not local_player.first_camera or not local_player.third_camera or not local_player.spring_arm:
			failures.append("first/third-person camera rig missing")
		elif get_viewport().get_camera_3d() != local_player.first_camera:
			failures.append("first-person camera was not initially current")
		else:
			var view_button := active_hud.find_child("Touch_toggle_view", true, false) as Button if active_hud else null
			if not view_button:
				failures.append("touch first/third-person button missing")
			else:
				_tap_control(view_button, 6)
				await get_tree().process_frame
				await get_tree().physics_frame
				if not local_player.third_person or get_viewport().get_camera_3d() != local_player.third_camera:
					failures.append("VIEW touch button did not activate third-person camera")
			if not local_player.body_visual.visible:
				failures.append("third-person crew model is hidden")

			# Send a real right-side touch sequence through the same viewport router
			# used on Android, then verify that controller yaw actually changes.
			var yaw_before_swipe := local_player.rotation.y
			var look_start := Vector2(get_viewport().get_visible_rect().size.x * 0.72, 330.0)
			_inject_screen_touch(7, look_start, true)
			_inject_screen_drag(7, look_start + Vector2(52.0, 0.0), Vector2(52.0, 0.0))
			_inject_screen_touch(7, look_start + Vector2(52.0, 0.0), false)
			await get_tree().process_frame
			await get_tree().physics_frame
			if is_equal_approx(local_player.rotation.y, yaw_before_swipe):
				failures.append("right-side touch drag did not rotate the player controller")

			# Hold the real left stick for several physics ticks. Node existence is
			# not enough: the player must physically travel and play locomotion.
			var move_stick := active_hud.find_child("MoveStick", true, false) as Control if active_hud else null
			if not move_stick:
				failures.append("left movement stick missing")
			else:
				var move_center := move_stick.get_global_rect().get_center()
				var move_point := move_center + Vector2(0.0, -68.0)
				var position_before_move := local_player.global_position
				# Input.parse_input_event batches held touches in CI, so invoke the same
				# router entry points directly for a deterministic sustained-stick test.
				active_hud.input_router._begin_touch(8, move_point)
				var routed_move := GameSession.mobile_move
				if routed_move.length() < 0.5:
					failures.append("left stick touch was not routed (value=%s)" % routed_move)
				await get_tree().create_timer(0.45).timeout
				var travelled := local_player.global_position.distance_to(position_before_move)
				var movement_velocity := local_player.velocity
				if not local_player.body_rig and not local_player.body_animation:
					failures.append("animated third-person character missing")
				elif local_player.body_animation_name not in ["Walk", "Run"]:
					failures.append("moving survivor did not enter walk/run animation (%s)" % local_player.body_animation_name)
				if local_player.body_rig:
					if local_player.body_rig.skeletons.size() < 2:
						failures.append("professional head/outfit skeletons did not import")
					elif not local_player.body_rig.animation_skeleton or not local_player.body_rig.animation_player:
						failures.append("authored Quaternius animation rig did not import")
					elif local_player.body_rig.current_clip != "Walk_Carry":
						failures.append("moving crew did not play an authored locomotion clip (%s)" % local_player.body_rig.current_clip)
					else:
						local_player.body_rig._copy_animation_pose()
						var source_skeleton := local_player.body_rig.animation_skeleton
						var proof_skeleton := local_player.body_rig.skeletons[0]
						var source_thigh := source_skeleton.find_bone("thigh_l")
						var target_thigh := proof_skeleton.find_bone("thigh_l")
						if source_thigh < 0 or target_thigh < 0:
							failures.append("professional named locomotion bones missing")
						else:
							var source_rotation := source_skeleton.get_bone_pose_rotation(source_thigh)
							var target_rotation := proof_skeleton.get_bone_pose_rotation(target_thigh)
							if source_rotation.angle_to(target_rotation) > 0.02:
								failures.append("authored locomotion pose was not copied to outfit rig")
						print("CREW_ANIMATION_PROOF clip=%s skeletons=%d" % [local_player.body_rig.current_clip, local_player.body_rig.skeletons.size()])
					for accessory in ["ExpeditionCapCrown", "SunglassLens", "QuaterniusRangerOutfit"]:
						if not local_player.body_rig.find_child(accessory, true, false):
							failures.append("professional crew component missing: %s" % accessory)
				if local_player.body_visual and Vector2(movement_velocity.x, movement_velocity.z).length() > 0.5:
					var visual_forward := local_player.body_visual.global_transform.basis.z.normalized()
					var travel_forward := Vector3(movement_velocity.x, 0.0, movement_velocity.z).normalized()
					if visual_forward.dot(travel_forward) < 0.62:
						failures.append("survivor model is sliding sideways instead of facing travel")
				active_hud.input_router._end_touch(8)
				await get_tree().process_frame
				if travelled < 0.8:
					failures.append("left touch stick did not move player (distance=%.3f input=%s velocity=%s)" % [travelled, routed_move, movement_velocity])

			var sprint_button := active_hud.find_child("Touch_sprint", true, false) as Button if active_hud else null
			if sprint_button:
				var sprint_center := sprint_button.get_global_rect().get_center()
				_inject_screen_touch(9, sprint_center, true)
				await get_tree().process_frame
				if not GameSession.touch_action("sprint"):
					failures.append("SPRINT touch button did not hold its action")
				_inject_screen_touch(9, sprint_center, false)
				await get_tree().process_frame
				if GameSession.touch_action("sprint"):
					failures.append("SPRINT touch action stuck after release")
			else:
				failures.append("SPRINT touch button missing")

			var jump_button := active_hud.find_child("Touch_jump", true, false) as Button if active_hud else null
			if jump_button:
				_tap_control(jump_button, 10)
				await get_tree().process_frame
				await get_tree().physics_frame
				if local_player.velocity.y <= 0.5:
					failures.append("JUMP touch button did not launch the grounded player")
				if (local_player.body_rig or local_player.body_animation) and local_player.body_animation_name not in ["Jump", "Jump_Idle"]:
					failures.append("jump did not activate a locomotion animation (%s)" % local_player.body_animation_name)
				await get_tree().create_timer(1.0).timeout
			else:
				failures.append("JUMP touch button missing")

			# Dedicated front-facing proof catches facial proportion, eye spacing,
			# accessory placement and accidental bind/A-pose regressions that a rear
			# gameplay camera cannot reveal.
			if local_player.body_visual and local_player.body_visual.visible:
				# Capture a settled neutral pose rather than a single-frame landing crouch;
				# close-up proportions must represent normal gameplay presentation.
				local_player.body_rig.set_locomotion("Idle", 0.0, 0.0, 0.0)
				await get_tree().create_timer(0.20).timeout
				var character_camera := Camera3D.new()
				character_camera.name = "CharacterAcceptanceCamera"
				character_camera.fov = 38.0
				character_camera.near = 0.05
				active_world.add_child(character_camera)
				var character_target := local_player.body_rig.accessory_root.global_position + Vector3.UP * 0.07
				var character_front := local_player.body_visual.global_transform.basis.z.normalized()
				character_camera.global_position = character_target + character_front * 1.30
				character_camera.look_at(character_target, Vector3.UP)
				if active_hud:
					active_hud.visible = false
				await _save_staged_render(character_camera, "res://build/validation/character-face-render.png")
				# A second full-body frame catches detached boots, folded limbs, sliding
				# silhouettes and accessory offsets that a face crop cannot reveal.
				var body_target := local_player.body_visual.global_position + Vector3.UP * 0.92
				character_camera.fov = 44.0
				character_camera.global_position = body_target + character_front * 3.05 + Vector3.UP * 0.06
				character_camera.look_at(body_target, Vector3.UP)
				await _save_staged_render(character_camera, "res://build/validation/character-body-render.png")
				if active_hud:
					active_hud.visible = true
				character_camera.queue_free()
				local_player.third_camera.make_current()

	# Guard the exact runaway/falling regression reported from the phone build.
	if GameSession.rv and is_instance_valid(GameSession.rv):
		var smoke_rv: ExpeditionRV = GameSession.rv as ExpeditionRV
		var parked_speed := smoke_rv.linear_velocity.length()
		var spawn_drift := smoke_rv.global_position.distance_to(smoke_rv.start_transform.origin)
		if parked_speed > 3.5:
			failures.append("parked RV is unstable (%.2f m/s)" % parked_speed)
		if spawn_drift > 3.0:
			failures.append("parked RV drifted %.2f m from spawn" % spawn_drift)
		if smoke_rv.health < 99.0:
			failures.append("RV took false spawn damage (%.1f health)" % smoke_rv.health)
		var parked_up := smoke_rv.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
		if parked_up < 0.985:
			failures.append("parked RV tipped before entry (up=%.3f)" % parked_up)
		if not smoke_rv.freeze:
			failures.append("unoccupied RV is not in stable parking mode")
		var wheel_count := 0
		var shell_collision_count := 0
		for child: Node in smoke_rv.get_children():
			if child is VehicleWheel3D:
				wheel_count += 1
				if not child.find_child("DetailedWheelAssembly", true, false):
					failures.append("%s lacks its modeled tire/rim assembly" % child.name)
			elif child is CollisionShape3D and child.name.begins_with("RV"):
				shell_collision_count += 1
		if wheel_count != 6:
			failures.append("professional tandem-axle RV requires 6 physical wheels, found %d" % wheel_count)
		if shell_collision_count != 7:
			failures.append("RV requires a 7-piece hollow shell collider, found %d" % shell_collision_count)
		var rejected_shell := smoke_rv.body_shell.find_child("StaticRVExterior", true, false) as MeshInstance3D if smoke_rv.body_shell else null
		var professional_exterior := smoke_rv.body_shell.find_child("ProfessionalGMCMotorhomeExterior", true, false) as Node3D if smoke_rv.body_shell else null
		var static_interior := smoke_rv.body_shell.find_child("StaticRVInterior", true, false) as MeshInstance3D if smoke_rv.body_shell else null
		if not professional_exterior or professional_exterior.find_children("*", "MeshInstance3D", true, false).size() < 5:
			failures.append("professional GMC exterior meshes missing")
		if rejected_shell and rejected_shell.visible:
			failures.append("rejected procedural slab exterior is still visible")
		if not static_interior or not static_interior.mesh or static_interior.mesh.get_surface_count() < 8:
			failures.append("connected modeled RV interior material surfaces missing")
		for component_name in ["CockpitSteeringWheel", "GearLever", "EntryDoor", "DriverCockpitSeat", "PassengerCockpitSeat", "ConnectedEntryAisle", "DoorwayInteriorWoodPanel", "RoofCargo", "FrontBumper"]:
			if not smoke_rv.body_shell or not smoke_rv.body_shell.find_child(component_name, true, false):
				failures.append("modeled RV component missing: %s" % component_name)
		smoke_rv.set_entry_door_open(true)
		await get_tree().create_timer(0.60).timeout
		if not smoke_rv.entry_door_pivot or absf(smoke_rv.entry_door_pivot.rotation.y) < 1.30:
			failures.append("functional RV entry door did not open on its hinge")
		if active_world:
			var doorway_probe := smoke_rv.global_transform * Vector3(1.30, 0.06, 0.98)
			var cabin_probe := smoke_rv.global_transform * Vector3(0.0, 0.06, 0.20)
			var low_approach := smoke_rv.global_transform * Vector3(2.42, -0.86, 0.98)
			low_approach.y = active_world.terrain_height(low_approach.x, low_approach.z) + 0.03
			if active_world.constrain_player_position(low_approach, low_approach).distance_to(low_approach) > 0.05:
				failures.append("open RV doorway rejects a terrain-level stair approach")
			if active_world.constrain_player_position(doorway_probe, doorway_probe).distance_to(doorway_probe) > 0.05:
				failures.append("open RV door does not provide a physical cabin path")
			if active_world.constrain_player_position(cabin_probe, cabin_probe).distance_to(cabin_probe) > 0.05:
				failures.append("connected RV living interior rejects an upright player")
			var previous_step_height := -INF
			var previous_path_point := low_approach
			# Walk the complete centreline in phone-sized increments. This verifies
			# the same horizontal constraint and deterministic step-up path used by
			# the real controller, not merely one point on either side of the gate.
			for step_x in [2.24, 2.08, 1.92, 1.76, 1.60, 1.44, 1.28, 1.12, 0.96, 0.80]:
				var step_probe := smoke_rv.global_transform * Vector3(step_x, -0.86, 0.98)
				step_probe.y = previous_path_point.y
				var accepted_probe := active_world.constrain_player_position(previous_path_point, step_probe)
				var accepted_local := smoke_rv.global_transform.affine_inverse() * accepted_probe
				if absf(accepted_local.x - step_x) > 0.035 or absf(accepted_local.z - 0.98) > 0.035:
					failures.append("RV entry centreline blocked at x=%.2f (accepted=%s)" % [step_x, accepted_local])
				var step_height := active_world.player_floor_height(accepted_probe)
				accepted_probe.y = step_height
				var local_step_height := (smoke_rv.global_transform.affine_inverse() * accepted_probe).y
				if local_step_height + 0.03 < previous_step_height:
					failures.append("RV entry floor descends while walking inward at x=%.2f" % step_x)
				previous_step_height = local_step_height
				previous_path_point = accepted_probe
			if previous_step_height < 0.02:
				failures.append("RV stair path never reaches connected cabin floor")
			# Exercise the phone-friendly USE assist as well as the physical walk.
			# It must enter the living cabin without prematurely assigning a driver.
			var assisted_player := GameSession.local_player as ExpeditionPlayer
			assisted_player.global_position = low_approach
			smoke_rv.entry_door_interactable.interact(assisted_player)
			var assisted_local := smoke_rv.global_transform.affine_inverse() * assisted_player.global_position
			if assisted_local.x > 1.10 or absf(assisted_local.z - 0.98) > 0.08:
				failures.append("door USE assist did not place player inside cabin (%s)" % assisted_local)
			if smoke_rv.driver_peer_id != 0 or assisted_player.is_driving:
				failures.append("door USE assist incorrectly skipped directly to driver seat")
			# Side-on acceptance frame must visibly show the open panel, all three
			# steps, unobstructed threshold and connected modeled living space.
			var doorway_camera := Camera3D.new()
			doorway_camera.name = "DoorwayAcceptanceCamera"
			doorway_camera.fov = 58.0
			doorway_camera.near = 0.05
			active_world.add_child(doorway_camera)
			var doorway_target := smoke_rv.global_transform * Vector3(1.02, 0.72, 0.98)
			# A shallow front-side angle exposes all three tread depths and the cabin
			# portal while keeping the rear-hinged open panel out of the sightline.
			# The old rear-quarter proof let that panel hide the gate entirely.
			doorway_camera.global_position = smoke_rv.global_transform * Vector3(4.00, 1.35, -0.35)
			doorway_camera.look_at(doorway_target, smoke_rv.global_transform.basis.y.normalized())
			# The gameplay character can stand directly on this sightline after the
			# movement test. Hide only its visual while documenting the physical entry.
			var doorway_player := GameSession.local_player as ExpeditionPlayer
			var doorway_player_was_visible := doorway_player.body_visual.visible
			var doorway_hud_was_visible := active_hud.visible if active_hud else false
			doorway_player.body_visual.visible = false
			if active_hud:
				active_hud.visible = false
			await _save_staged_render(doorway_camera, "res://build/validation/rv-doorway-render.png")
			doorway_player.body_visual.visible = doorway_player_was_visible
			if active_hud:
				active_hud.visible = doorway_hud_was_visible
			doorway_camera.queue_free()
			GameSession.local_player.camera.make_current()
		smoke_rv.set_entry_door_open(false)
		if GameSession.local_player and is_instance_valid(GameSession.local_player):
			smoke_rv.interact(GameSession.local_player)
		if smoke_rv.driver_peer_id != 0:
			failures.append("unpacked RV allowed a driver or started occupied")
		# Pack and enter through the real interaction path. This proves the chase
		# camera and driver-eye camera against the same intact modeled RV shell.
		if GameSession.local_player and is_instance_valid(GameSession.local_player):
			GameSession.supplies_loaded = 3
			GameSession.complete_target("supplies")
			smoke_rv.interact(GameSession.local_player)
			await get_tree().process_frame
			await get_tree().physics_frame
			var smoke_player := GameSession.local_player as ExpeditionPlayer
			if smoke_rv.driver_peer_id != smoke_player.peer_id or not smoke_player.is_driving:
				failures.append("packed RV did not assign the physical driver seat")
			else:
				smoke_player._apply_camera_mode(true)
				# Let the full 3.6-ton suspension complete its damped release transient.
				await get_tree().create_timer(2.20).timeout
				if get_viewport().get_camera_3d() != smoke_player.third_camera:
					failures.append("RV chase camera did not become current")
				if not smoke_rv.body_shell.visible:
					failures.append("RV shell was hidden while driving")
				for settled_child: Node in smoke_rv.get_children():
					if settled_child is VehicleWheel3D:
						var settled_wheel := settled_child as VehicleWheel3D
						var wheel_ground := active_world.terrain_height(settled_wheel.global_position.x, settled_wheel.global_position.z)
						var wheel_clearance := settled_wheel.global_position.y - wheel_ground
						if wheel_clearance < 0.32:
							failures.append("%s sank below terrain after physics release (clearance %.2f m)" % [settled_wheel.name, wheel_clearance])
						elif wheel_clearance > 0.62:
							failures.append("%s is floating above terrain after physics release (clearance %.2f m)" % [settled_wheel.name, wheel_clearance])

	if active_hud and is_instance_valid(active_hud):
		if not active_hud.find_child("MoveStick", true, false):
			failures.append("left movement stick missing")
		if not active_hud.find_child("SwipeLookArea", true, false):
			failures.append("swipe camera-look area missing")
		if not active_hud.find_child("Touch_toggle_view", true, false):
			failures.append("touch first/third-person button missing")
		if not active_hud.find_child("Touch_control_settings", true, false):
			failures.append("mobile control-layout settings button missing")
		if not active_hud.find_child("Touch_handbrake", true, false):
			failures.append("mobile RV brake button missing")
	if active_world:
		var terrain := active_world.find_child("RedmesaTerrain", true, false) as MeshInstance3D
		if not terrain:
			failures.append("generated terrain missing")
		elif not (terrain.material_override is StandardMaterial3D):
			failures.append("terrain is not using the Android-safe standard material")
		if not active_world.find_child("BatchedDistantForest", true, false):
			failures.append("optimized distant forest batch missing")
		if active_world.find_children("CampHeroTexturedTree*", "Node3D", true, false).size() < 6:
			failures.append("opening campsite still lacks textured hero-tree density")
		if GameSession.graphics_quality == 2 and active_world.find_children("RealisticBarkBranches", "MeshInstance3D", true, false).size() < 8:
			failures.append("HIGH is missing its detailed procedural conifer layer")
		if active_world.rv:
			var under_bumper := active_world.rv.global_transform * Vector3(0.0, 0.0, 3.85)
			var blocked_position := active_world.constrain_player_position(under_bumper + Vector3.BACK, under_bumper)
			var blocked_local := active_world.rv.global_transform.affine_inverse() * blocked_position
			if absf(blocked_local.x) < 1.70 and absf(blocked_local.z) < 4.10:
				failures.append("player can still stand underneath an RV overhang")

	# Capture the 3D viewport without CanvasLayer UI. Stage the already-working
	# swipe-look camera at a rear three-quarter angle so the proof exposes side
	# glazing, both axles and wheel stance instead of validating only a rear wall.
	if GameSession.local_player and is_instance_valid(GameSession.local_player):
		var render_player := GameSession.local_player as ExpeditionPlayer
		if render_player.is_driving:
			render_player.head.rotation.y = 0.30
	if active_hud and is_instance_valid(active_hud):
		active_hud.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var current_camera := get_viewport().get_camera_3d()
	if not current_camera:
		failures.append("current 3D camera missing")
	var mesh_count := get_tree().get_nodes_in_group("render_smoke_mesh").size()
	if active_world:
		mesh_count = active_world.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count < 50:
		failures.append("expected at least 50 world meshes, found %d" % mesh_count)
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		failures.append("viewport capture is empty")
	else:
		var colors := {}
		var width := image.get_width()
		var height := image.get_height()
		for y in range(0, height, maxi(1, int(height / 18.0))):
			for x in range(0, width, maxi(1, int(width / 24.0))):
				colors[image.get_pixel(x, y).to_rgba32()] = true
		if colors.size() < 18:
			failures.append("viewport lacks visual variation (%d sampled colors)" % colors.size())
		# The former smoke test accepted a technically varied but almost-black
		# terrain. Measure the lower gameplay view where ground/road must be legible.
		var luminance_total := 0.0
		var luminance_samples := 0
		var dark_samples := 0
		for y in range(int(height * 0.46), height, maxi(1, int(height / 22.0))):
			for x in range(0, width, maxi(1, int(width / 28.0))):
				var pixel := image.get_pixel(x, y)
				var luminance := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
				luminance_total += luminance
				luminance_samples += 1
				if luminance < 0.075:
					dark_samples += 1
		var average_luminance := luminance_total / maxf(float(luminance_samples), 1.0)
		var dark_ratio := float(dark_samples) / maxf(float(luminance_samples), 1.0)
		if average_luminance < 0.17 or dark_ratio > 0.42:
			failures.append("ground render is underexposed (luma=%.3f dark=%.2f)" % [average_luminance, dark_ratio])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/validation"))
		image.save_png("res://build/validation/expedition-render.png")

	# A second render gate proves that first person occupies the world-space RV.
	# The authored shell remains present: back-face culling opens it naturally from
	# inside while real glazing, dashboard and connected cabin stay world-space.
	if GameSession.local_player and is_instance_valid(GameSession.local_player) and GameSession.rv:
		var cockpit_player := GameSession.local_player as ExpeditionPlayer
		var cockpit_rv := GameSession.rv as ExpeditionRV
		if cockpit_player.is_driving:
			cockpit_player.head.rotation = Vector3.ZERO
			cockpit_player.look_pitch = 0.0
			cockpit_player._apply_camera_mode(false)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			if get_viewport().get_camera_3d() != cockpit_player.first_camera:
				failures.append("driver-eye first-person camera did not become current")
			if not cockpit_rv.body_shell.visible:
				failures.append("first-person incorrectly hid the world-space RV model")
			var expected_eye: Vector3 = cockpit_rv.global_transform * Vector3(-0.72, 1.30, -2.85)
			if cockpit_player.first_camera.global_position.distance_to(expected_eye) > 0.24:
				failures.append("driver camera is not located in the modeled cockpit")
			for cockpit_part in ["CockpitSteeringWheel", "StaticRVInterior", "GearLever"]:
				if not cockpit_rv.body_shell.find_child(cockpit_part, true, false):
					failures.append("first-person cockpit part missing: %s" % cockpit_part)
			if not cockpit_rv.exterior_shell or not cockpit_rv.exterior_shell.visible:
				failures.append("professional shell/glazing disappeared in driver-eye view")
			if not cockpit_rv.interior_shell or not cockpit_rv.interior_shell.visible:
				failures.append("modeled interior is hidden in driver-eye view")
			var cockpit_image := get_viewport().get_texture().get_image()
			if cockpit_image.is_empty():
				failures.append("modeled cockpit render is empty")
			else:
				var cockpit_colors := {}
				var cockpit_width := cockpit_image.get_width()
				var cockpit_height := cockpit_image.get_height()
				var upper_samples := 0
				var upper_dark_samples := 0
				for y in range(0, cockpit_height, maxi(1, int(cockpit_height / 18.0))):
					for x in range(0, cockpit_width, maxi(1, int(cockpit_width / 24.0))):
						var cockpit_pixel := cockpit_image.get_pixel(x, y)
						cockpit_colors[cockpit_pixel.to_rgba32()] = true
						if y < int(cockpit_height * 0.35):
							upper_samples += 1
							var cockpit_luma := cockpit_pixel.r * 0.2126 + cockpit_pixel.g * 0.7152 + cockpit_pixel.b * 0.0722
							if cockpit_luma < 0.09:
								upper_dark_samples += 1
				if cockpit_colors.size() < 18:
					failures.append("modeled cockpit lacks visible structure (%d colors)" % cockpit_colors.size())
				var upper_dark_ratio := float(upper_dark_samples) / maxf(float(upper_samples), 1.0)
				if upper_dark_ratio > 0.32:
					failures.append("cockpit roof/seat occludes the upper view (dark=%.2f)" % upper_dark_ratio)
				cockpit_image.save_png("res://build/validation/rv-cockpit-render.png")
	print("3D_RENDER_SMOKE camera=%s meshes=%d failures=%s" % [get_viewport().get_camera_3d().name if get_viewport().get_camera_3d() else "none", mesh_count, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _save_staged_render(staged_camera: Camera3D, output_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/validation"))
	staged_camera.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var staged_image := get_viewport().get_texture().get_image()
	if not staged_image.is_empty():
		staged_image.save_png(output_path)

func _show_results(success: bool) -> void:
	var results := CanvasLayer.new()
	results.layer = 80
	add_child(results)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.035, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.add_child(shade)
	var title := _label("ROUTE 17 FOUND" if success else "THE VALLEY WON", 58, Color("fff0d1"), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 180)
	title.size = Vector2(680, 90)
	results.add_child(title)
	var detail := _label("You brought the rig home." if success else "Recover the rig and try a better line.", 18, Color("c9c4b7"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.position = Vector2(300, 276)
	detail.size = Vector2(680, 45)
	results.add_child(detail)
	var retry := _button("RUN IT AGAIN", Vector2(405, 370), Vector2(220, 64), Color("dd8f33"))
	retry.pressed.connect(func() -> void:
		results.queue_free()
		_clear_game()
		_start_expedition()
	)
	results.add_child(retry)
	var menu := _button("MAIN MENU", Vector2(655, 370), Vector2(220, 64), Color("485156"))
	menu.pressed.connect(func() -> void:
		results.queue_free()
		Net.shutdown()
		_show_main_menu()
	)
	results.add_child(menu)

func _clear_game() -> void:
	if active_hud and is_instance_valid(active_hud):
		active_hud.queue_free()
	if active_world and is_instance_valid(active_world):
		active_world.queue_free()
	active_hud = null
	active_world = null

func _save_profile() -> void:
	GameSession.player_name = name_input.text.strip_edges().left(18) if not name_input.text.strip_edges().is_empty() else "Rover"
	GameSession.selected_role = GameSession.Role.DRIVER

func _button(text: String, position: Vector2, size: Vector2, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("fff4dc"))
	button.add_theme_stylebox_override("normal", _style(color, Color(1, 1, 1, 0.16), 14))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.09), Color("ffe3ad"), 14))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.12), Color("fff0d1"), 14))
	return button

func _style_field(control: Control) -> void:
	control.add_theme_font_size_override("font_size", 15)
	control.add_theme_color_override("font_color", Color("fff0d1"))
	control.add_theme_stylebox_override("normal", _style(Color(0.04, 0.05, 0.065, 0.88), Color(1, 1, 1, 0.13), 10))

func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.85))
	return label

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

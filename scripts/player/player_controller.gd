class_name ExpeditionPlayer
extends CharacterBody3D
## Stable single-player explorer with first/third-person mobile controls.

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const JUMP_FORCE := 6.2
const LOOK_SENSITIVITY := 0.0024
const TOUCH_LOOK_SENSITIVITY := 0.0042
const ProfessionalCrewVisualScript = preload("res://scripts/player/professional_crew_visual.gd")
const HANDS_SCENE: PackedScene = preload("res://assets/models/first_person_hands.gltf")

var peer_id := 1
var player_name := "Rover"
var role := 0
var is_driving := false
var driven_vehicle: Node
var carried_item := ""
var carried_object: PhysicsCargo
var cargo_mount: Node3D
var interaction_text := ""
var remote_target := Transform3D.IDENTITY
var safe_position := Vector3.ZERO
var grounded := true
var vertical_velocity := 0.0
var look_pitch := 0.0
var head: Node3D
var camera: Camera3D
var first_camera: Camera3D
var third_camera: Camera3D
var third_person := false
var spring_arm: SpringArm3D
var interact_ray: RayCast3D
var body_visual: Node3D
var body_rig: ProfessionalCrewVisual
var body_animation: AnimationPlayer
var body_animation_name := ""
var movement_direction := Vector3.ZERO
var air_time := 0.0
var landing_time := 0.0
var just_jumped := false
var just_landed := false
var carried_visual: MeshInstance3D
var hands_visual: Node3D
var nameplate: Label3D
var voice: ProximityVoice
# Last observed coach pose for moving-platform transport. CharacterBody3D does
# not automatically inherit a VehicleBody3D's full translation and rotation,
# so passengers apply the coach delta before their own walking input.
var previous_rv_transform := Transform3D.IDENTITY
var rv_transform_initialized := false
# Touch players get a short automatic clutch press around each gear change. The
# dedicated clutch remains available for advanced starts, but routine shifting
# does not require holding two small buttons while steering with a thumb.
var mobile_auto_clutch_timer := 0.0

func setup(id: int, display_name: String, selected_role: int, spawn_position: Vector3) -> void:
	peer_id = id
	player_name = display_name
	role = selected_role
	name = "Player_%d" % peer_id
	position = spawn_position
	safe_position = spawn_position
	remote_target = transform
	set_multiplayer_authority(peer_id)
	_build_player()
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(false)
		nameplate.visible = false
		GameSession.register_local_player(self)
		call_deferred("_ensure_local_camera")
		if not OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Voice/network services stay dormant in the single-player stabilization
	# build. The code path remains available for a later multiplayer pass.
	if Net.is_online:
		voice = ProximityVoice.new()
		voice.name = "ProximityVoice"
		add_child(voice)
		voice.setup(peer_id)

func _ensure_local_camera() -> void:
	if peer_id != multiplayer.get_unique_id() or not is_instance_valid(camera):
		return
	camera.make_current()
	# Re-assert after scene construction. This avoids a later bootstrap camera
	# taking ownership on slower mobile devices.
	await get_tree().process_frame
	if is_instance_valid(camera):
		camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_driving:
			head.rotation.y = clampf(head.rotation.y - event.relative.x * LOOK_SENSITIVITY, -1.25, 1.25)
		else:
			rotate_y(-event.relative.x * LOOK_SENSITIVITY)
		look_pitch = clampf(look_pitch - event.relative.y * LOOK_SENSITIVITY, -1.15, 1.15)
		head.rotation.x = look_pitch

func _physics_process(delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		transform = transform.interpolate_with(remote_target, minf(1.0, delta * 13.0))
		return
	_apply_moving_rv_platform()
	if Input.is_action_just_pressed("toggle_view") or GameSession.consume_touch_press("toggle_view"):
		_toggle_camera_mode()
	if is_driving and driven_vehicle:
		_drive_vehicle(delta)
	else:
		_move_on_foot(delta)
	_update_body_animation(delta)
	_update_winch_remote()
	_update_carried_tool()
	_update_interaction()
	if Net.is_online:
		_sync_state.rpc(transform, velocity, is_driving)

func _apply_moving_rv_platform() -> void:
	var rig := GameSession.rv
	if not rig or not is_instance_valid(rig):
		rv_transform_initialized = false
		return
	var current: Transform3D = rig.global_transform
	if not rv_transform_initialized:
		previous_rv_transform = current
		rv_transform_initialized = true
		return
	if not is_driving and rig.has_method("contains_cabin_point") and rig.contains_cabin_point(global_position):
		# Preserve the passenger's coach-local position and facing while the rigid
		# body translates, climbs and turns. Their walking input is applied next.
		var coach_delta := current * previous_rv_transform.affine_inverse()
		global_transform = coach_delta * global_transform
		safe_position = global_position
	previous_rv_transform = current

func _move_on_foot(delta: float) -> void:
	just_jumped = false
	just_landed = false
	var input := GameSession.movement_vector()
	var direction := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	movement_direction = direction
	var speed := SPRINT_SPEED if GameSession.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 22.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 22.0 * delta)

	# Turn the visible survivor toward actual travel, including backpedal and
	# strafe input. The camera/root can free-look independently, so the character
	# no longer slides sideways in an unchanged pose.
	if direction.length_squared() > 0.0025 and body_visual:
		var world_facing := atan2(direction.x, direction.z)
		var local_facing := wrapf(world_facing - global_rotation.y, -PI, PI)
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, local_facing, minf(1.0, delta * 11.5))

	# CharacterBody3D was being pinned or falling through overlapping generated
	# trimesh/box contacts on Android. In the single-player build the procedural
	# terrain is authoritative, so horizontal locomotion and floor following are
	# deterministic while the RV keeps full rigid-body physics.
	var next_position := global_position + Vector3(velocity.x, 0.0, velocity.z) * delta
	next_position.x = clampf(next_position.x, -126.0, 126.0)
	next_position.z = clampf(next_position.z, -266.0, 108.0)
	if Net.world and Net.world.has_method("constrain_player_position"):
		next_position = Net.world.constrain_player_position(global_position, next_position)
	var floor_height := _terrain_floor(next_position.x, next_position.z)
	var jump_pressed := Input.is_action_just_pressed("jump") or GameSession.consume_touch_press("jump")
	if grounded and jump_pressed:
		grounded = false
		vertical_velocity = JUMP_FORCE
		air_time = 0.0
		landing_time = 0.0
		just_jumped = true
	if grounded:
		vertical_velocity = 0.0
		next_position.y = floor_height
	else:
		air_time += delta
		vertical_velocity -= 16.0 * delta
		next_position.y = global_position.y + vertical_velocity * delta
		if next_position.y <= floor_height:
			next_position.y = floor_height
			vertical_velocity = 0.0
			grounded = true
			just_landed = true
			landing_time = 0.32
	velocity.y = vertical_velocity
	global_position = next_position
	if grounded:
		safe_position = global_position
	if not global_position.is_finite() or global_position.y < -18.0:
		_recover_on_foot()
	_apply_mobile_and_gamepad_look(delta, false)

func _terrain_floor(x: float, z: float) -> float:
	if Net.world and Net.world.has_method("player_floor_height"):
		return float(Net.world.player_floor_height(Vector3(x, global_position.y, z)))
	if Net.world and Net.world.has_method("terrain_height"):
		return float(Net.world.terrain_height(x, z)) + 0.03
	return safe_position.y


func _recover_on_foot() -> void:
	global_position = safe_position + Vector3.UP * 0.12
	velocity = Vector3.ZERO
	vertical_velocity = 0.0
	grounded = true
	reset_physics_interpolation()
	GameSession.toast_requested.emit("BACK ON THE TRAIL", "Recovered at the last safe footing.")

func place_inside_rv(cabin_transform: Transform3D) -> void:
	# The doorway remains physically walkable, but USE at the open door is also a
	# mobile-friendly entry assist. It places the character's feet just past the
	# threshold instead of incorrectly jumping straight to the driver seat.
	global_transform = cabin_transform
	velocity = Vector3.ZERO
	vertical_velocity = 0.0
	grounded = true
	air_time = 0.0
	landing_time = 0.0
	safe_position = global_position
	reset_physics_interpolation()

func _drive_vehicle(delta: float) -> void:
	global_transform = driven_vehicle.driver_seat_transform()
	velocity = Vector3.ZERO
	var input := GameSession.movement_vector()
	var shift_up_pressed := Input.is_action_just_pressed("shift_up") or GameSession.consume_touch_press("shift_up")
	var shift_down_pressed := Input.is_action_just_pressed("shift_down") or GameSession.consume_touch_press("shift_down")
	if OS.has_feature("mobile") and (shift_up_pressed or shift_down_pressed):
		mobile_auto_clutch_timer = 0.34
	mobile_auto_clutch_timer = maxf(0.0, mobile_auto_clutch_timer - delta)
	var clutch_pressed := GameSession.is_action_pressed("clutch") or (OS.has_feature("mobile") and mobile_auto_clutch_timer > 0.0)
	driven_vehicle.submit_driver_input(peer_id, -input.y, input.x,
		GameSession.is_action_pressed("handbrake"), shift_up_pressed, shift_down_pressed,
		Input.is_action_just_pressed("winch_front") or GameSession.consume_touch_press("winch_front"),
		Input.is_action_just_pressed("winch_rear") or GameSession.consume_touch_press("winch_rear"),
		clutch_pressed,
		Input.is_action_just_pressed("primary") or GameSession.consume_touch_press("primary"))
	_apply_mobile_and_gamepad_look(delta, true)

func _apply_mobile_and_gamepad_look(delta: float, driving: bool) -> void:
	var swipe := GameSession.consume_touch_look()
	var stick := GameSession.look_vector()
	var touch_sensitivity := TOUCH_LOOK_SENSITIVITY * GameSession.touch_look_speed
	var yaw_change := swipe.x * touch_sensitivity + stick.x * delta * 2.6
	var pitch_change := swipe.y * touch_sensitivity + stick.y * delta * 2.2
	if absf(yaw_change) > 0.0001:
		if driving:
			head.rotation.y = clampf(head.rotation.y - yaw_change, -1.25, 1.25)
		else:
			rotate_y(-yaw_change)
	if absf(pitch_change) > 0.0001:
		look_pitch = clampf(look_pitch - pitch_change, -1.15, 1.15)
		head.rotation.x = look_pitch

func _update_body_animation(delta: float) -> void:
	if is_driving or (not body_rig and not body_animation):
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var target := "Idle"
	var blend := 0.14
	if just_jumped:
		target = "Jump"
		blend = 0.06
	elif not grounded:
		target = "Jump" if air_time < 0.20 and vertical_velocity > 0.0 else "Jump_Idle"
		blend = 0.08
	elif just_landed or landing_time > 0.0:
		target = "Jump_Land"
		blend = 0.06
		landing_time = maxf(0.0, landing_time - delta)
	elif horizontal_speed > 5.1:
		target = "Run"
	elif horizontal_speed > 0.25:
		target = "Walk"
	if body_rig:
		body_rig.set_locomotion(target, horizontal_speed, vertical_velocity, delta)
	if target == body_animation_name:
		return
	body_animation_name = target
	if body_animation and body_animation.has_animation(target):
		body_animation.speed_scale = 1.0
		body_animation.play(target, blend)

func _toggle_camera_mode() -> void:
	_apply_camera_mode(not third_person)
	GameSession.toast_requested.emit("THIRD-PERSON CAMERA" if third_person else "FIRST-PERSON CAMERA",
		"Swipe anywhere on the right side to look around.")

func _apply_camera_mode(use_third_person: bool) -> void:
	third_person = use_third_person
	camera = third_camera if third_person else first_camera
	camera.make_current()
	var local_player := peer_id == multiplayer.get_unique_id()
	if local_player:
		body_visual.visible = third_person and not is_driving
		# On-foot first person stays unobstructed; driving uses the RV's actual
		# cockpit geometry, while third person shows the complete animated survivor.
		hands_visual.visible = false
		# Physical cargo is rendered from cargo_mount in both camera modes; the old
		# placeholder plank mesh remains disabled.
		carried_visual.visible = false
		if driven_vehicle and driven_vehicle.has_method("set_local_driver_first_person"):
			driven_vehicle.set_local_driver_first_person(is_driving and not third_person)

func _update_winch_remote() -> void:
	var rig := GameSession.rv
	if not rig or not is_instance_valid(rig):
		return
	var reel_direction := 0.0
	if GameSession.is_action_pressed("winch_in"):
		reel_direction += 1.0
	if GameSession.is_action_pressed("winch_out"):
		reel_direction -= 1.0
	rig.set_winch_reel(peer_id, reel_direction)
	if is_driving:
		return
	var front_pressed := Input.is_action_just_pressed("winch_front") or GameSession.consume_touch_press("winch_front")
	var rear_pressed := Input.is_action_just_pressed("winch_rear") or GameSession.consume_touch_press("winch_rear")
	if not front_pressed and not rear_pressed:
		return
	interact_ray.force_raycast_update()
	var target := interact_ray.get_collider() if interact_ray.is_colliding() else null
	var anchor_node: Node = target
	while anchor_node and not anchor_node.is_in_group("winch_anchor"):
		anchor_node = anchor_node.get_parent()
	if not anchor_node or not anchor_node is Node3D:
		GameSession.toast_requested.emit("AIM AT ANCHOR", "Point the reticle at a marked tree or steel post.")
		return
	rig.attach_winch_from_player(peer_id, front_pressed, (anchor_node as Node3D).global_position)

func _update_carried_tool() -> void:
	if is_driving:
		return
	var use_pressed := Input.is_action_just_pressed("tool_use") or GameSession.consume_touch_press("tool_use")
	if not use_pressed:
		return
	if not has_carried_tool("extinguisher"):
		GameSession.toast_requested.emit("NO ACTIVE TOOL", "Carry a fire extinguisher before using this control.")
		return
	var rig := GameSession.rv
	if not rig or global_position.distance_to(rig.global_position) > 8.0:
		GameSession.toast_requested.emit("TOO FAR", "Move closer to the burning RV.")
		return
	if rig.fire_level <= 0.0:
		GameSession.toast_requested.emit("NO FIRE", "Save the remaining extinguisher charge.")
		return
	if not carried_object.use_charge():
		GameSession.toast_requested.emit("EXTINGUISHER EMPTY", "Find another extinguisher.")
		return
	rig.extinguish(24.0)
	GameSession.toast_requested.emit("FIRE SUPPRESSED", "%d extinguisher bursts remaining." % carried_object.uses_remaining)

func _update_interaction() -> void:
	# Consume a touch pulse exactly once even when no target is present; otherwise
	# a stale USE tap could trigger later when the player approached an object.
	var interact_pressed := Input.is_action_just_pressed("interact") or GameSession.consume_touch_press("interact")
	if is_driving:
		interaction_text = "EXIT DRIVER SEAT"
		if interact_pressed:
			driven_vehicle.exit_driver(self)
		return
	interaction_text = ""
	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding():
		if carried_object and is_instance_valid(carried_object):
			interaction_text = "DROP %s" % carried_item.to_upper()
			if interact_pressed:
				drop_carried_cargo()
		return
	var target := interact_ray.get_collider()
	if target and target.has_method("interact"):
		var target_prompt = target.get("prompt")
		interaction_text = str(target_prompt) if target_prompt != null else "INTERACT"
		if interact_pressed:
			target.interact(self)
	elif carried_object and is_instance_valid(carried_object):
		interaction_text = "DROP %s" % carried_item.to_upper()
		if interact_pressed:
			drop_carried_cargo()

func pick_up_cargo(cargo: PhysicsCargo) -> void:
	if carried_object and is_instance_valid(carried_object):
		GameSession.toast_requested.emit("HANDS FULL", "Drop the current cargo before carrying another item.")
		return
	carried_object = cargo
	carried_item = cargo.cargo_kind
	cargo.attach_to_carrier(self, cargo_mount)
	update_carried_visual()
	GameSession.toast_requested.emit("CARGO LIFTED", "Carry it into the RV or to a matching worksite.")

func drop_carried_cargo() -> void:
	if not carried_object or not is_instance_valid(carried_object):
		carried_object = null
		carried_item = ""
		return
	var cargo := carried_object
	carried_object = null
	carried_item = ""
	var forward := -head.global_transform.basis.z.normalized()
	var drop_position := head.global_position + forward * 1.45 - Vector3.UP * 0.55
	var drop_basis := Basis(Vector3.UP, global_rotation.y)
	var inherited := velocity
	if Net.world and Net.world.rv and Net.world.rv.contains_cabin_point(global_position):
		inherited += Net.world.rv.linear_velocity
	cargo.drop_from_carrier(Net.world if Net.world else get_parent(), Transform3D(drop_basis, drop_position), inherited)
	update_carried_visual()

func has_carried_tool(expected_kind: String) -> bool:
	return carried_item == expected_kind and carried_object != null and is_instance_valid(carried_object)

func consume_carried_cargo(expected_kind: String) -> bool:
	if not has_carried_tool(expected_kind):
		return false
	var cargo := carried_object
	carried_object = null
	carried_item = ""
	cargo.consume()
	update_carried_visual()
	return true

func enter_driver(vehicle: Node) -> void:
	is_driving = true
	driven_vehicle = vehicle
	head.rotation = Vector3.ZERO
	look_pitch = 0.0
	spring_arm.add_excluded_object(vehicle.get_rid())
	# Gamer-facing rear three-quarter view: the pivot stays near window height and
	# the arm trails just beyond the eight-metre coach. The previous high pivot
	# turned the physical phone view into an unusable roof inspection camera.
	spring_arm.spring_length = 10.8
	spring_arm.position = Vector3(-0.40, -0.05, 0.30)
	spring_arm.rotation = Vector3(-0.08, 0.22, 0.0)
	third_camera.fov = 68.0
	$CollisionShape3D.set_deferred("disabled", true)
	body_visual.visible = false
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(third_person)
	GameSession.toast_requested.emit("DRIVER SEAT", "Drive with the left stick, swipe to look, and tap VIEW for chase camera.")

func leave_driver(exit_transform: Transform3D) -> void:
	if driven_vehicle and driven_vehicle.has_method("set_local_driver_first_person"):
		driven_vehicle.set_local_driver_first_person(false)
	is_driving = false
	driven_vehicle = null
	spring_arm.clear_excluded_objects()
	spring_arm.add_excluded_object(get_rid())
	spring_arm.spring_length = 4.2
	spring_arm.position = Vector3(0.0, 0.30, 0.0)
	spring_arm.rotation = Vector3.ZERO
	global_transform = exit_transform
	$CollisionShape3D.set_deferred("disabled", false)
	head.rotation = Vector3.ZERO
	look_pitch = 0.0
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(third_person)
	else:
		body_visual.visible = true

func update_carried_visual() -> void:
	# Cargo itself is now the visual and physical object. Keep the legacy mesh
	# hidden so first person never renders two overlapping planks.
	carried_visual.visible = false
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(third_person)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _sync_state(new_transform: Transform3D, new_velocity: Vector3, driving: bool) -> void:
	remote_target = new_transform
	velocity = new_velocity
	is_driving = driving

func _build_player() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.42
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	# A 0.76 m-wide collider left almost no tolerance in the real 1.04 m coach
	# doorway. This shoulder-width capsule remains stable but gives touch steering
	# enough margin to climb the steps without snagging either jamb.
	capsule.radius = 0.30
	capsule.height = 1.78
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	body_rig = ProfessionalCrewVisualScript.new()
	body_visual = body_rig
	body_visual.name = "ProfessionalExpeditionCrew"
	# Quaternius faces +Z; gameplay forward is -Z.
	body_visual.rotation.y = PI
	body_visual.scale = Vector3.ONE * 0.98
	add_child(body_visual)
	body_animation = null
	body_animation_name = "Idle"

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.62
	add_child(head)
	first_camera = Camera3D.new()
	first_camera.name = "FirstPersonCamera"
	first_camera.fov = 76.0
	first_camera.near = 0.030
	head.add_child(first_camera)
	camera = first_camera
	cargo_mount = Node3D.new()
	cargo_mount.name = "PhysicalCargoMount"
	head.add_child(cargo_mount)

	spring_arm = SpringArm3D.new()
	spring_arm.name = "ThirdPersonSpringArm"
	spring_arm.spring_length = 4.2
	spring_arm.margin = 0.22
	spring_arm.collision_mask = 1 | 4 | 8
	spring_arm.position = Vector3(0.0, 0.30, 0.0)
	head.add_child(spring_arm)
	spring_arm.add_excluded_object(get_rid())
	third_camera = Camera3D.new()
	third_camera.name = "ThirdPersonCamera"
	third_camera.fov = 70.0
	third_camera.near = 0.10
	spring_arm.add_child(third_camera)

	hands_visual = HANDS_SCENE.instantiate() as Node3D
	hands_visual.name = "FirstPersonHands"
	# Keep hands as a subtle lower-screen frame rather than the giant forearms
	# that obscured most of the phone display.
	hands_visual.scale = Vector3.ONE * 0.46
	hands_visual.position = Vector3(0.0, -0.10, 0.08)
	hands_visual.visible = false
	camera.add_child(hands_visual)
	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0.0, 0.0, -4.2)
	interact_ray.collision_mask = 1 | 4 | 8
	interact_ray.collide_with_areas = true
	head.add_child(interact_ray)

	carried_visual = MeshInstance3D.new()
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(1.55, 0.12, 0.32)
	carried_visual.mesh = plank_mesh
	carried_visual.material_override = PrimitiveFactory.material(Color("9a693d"))
	carried_visual.position = Vector3(0.45, -0.42, -1.1)
	carried_visual.rotation = Vector3(0.15, -0.2, 0.28)
	carried_visual.visible = false
	camera.add_child(carried_visual)

	nameplate = PrimitiveFactory.label_3d(self, "%s\n%s" % [player_name, _role_name()], Vector3(0.0, 2.2, 0.0), Color.WHITE, 34)

func _role_name() -> String:
	return ["DRIVER", "MECHANIC", "SCOUT", "NAVIGATOR"][role % 4]

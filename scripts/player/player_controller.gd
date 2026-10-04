class_name ExpeditionPlayer
extends CharacterBody3D
## Stable single-player explorer with first/third-person mobile controls.

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const JUMP_FORCE := 6.2
const LOOK_SENSITIVITY := 0.0024
const TOUCH_LOOK_SENSITIVITY := 0.0042
const StylizedCrewVisualScript = preload("res://scripts/player/stylized_crew_visual.gd")
const HANDS_SCENE: PackedScene = preload("res://assets/models/first_person_hands.gltf")

var peer_id := 1
var player_name := "Rover"
var role := 0
var is_driving := false
var driven_vehicle: Node
var carried_item := ""
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
var body_rig: StylizedCrewVisual
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
	if Input.is_action_just_pressed("toggle_view") or GameSession.consume_touch_press("toggle_view"):
		_toggle_camera_mode()
	if is_driving and driven_vehicle:
		_drive_vehicle(delta)
	else:
		_move_on_foot(delta)
	_update_body_animation(delta)
	_update_interaction()
	if Net.is_online:
		_sync_state.rpc(transform, velocity, is_driving)

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

func _drive_vehicle(delta: float) -> void:
	global_transform = driven_vehicle.driver_seat_transform()
	velocity = Vector3.ZERO
	var input := GameSession.movement_vector()
	driven_vehicle.submit_driver_input(peer_id, -input.y, input.x,
		GameSession.is_action_pressed("handbrake"),
		Input.is_action_just_pressed("shift_up") or GameSession.consume_touch_press("shift_up"),
		Input.is_action_just_pressed("shift_down") or GameSession.consume_touch_press("shift_down"),
		Input.is_action_just_pressed("winch_front") or GameSession.consume_touch_press("winch_front"),
		Input.is_action_just_pressed("winch_rear") or GameSession.consume_touch_press("winch_rear"))
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
		carried_visual.visible = not third_person and carried_item == "plank"
		if driven_vehicle and driven_vehicle.has_method("set_local_driver_first_person"):
			driven_vehicle.set_local_driver_first_person(is_driving and not third_person)

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
		return
	var target := interact_ray.get_collider()
	if target and target.has_method("interact"):
		var target_prompt = target.get("prompt")
		interaction_text = str(target_prompt) if target_prompt != null else "INTERACT"
		if interact_pressed:
			target.interact(self)

func enter_driver(vehicle: Node) -> void:
	is_driving = true
	driven_vehicle = vehicle
	head.rotation = Vector3.ZERO
	look_pitch = 0.0
	spring_arm.add_excluded_object(vehicle.get_rid())
	spring_arm.spring_length = 8.4
	spring_arm.position = Vector3(-0.53, 1.10, 1.10)
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
	global_transform = exit_transform
	$CollisionShape3D.set_deferred("disabled", false)
	head.rotation = Vector3.ZERO
	look_pitch = 0.0
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(third_person)
	else:
		body_visual.visible = true

func update_carried_visual() -> void:
	if peer_id == multiplayer.get_unique_id():
		_apply_camera_mode(third_person)
	else:
		carried_visual.visible = carried_item == "plank"

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
	capsule.radius = 0.38
	capsule.height = 1.78
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	body_rig = StylizedCrewVisualScript.new()
	body_visual = body_rig
	body_visual.name = "RoundedExpeditionCrew"
	body_visual.rotation.y = PI
	body_visual.scale = Vector3.ONE * 0.82
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
	first_camera.near = 0.045
	head.add_child(first_camera)
	camera = first_camera

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

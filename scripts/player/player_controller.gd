class_name ExpeditionPlayer
extends CharacterBody3D
## First-person co-op explorer with physical interaction and mobile controls.

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const JUMP_FORCE := 6.2
const LOOK_SENSITIVITY := 0.0024
const CREW_SCENE: PackedScene = preload("res://assets/models/crew_member.gltf")
const HANDS_SCENE: PackedScene = preload("res://assets/models/first_person_hands.gltf")
const COCKPIT_SCENE: PackedScene = preload("res://assets/models/rv_cockpit.gltf")

var peer_id := 1
var player_name := "Rover"
var role := 0
var is_driving := false
var driven_vehicle: Node
var carried_item := ""
var interaction_text := ""
var remote_target := Transform3D.IDENTITY
var look_pitch := 0.0
var head: Node3D
var camera: Camera3D
var interact_ray: RayCast3D
var body_visual: Node3D
var carried_visual: MeshInstance3D
var hands_visual: Node3D
var cockpit_visual: Node3D
var nameplate: Label3D
var voice: ProximityVoice

func setup(id: int, display_name: String, selected_role: int, spawn_position: Vector3) -> void:
	peer_id = id
	player_name = display_name
	role = selected_role
	name = "Player_%d" % peer_id
	position = spawn_position
	remote_target = transform
	set_multiplayer_authority(peer_id)
	_build_player()
	if peer_id == multiplayer.get_unique_id():
		camera.make_current()
		body_visual.visible = false
		nameplate.visible = false
		hands_visual.visible = true
		GameSession.register_local_player(self)
		call_deferred("_ensure_local_camera")
		if not OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	if peer_id != multiplayer.get_unique_id() or is_driving:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * LOOK_SENSITIVITY)
		look_pitch = clampf(look_pitch - event.relative.y * LOOK_SENSITIVITY, -1.35, 1.35)
		head.rotation.x = look_pitch

func _physics_process(delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		transform = transform.interpolate_with(remote_target, minf(1.0, delta * 13.0))
		return
	if is_driving and driven_vehicle:
		_drive_vehicle(delta)
	else:
		_move_on_foot(delta)
	_update_interaction()
	_sync_state.rpc(transform, velocity, is_driving)

func _move_on_foot(delta: float) -> void:
	var input := GameSession.movement_vector()
	var direction := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if GameSession.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 22.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 22.0 * delta)
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	elif Input.is_action_just_pressed("jump") or GameSession.consume_touch_press("jump"):
		velocity.y = JUMP_FORCE
	move_and_slide()
	var look := GameSession.look_vector()
	if look.length_squared() > 0.002:
		rotate_y(-look.x * delta * 2.6)
		look_pitch = clampf(look_pitch - look.y * delta * 2.2, -1.35, 1.35)
		head.rotation.x = look_pitch

func _drive_vehicle(_delta: float) -> void:
	global_transform = driven_vehicle.driver_seat_transform()
	velocity = Vector3.ZERO
	var input := GameSession.movement_vector()
	driven_vehicle.submit_driver_input(peer_id, -input.y, input.x,
		GameSession.is_action_pressed("handbrake"),
		Input.is_action_just_pressed("shift_up") or GameSession.consume_touch_press("shift_up"),
		Input.is_action_just_pressed("shift_down") or GameSession.consume_touch_press("shift_down"),
		Input.is_action_just_pressed("winch_front") or GameSession.consume_touch_press("winch_front"),
		Input.is_action_just_pressed("winch_rear") or GameSession.consume_touch_press("winch_rear"))
	var look := GameSession.look_vector()
	if look.length_squared() > 0.002:
		look_pitch = clampf(look_pitch - look.y * 0.035, -0.8, 0.8)
		head.rotation = Vector3(look_pitch, clampf(-look.x * 0.6, -1.0, 1.0), 0.0)
	else:
		head.rotation.y = lerpf(head.rotation.y, 0.0, 0.1)

func _update_interaction() -> void:
	if is_driving:
		interaction_text = "EXIT DRIVER SEAT"
		if Input.is_action_just_pressed("interact") or GameSession.consume_touch_press("interact"):
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
		if Input.is_action_just_pressed("interact") or GameSession.consume_touch_press("interact"):
			target.interact(self)

func enter_driver(vehicle: Node) -> void:
	is_driving = true
	driven_vehicle = vehicle
	$CollisionShape3D.set_deferred("disabled", true)
	body_visual.visible = false
	hands_visual.visible = false
	cockpit_visual.visible = true
	GameSession.toast_requested.emit("DRIVER SEAT", "Use the left stick to steer and drive. Shift with GEAR − / GEAR +.")

func leave_driver(exit_transform: Transform3D) -> void:
	is_driving = false
	driven_vehicle = null
	global_transform = exit_transform
	$CollisionShape3D.set_deferred("disabled", false)
	head.rotation = Vector3.ZERO
	look_pitch = 0.0
	body_visual.visible = peer_id != multiplayer.get_unique_id()
	hands_visual.visible = peer_id == multiplayer.get_unique_id()
	cockpit_visual.visible = false

func update_carried_visual() -> void:
	carried_visual.visible = carried_item == "plank"
	if peer_id == multiplayer.get_unique_id() and not is_driving:
		hands_visual.visible = carried_item.is_empty()

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _sync_state(new_transform: Transform3D, new_velocity: Vector3, driving: bool) -> void:
	remote_target = new_transform
	velocity = new_velocity
	is_driving = driving

func _build_player() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.78
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	body_visual = CREW_SCENE.instantiate() as Node3D
	body_visual.name = "TexturedCrewModel"
	body_visual.scale = Vector3.ONE * 0.82
	body_visual.rotation.y = PI
	add_child(body_visual)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.62
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 76.0
	camera.near = 0.045
	head.add_child(camera)

	hands_visual = HANDS_SCENE.instantiate() as Node3D
	hands_visual.name = "FirstPersonHands"
	hands_visual.visible = false
	camera.add_child(hands_visual)
	cockpit_visual = COCKPIT_SCENE.instantiate() as Node3D
	cockpit_visual.name = "DriverCockpit"
	cockpit_visual.visible = false
	camera.add_child(cockpit_visual)

	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0.0, 0.0, -3.6)
	interact_ray.collision_mask = 1 | 4 | 8
	interact_ray.collide_with_areas = true
	camera.add_child(interact_ray)

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

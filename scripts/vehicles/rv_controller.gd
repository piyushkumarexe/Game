class_name ExpeditionRV
extends VehicleBody3D
## Server-authoritative four-wheel RV with manual gears, damage and twin winches.

signal stats_changed(health: float, fuel: float, gear: int, speed: float)

const GEAR_RATIOS := [-0.62, 0.0, 0.68, 0.92, 1.16, 1.38, 1.55]
const MAX_ENGINE_FORCE := 5200.0
const MAX_STEER := 0.46
const MAX_FUEL := 100.0

var prompt := "DRIVE THE RV"
var health := 100.0
var fuel := 100.0
var gear := 2
var engine_running := false
var driver_peer_id := 0
var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false
var command_front_winch := false
var command_rear_winch := false
var front_winch := {"active": false, "anchor": Vector3.ZERO, "length": 0.0}
var rear_winch := {"active": false, "anchor": Vector3.ZERO, "length": 0.0}
var front_cable: MeshInstance3D
var rear_cable: MeshInstance3D
var engine_audio: AudioStreamPlayer3D
var engine_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var last_impact_time := -10.0
var start_transform := Transform3D.IDENTITY
var body_shell: Node3D
var bumper_visual: Node3D
var roof_crate: Node3D

func setup(spawn_transform: Transform3D) -> void:
	name = "ExpeditionRV"
	mass = 3100.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.55, 0.18)
	contact_monitor = true
	max_contacts_reported = 12
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	global_transform = spawn_transform
	start_transform = spawn_transform
	_build_rv()
	body_entered.connect(_on_body_entered)
	_setup_engine_audio()

func _ready() -> void:
	front_cable = _create_cable("FrontCable")
	rear_cable = _create_cable("RearCable")

func _physics_process(delta: float) -> void:
	if Net.is_online and not multiplayer.is_server():
		_fill_engine_audio()
		return
	_simulate_driver(delta)
	_simulate_winch(front_winch, _front_hook_position(), delta)
	_simulate_winch(rear_winch, _rear_hook_position(), delta)
	_update_cable(front_cable, front_winch, _front_hook_position())
	_update_cable(rear_cable, rear_winch, _rear_hook_position())
	_fill_engine_audio()
	if Net.is_online:
		_sync_rv.rpc(global_transform, linear_velocity, angular_velocity, health, fuel, gear, engine_running, driver_peer_id,
			front_winch, rear_winch)
	stats_changed.emit(health, fuel, gear, linear_velocity.length() * 3.6)

func submit_driver_input(peer_id: int, throttle: float, steering_input: float, handbrake_pressed: bool,
	shift_up_pressed: bool, shift_down_pressed: bool, front_pressed := false, rear_pressed := false) -> void:
	if Net.is_online and not multiplayer.is_server():
		_receive_driver_input.rpc_id(1, peer_id, throttle, steering_input, handbrake_pressed,
			shift_up_pressed, shift_down_pressed, front_pressed, rear_pressed)
		return
	_apply_driver_input(peer_id, throttle, steering_input, handbrake_pressed,
		shift_up_pressed, shift_down_pressed, front_pressed, rear_pressed)

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _receive_driver_input(peer_id: int, throttle: float, steering_input: float, handbrake_pressed: bool,
	shift_up_pressed: bool, shift_down_pressed: bool, front_pressed: bool, rear_pressed: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_apply_driver_input(peer_id, throttle, steering_input, handbrake_pressed,
			shift_up_pressed, shift_down_pressed, front_pressed, rear_pressed)

func _apply_driver_input(peer_id: int, throttle: float, steering_input: float, handbrake_pressed: bool,
	shift_up_pressed: bool, shift_down_pressed: bool, front_pressed: bool, rear_pressed: bool) -> void:
	if peer_id != driver_peer_id:
		return
	throttle_input = clampf(throttle, -1.0, 1.0)
	steer_input = clampf(steering_input, -1.0, 1.0)
	handbrake_input = handbrake_pressed
	if shift_up_pressed:
		gear = mini(GEAR_RATIOS.size() - 1, gear + 1)
	if shift_down_pressed:
		gear = maxi(0, gear - 1)
	if front_pressed:
		_toggle_winch(front_winch, true)
	if rear_pressed:
		_toggle_winch(rear_winch, false)

func interact(player: Node) -> void:
	if driver_peer_id != 0:
		GameSession.toast_requested.emit("DRIVER SEAT OCCUPIED", "Someone is already wrestling the wheel.")
		return
	if Net.is_online and not multiplayer.is_server():
		_request_driver.rpc_id(1, player.peer_id)
	else:
		_assign_driver.rpc(player.peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_driver(requested_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == requested_peer and driver_peer_id == 0:
		_assign_driver.rpc(requested_peer)

@rpc("authority", "call_local", "reliable")
func _assign_driver(id: int) -> void:
	driver_peer_id = id
	engine_running = true
	var player := Net.world.get_player(id) if Net.world else null
	if player:
		player.enter_driver(self)
	if multiplayer.is_server() or not Net.is_online:
		GameSession.complete_target("engine")

func exit_driver(player: Node) -> void:
	if player.peer_id != driver_peer_id:
		return
	if Net.is_online and not multiplayer.is_server():
		_request_exit.rpc_id(1, player.peer_id)
	else:
		_release_driver.rpc(player.peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_exit(requested_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == requested_peer:
		_release_driver.rpc(requested_peer)

@rpc("authority", "call_local", "reliable")
func _release_driver(id: int) -> void:
	var player := Net.world.get_player(id) if Net.world else null
	if player:
		player.leave_driver(exit_seat_transform())
	driver_peer_id = 0
	throttle_input = 0.0
	brake = 55.0

func driver_seat_transform() -> Transform3D:
	var seat := global_transform * Transform3D(Basis.IDENTITY, Vector3(0.58, 1.05, -1.65))
	return seat

func exit_seat_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(-2.2, 0.1, -0.8))

func repair(value: float) -> void:
	health = minf(100.0, health + value)
	_update_damage_visuals()

func add_fuel(value: float) -> void:
	fuel = minf(MAX_FUEL, fuel + value)

func respawn_at(new_transform: Transform3D) -> void:
	global_transform = new_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	health = maxf(health, 55.0)
	fuel = maxf(fuel, 35.0)

func damage(value: float, source := "IMPACT") -> void:
	if Time.get_ticks_msec() / 1000.0 - last_impact_time < 0.35:
		return
	last_impact_time = Time.get_ticks_msec() / 1000.0
	health = maxf(0.0, health - value)
	_update_damage_visuals()
	GameSession.toast_requested.emit(source, "RV frame -%d" % roundi(value))
	if health <= 0.0:
		GameSession.run_finished.emit(false)

func _simulate_driver(delta: float) -> void:
	steering = move_toward(steering, steer_input * MAX_STEER, delta * 1.8)
	if not engine_running or fuel <= 0.0 or health <= 0.0 or gear == 1:
		engine_force = 0.0
	else:
		var health_factor := lerpf(0.42, 1.0, health / 100.0)
		engine_force = throttle_input * GEAR_RATIOS[gear] * MAX_ENGINE_FORCE * health_factor
		fuel = maxf(0.0, fuel - absf(throttle_input) * delta * 0.16)
	brake = 72.0 if handbrake_input else (18.0 if absf(throttle_input) < 0.05 else 0.0)
	if global_position.y < -24.0 or global_transform.basis.y.dot(Vector3.UP) < -0.55:
		if linear_velocity.length() < 1.0:
			respawn_at(Net.world.last_checkpoint_transform if Net.world else start_transform)

func _toggle_winch(data: Dictionary, front: bool) -> void:
	if bool(data["active"]):
		data["active"] = false
		return
	var hook := _front_hook_position() if front else _rear_hook_position()
	var anchor := _nearest_winch_anchor(hook, 22.0)
	if anchor == Vector3.INF:
		GameSession.toast_requested.emit("NO CABLE ANCHOR", "Move within 22 m of a marked tree or steel post.")
		return
	data["active"] = true
	data["anchor"] = anchor
	data["length"] = hook.distance_to(anchor) * 0.72
	GameSession.toast_requested.emit("%s CABLE ATTACHED" % ("FRONT" if front else "REAR"), "Throttle gently while the winch pulls.")
	GameSession.complete_target("winch")

func _simulate_winch(data: Dictionary, hook: Vector3, delta: float) -> void:
	if not bool(data["active"]):
		return
	var anchor: Vector3 = data["anchor"]
	var distance := hook.distance_to(anchor)
	if distance > float(data["length"]):
		var tension := clampf((distance - float(data["length"])) * 0.65, 0.0, 1.0)
		var force := hook.direction_to(anchor) * 11500.0 * tension
		apply_force(force, hook - global_position)
		data["length"] = maxf(2.8, float(data["length"]) - delta * 1.45)
	if distance > 34.0:
		data["active"] = false

func _nearest_winch_anchor(from: Vector3, max_distance: float) -> Vector3:
	var best := Vector3.INF
	var best_distance := max_distance
	for anchor: Node in get_tree().get_nodes_in_group("winch_anchor"):
		if not anchor is Node3D:
			continue
		var distance := from.distance_to(anchor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = anchor.global_position
	return best

func _front_hook_position() -> Vector3:
	return global_transform * Vector3(0.0, -0.15, -3.0)

func _rear_hook_position() -> Vector3:
	return global_transform * Vector3(0.0, -0.12, 3.0)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _sync_rv(new_transform: Transform3D, new_linear: Vector3, new_angular: Vector3, new_health: float,
	new_fuel: float, new_gear: int, running: bool, driver_id: int, front_data: Dictionary, rear_data: Dictionary) -> void:
	global_transform = global_transform.interpolate_with(new_transform, 0.42)
	linear_velocity = new_linear
	angular_velocity = new_angular
	health = new_health
	fuel = new_fuel
	gear = new_gear
	engine_running = running
	driver_peer_id = driver_id
	front_winch = front_data.duplicate(true)
	rear_winch = rear_data.duplicate(true)
	_update_cable(front_cable, front_winch, _front_hook_position())
	_update_cable(rear_cable, rear_winch, _rear_hook_position())
	_update_damage_visuals()
	stats_changed.emit(health, fuel, gear, linear_velocity.length() * 3.6)

func _on_body_entered(_body: Node) -> void:
	var impact := linear_velocity.length()
	if impact > 7.5 and (multiplayer.is_server() or not Net.is_online):
		damage(clampf((impact - 6.5) * 1.45, 3.0, 19.0), "TRAIL IMPACT")

func _create_cable(cable_name: String) -> MeshInstance3D:
	var cable := MeshInstance3D.new()
	cable.name = cable_name
	cable.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e1c188")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	cable.material_override = mat
	get_parent().call_deferred("add_child", cable)
	return cable

func _update_cable(cable: MeshInstance3D, data: Dictionary, hook: Vector3) -> void:
	if not cable or not is_instance_valid(cable) or not cable.is_inside_tree():
		return
	var mesh := cable.mesh as ImmediateMesh
	mesh.clear_surfaces()
	cable.visible = bool(data["active"])
	if not bool(data["active"]):
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(hook)
	mesh.surface_add_vertex(data["anchor"])
	mesh.surface_end()

func _setup_engine_audio() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.25
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.stream = generator
	engine_audio.bus = "Engine"
	engine_audio.max_distance = 32.0
	add_child(engine_audio)
	engine_audio.play()
	engine_playback = engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback

func _fill_engine_audio() -> void:
	if not engine_playback:
		return
	var available := mini(engine_playback.get_frames_available(), 512)
	var rpm := 34.0 + linear_velocity.length() * 2.6 + absf(throttle_input) * 28.0
	var volume := 0.035 if engine_running else 0.0
	for _index in available:
		audio_phase = fmod(audio_phase + rpm / 22050.0, 1.0)
		var fundamental := sin(audio_phase * TAU)
		var harmonic := sin(audio_phase * TAU * 2.0) * 0.34
		var sample := (fundamental + harmonic) * volume
		engine_playback.push_frame(Vector2(sample, sample))

func _update_damage_visuals() -> void:
	if bumper_visual:
		bumper_visual.visible = health > 38.0
	if roof_crate:
		roof_crate.rotation.z = lerpf(0.0, 0.25, 1.0 - health / 100.0)
	if body_shell:
		body_shell.rotation.z = lerpf(0.0, -0.025, 1.0 - health / 100.0)

func _build_rv() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.45, 2.15, 5.35)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.62, 0.0)
	add_child(collision)

	body_shell = Node3D.new()
	body_shell.name = "OriginalRVBody"
	add_child(body_shell)
	PrimitiveFactory.box(body_shell, "Coach", Vector3(0.0, 0.72, 0.22), Vector3(2.5, 2.05, 5.4), Color("e8dec1"))
	PrimitiveFactory.box(body_shell, "OrangeStripe", Vector3(0.0, 0.55, -0.04), Vector3(2.55, 0.42, 5.46), Color("b95032"))
	PrimitiveFactory.box(body_shell, "Cab", Vector3(0.0, 0.3, -2.65), Vector3(2.42, 1.25, 1.12), Color("ded5bb"))
	PrimitiveFactory.box(body_shell, "Windshield", Vector3(0.0, 1.03, -2.735), Vector3(1.78, 0.62, 0.05), Color("263c44"))
	PrimitiveFactory.box(body_shell, "LeftWindow", Vector3(-1.265, 1.05, -0.7), Vector3(0.04, 0.72, 1.04), Color("34535a"))
	PrimitiveFactory.box(body_shell, "RightWindow", Vector3(1.265, 1.05, -0.7), Vector3(0.04, 0.72, 1.04), Color("34535a"))
	PrimitiveFactory.box(body_shell, "SideWindowA", Vector3(-1.265, 1.02, 0.72), Vector3(0.04, 0.68, 0.78), Color("496970"))
	PrimitiveFactory.box(body_shell, "SideWindowB", Vector3(-1.265, 1.02, 1.78), Vector3(0.04, 0.68, 0.78), Color("496970"))
	PrimitiveFactory.box(body_shell, "Door", Vector3(1.27, 0.45, 1.25), Vector3(0.04, 1.55, 0.82), Color("d7ccb0"))
	PrimitiveFactory.box(body_shell, "RoofRack", Vector3(0.0, 1.87, 0.5), Vector3(2.0, 0.08, 3.2), Color("35383a"))
	roof_crate = PrimitiveFactory.box(body_shell, "RoofCargo", Vector3(-0.42, 2.08, 0.6), Vector3(0.85, 0.42, 1.15), Color("6f4132"))
	bumper_visual = PrimitiveFactory.box(body_shell, "FrontBumper", Vector3(0.0, -0.08, -3.18), Vector3(2.6, 0.24, 0.28), Color("55595b"))
	PrimitiveFactory.box(body_shell, "RearBumper", Vector3(0.0, -0.08, 3.02), Vector3(2.55, 0.24, 0.25), Color("55595b"))
	PrimitiveFactory.box(body_shell, "HeadlightL", Vector3(-0.82, 0.28, -3.22), Vector3(0.34, 0.26, 0.08), Color("f7d47d"))
	PrimitiveFactory.box(body_shell, "HeadlightR", Vector3(0.82, 0.28, -3.22), Vector3(0.34, 0.26, 0.08), Color("f7d47d"))

	_add_wheel("FrontLeft", Vector3(-1.18, -0.62, -1.82), true, false)
	_add_wheel("FrontRight", Vector3(1.18, -0.62, -1.82), true, false)
	_add_wheel("RearLeft", Vector3(-1.18, -0.62, 1.78), false, true)
	_add_wheel("RearRight", Vector3(1.18, -0.62, 1.78), false, true)

func _add_wheel(wheel_name: String, wheel_position: Vector3, steering_wheel: bool, traction_wheel: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = wheel_position
	wheel.wheel_radius = 0.56
	wheel.wheel_rest_length = 0.32
	wheel.suspension_travel = 0.35
	wheel.suspension_stiffness = 28.0
	wheel.suspension_max_force = 9000.0
	wheel.damping_compression = 0.42
	wheel.damping_relaxation = 0.55
	wheel.wheel_friction_slip = 2.25
	wheel.use_as_steering = steering_wheel
	wheel.use_as_traction = traction_wheel
	add_child(wheel)
	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = 0.56
	tire_mesh.bottom_radius = 0.56
	tire_mesh.height = 0.34
	tire_mesh.radial_segments = 16
	tire.mesh = tire_mesh
	tire.rotation.z = PI * 0.5
	tire.material_override = PrimitiveFactory.material(Color("16181c"), 0.95)
	wheel.add_child(tire)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.21
	hub_mesh.bottom_radius = 0.21
	hub_mesh.height = 0.37
	hub_mesh.radial_segments = 10
	hub.mesh = hub_mesh
	hub.rotation.z = PI * 0.5
	hub.material_override = PrimitiveFactory.material(Color("a9a795"), 0.45, 0.6)
	wheel.add_child(hub)

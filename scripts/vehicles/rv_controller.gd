class_name ExpeditionRV
extends VehicleBody3D
## Server-authoritative four-wheel RV with manual gears, damage and twin winches.

signal stats_changed(health: float, fuel: float, gear: int, speed: float)

const GEAR_RATIOS := [-0.62, 0.0, 0.68, 0.92, 1.16, 1.38, 1.55]
const MAX_ENGINE_FORCE := 4300.0
const MAX_STEER := 0.43
const MAX_FUEL := 100.0
const MAX_SAFE_SPEED := 32.0
const RV_EXTERIOR_SCENE: PackedScene = preload("res://assets/models/rv_exterior.gltf")

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
var safe_spawn_seconds := 2.5
var upside_down_seconds := 0.0
var start_transform := Transform3D.IDENTITY
var body_shell: Node3D
var bumper_visual: Node3D
var roof_crate: Node3D
var stats_emit_accumulator := 0.0

func setup(spawn_transform: Transform3D) -> void:
	name = "ExpeditionRV"
	mass = 3600.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.82, 0.18)
	linear_damp = 0.18
	angular_damp = 2.8
	continuous_cd = true
	can_sleep = true
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
	safe_spawn_seconds = maxf(0.0, safe_spawn_seconds - delta)
	_stabilize_motion()
	_simulate_driver(delta)
	_simulate_winch(front_winch, _front_hook_position(), delta)
	_simulate_winch(rear_winch, _rear_hook_position(), delta)
	_update_cable(front_cable, front_winch, _front_hook_position())
	_update_cable(rear_cable, rear_winch, _rear_hook_position())
	_fill_engine_audio()
	if Net.is_online:
		_sync_rv.rpc(global_transform, linear_velocity, angular_velocity, health, fuel, gear, engine_running, driver_peer_id,
			front_winch, rear_winch)
	# Text layout and signal fan-out at 60 Hz wastes mobile CPU. Ten updates per
	# second is visually smooth for HUD meters and leaves time for physics/render.
	stats_emit_accumulator += delta
	if stats_emit_accumulator >= 0.10:
		stats_emit_accumulator = 0.0
		stats_changed.emit(health, fuel, gear, _hud_speed_kmh())

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
	if GameSession.supplies_loaded < 3:
		GameSession.toast_requested.emit("PACK BEFORE DEPARTURE",
			"Load all 3 marked supply crates before starting the RV.")
		return
	if Net.is_online and not multiplayer.is_server():
		_request_driver.rpc_id(1, player.peer_id)
	else:
		_assign_driver.rpc(player.peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_driver(requested_peer: int) -> void:
	if (multiplayer.is_server()
			and multiplayer.get_remote_sender_id() == requested_peer
			and driver_peer_id == 0
			and GameSession.supplies_loaded >= 3):
		_assign_driver.rpc(requested_peer)

@rpc("authority", "call_local", "reliable")
func _assign_driver(id: int) -> void:
	driver_peer_id = id
	engine_running = true
	var player: Node = Net.world.get_player(id) if Net.world else null
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
	var player: Node = Net.world.get_player(id) if Net.world else null
	if player:
		player.leave_driver(exit_seat_transform())
	driver_peer_id = 0
	throttle_input = 0.0
	brake = 55.0

func set_local_driver_first_person(active: bool) -> void:
	if body_shell:
		body_shell.visible = not active

func driver_seat_transform() -> Transform3D:
	# The player camera is 1.62 m above its origin. Offset the character origin so
	# the actual viewpoint sits naturally behind the windshield.
	var seat := global_transform * Transform3D(Basis.IDENTITY, Vector3(0.48, -0.52, -1.25))
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
	steering = 0.0
	engine_force = 0.0
	brake = 95.0
	safe_spawn_seconds = 1.5
	upside_down_seconds = 0.0
	health = maxf(health, 55.0)
	fuel = maxf(fuel, 35.0)
	reset_physics_interpolation()

func damage(value: float, source := "IMPACT") -> void:
	if safe_spawn_seconds > 0.0:
		return
	if Time.get_ticks_msec() / 1000.0 - last_impact_time < 0.35:
		return
	last_impact_time = Time.get_ticks_msec() / 1000.0
	health = maxf(0.0, health - value)
	_update_damage_visuals()
	GameSession.toast_requested.emit(source, "RV frame -%d" % roundi(value))
	if health <= 0.0:
		GameSession.run_finished.emit(false)

func _simulate_driver(delta: float) -> void:
	var horizontal_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	var steering_limit := lerpf(MAX_STEER, 0.20, clampf(horizontal_speed / MAX_SAFE_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_input * steering_limit, delta * 1.8)
	var parked := driver_peer_id == 0
	if parked or not engine_running or fuel <= 0.0 or health <= 0.0 or gear == 1:
		engine_force = 0.0
	else:
		var health_factor := lerpf(0.42, 1.0, health / 100.0)
		var speed_factor := clampf((MAX_SAFE_SPEED - linear_velocity.length()) / 8.0, 0.0, 1.0)
		engine_force = throttle_input * GEAR_RATIOS[gear] * MAX_ENGINE_FORCE * health_factor * speed_factor
		fuel = maxf(0.0, fuel - absf(throttle_input) * delta * 0.16)
	brake = 95.0 if parked else (82.0 if handbrake_input else (24.0 if absf(throttle_input) < 0.05 else 0.0))
	var up_alignment := global_transform.basis.orthonormalized().y.dot(Vector3.UP)
	upside_down_seconds = upside_down_seconds + delta if up_alignment < -0.35 else 0.0
	# Recover immediately once the RV leaves the playable basin. Waiting for a
	# falling rigid body to slow down is impossible and caused runaway speed HUDs.
	if global_position.y < -24.0 or upside_down_seconds > 2.0:
		respawn_at(Net.world.last_checkpoint_transform if Net.world else start_transform)

func _stabilize_motion() -> void:
	if (not global_position.is_finite()
			or not global_transform.basis.is_finite()
			or not linear_velocity.is_finite()
			or not angular_velocity.is_finite()):
		respawn_at(Net.world.last_checkpoint_transform if Net.world else start_transform)
		return
	if linear_velocity.length() > MAX_SAFE_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_SAFE_SPEED
	if angular_velocity.length() > 3.8:
		angular_velocity = angular_velocity.normalized() * 3.8
	# Suppress the one-frame suspension kick which caused parked RV launches on
	# slower mobile physics ticks.
	if safe_spawn_seconds > 0.0:
		linear_velocity = linear_velocity.limit_length(2.5)
		angular_velocity = angular_velocity.limit_length(0.65)

func _hud_speed_kmh() -> float:
	var horizontal := Vector2(linear_velocity.x, linear_velocity.z).length() * 3.6
	return clampf(horizontal, 0.0, MAX_SAFE_SPEED * 3.6)

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
	stats_changed.emit(health, fuel, gear, _hud_speed_kmh())

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
	shape.size = Vector3(2.60, 3.20, 6.35)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.80, 0.0)
	add_child(collision)

	body_shell = Node3D.new()
	body_shell.name = "ExpeditionRVBody"
	add_child(body_shell)
	var exterior := RV_EXTERIOR_SCENE.instantiate() as Node3D
	exterior.name = "DustboundExpeditionRV"
	body_shell.add_child(exterior)
	# The original camper model has a full coach, cab, windows, side door,
	# bumpers, roof rack/cargo, rear ladder and spare instead of reading as an
	# ambulance. VehicleWheel3D supplies the four animated wheels underneath it.
	roof_crate = exterior.find_child("RoofCargo", true, false) as Node3D
	bumper_visual = exterior.find_child("FrontBumper", true, false) as Node3D

	_add_wheel("FrontLeft", Vector3(-1.18, -0.62, -2.08), true, false)
	_add_wheel("FrontRight", Vector3(1.18, -0.62, -2.08), true, false)
	_add_wheel("RearLeft", Vector3(-1.18, -0.62, 1.92), false, true)
	_add_wheel("RearRight", Vector3(1.18, -0.62, 1.92), false, true)

func _add_wheel(wheel_name: String, wheel_position: Vector3, steering_wheel: bool, traction_wheel: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = wheel_position
	wheel.wheel_radius = 0.56
	wheel.wheel_rest_length = 0.32
	wheel.suspension_travel = 0.35
	wheel.suspension_stiffness = 22.0
	wheel.suspension_max_force = 18000.0
	wheel.damping_compression = 0.72
	wheel.damping_relaxation = 0.88
	wheel.wheel_friction_slip = 1.55
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

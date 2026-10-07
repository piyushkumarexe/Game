class_name ExpeditionRV
extends VehicleBody3D
## Server-authoritative four-wheel RV with manual gears, damage and twin winches.

signal stats_changed(health: float, fuel: float, gear: int, speed: float)

const GEAR_RATIOS := [-0.62, 0.0, 0.68, 0.92, 1.16, 1.38, 1.55]
const MAX_ENGINE_FORCE := 4300.0
const MAX_STEER := 0.43
const MAX_FUEL := 100.0
const MAX_SAFE_SPEED := 32.0
const SHIFT_PATTERN: Array[Vector2] = [
	Vector2(-0.24, -0.20), Vector2.ZERO, Vector2(-0.24, 0.20),
	Vector2(0.24, 0.20), Vector2(-0.24, 0.0), Vector2(0.24, 0.0), Vector2(0.24, -0.20)
]
const RV_INTERIOR_SCENE: PackedScene = preload("res://assets/models/rv_exterior.gltf")
const RV_EXTERIOR_SCENE: PackedScene = preload("res://assets/third_party/gmc_motorhome/motorhome.gltf")
const RV_WHEEL_SCENE: PackedScene = preload("res://assets/third_party/gmc_motorhome/wheel.gltf")
const RVDoorInteractableScript = preload("res://scripts/vehicles/rv_door_interactable.gd")

var prompt := "DRIVE THE RV"
var health := 100.0
var fuel := 100.0
var gear := 2
var engine_running := false
var driver_peer_id := 0
## Crew who hitched a ride instead of driving: peer_id -> seat index. Riders are
## carried by the coach transform, so they never get stranded mid-route.
var rider_peers := {}
const RIDE_SEAT_LIMIT := 2
const RIDE_SEAT_OFFSETS: Array[Vector3] = [Vector3(-0.78, -0.22, 0.95), Vector3(0.74, -0.22, 1.35)]
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
var steering_visual_root: Node3D
var gear_visual_root: Node3D
var exterior_shell: Node3D
var interior_shell: Node3D
var cockpit_frame: Node3D
var entry_door_pivot: Node3D
var entry_door_interactable: RVEntryDoorInteractable
var entry_door_open := false
var cabin_light: OmniLight3D
var headlamps: Array[SpotLight3D] = []
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
	# Parked rigid vehicles were settling onto one suspension corner before the
	# player reached them, leaving the RV tipped over in the opening screenshots.
	# Keep the unoccupied rig statically parked; physics resumes at the driver seat.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	_build_rv()
	body_entered.connect(_on_body_entered)
	_setup_engine_audio()

func _ready() -> void:
	front_cable = _create_cable("FrontCable")
	rear_cable = _create_cable("RearCable")
	_refresh_prompt()

func _physics_process(delta: float) -> void:
	if Net.is_online and not multiplayer.is_server():
		_fill_engine_audio()
		return
	safe_spawn_seconds = maxf(0.0, safe_spawn_seconds - delta)
	_stabilize_motion()
	_apply_grounded_stability(delta)
	_simulate_driver(delta)
	_update_vehicle_visuals()
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
	# A taken wheel is not a dead end in co-op: everyone else rides along, so the
	# crew stays together instead of walking in the RV's dust.
	if driver_peer_id != 0:
		request_ride(player)
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
	# Whoever grabs the wheel stops being a passenger.
	rider_peers.erase(id)
	driver_peer_id = id
	engine_running = true
	set_entry_door_open(false)
	freeze = false
	sleeping = false
	safe_spawn_seconds = maxf(safe_spawn_seconds, 0.8)
	var player: Node = Net.world.get_player(id) if Net.world else null
	if player:
		player.enter_driver(self)
	_refresh_prompt()
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
	# Park on an upright terrain-aligned pose before placing the player outside.
	# This prevents a harmless suspension lean from becoming a permanently frozen
	# overturned camper after EXIT DRIVER SEAT.
	if Net.world and Net.world.has_method("terrain_height"):
		var yaw := global_rotation.y
		var parked_origin := global_position
		parked_origin.y = float(Net.world.terrain_height(parked_origin.x, parked_origin.z)) + 0.86
		global_transform = Transform3D(Basis(Vector3.UP, yaw), parked_origin)
	var player: Node = Net.world.get_player(id) if Net.world else null
	if player:
		player.leave_driver(exit_seat_transform())
	driver_peer_id = 0
	throttle_input = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	brake = 95.0
	freeze = true
	_refresh_prompt()


## A disconnected driver would otherwise leave the rig frozen forever with an
## occupied seat nobody can release. Only ever called on the authority.
func force_release_driver(id: int) -> void:
	if driver_peer_id != id:
		return
	_release_driver(id)
	GameSession.toast_requested.emit("CREW LEFT THE WHEEL", "The RV is parked. Anyone can take it now.")


func force_release_rider(id: int) -> void:
	if not rider_peers.has(id):
		return
	_release_rider(id)


# --- shared ride slots -----------------------------------------------------

func request_ride(player: Node) -> void:
	if rider_peers.has(player.peer_id):
		request_exit_ride(player)
		return
	if _free_ride_slot() < 0:
		GameSession.toast_requested.emit("NO FREE SEAT", "Only two crew ride aboard; wait at the campfire.")
		return
	if Net.is_online and not multiplayer.is_server():
		_request_ride.rpc_id(1, player.peer_id)
	else:
		_assign_rider.rpc(player.peer_id)


func request_exit_ride(player: Node) -> void:
	if not rider_peers.has(player.peer_id):
		return
	if Net.is_online and not multiplayer.is_server():
		_request_exit_ride.rpc_id(1, player.peer_id)
	else:
		_release_rider.rpc(player.peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_ride(requested_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == requested_peer:
		_assign_rider.rpc(requested_peer)


@rpc("any_peer", "call_remote", "reliable")
func _request_exit_ride(requested_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == requested_peer:
		_release_rider.rpc(requested_peer)


@rpc("authority", "call_local", "reliable")
func _assign_rider(id: int) -> void:
	if rider_peers.has(id) or id == driver_peer_id:
		return
	var slot := _free_ride_slot()
	if slot < 0:
		return
	rider_peers[id] = slot
	set_entry_door_open(false)
	var player: Node = Net.world.get_player(id) if Net.world else null
	if player and player.has_method("enter_rider"):
		player.call("enter_rider", self, slot)
	GameSession.toast_requested.emit("CREW ABOARD", "%s climbed into the coach." % _crew_name(id))
	_refresh_prompt()


@rpc("authority", "call_local", "reliable")
func _release_rider(id: int) -> void:
	if not rider_peers.has(id):
		return
	var slot := int(rider_peers[id])
	rider_peers.erase(id)
	var player: Node = Net.world.get_player(id) if Net.world else null
	if player and player.has_method("leave_rider"):
		player.call("leave_rider", exit_seat_transform())
	# Leave the door open where the crew stepped out, so the next tap is a
	# doorway to walk through rather than a sealed wall.
	if slot >= 0:
		set_entry_door_open(true)
	_refresh_prompt()


func _free_ride_slot() -> int:
	for slot in RIDE_SEAT_LIMIT:
		if not rider_peers.values().has(slot):
			return slot
	return -1


func ride_seat_transform(slot: int) -> Transform3D:
	var index := clampi(slot, 0, RIDE_SEAT_LIMIT - 1)
	return Transform3D(global_transform.basis, global_transform * RIDE_SEAT_OFFSETS[index])


func rider_count() -> int:
	return rider_peers.size()


func _crew_name(peer_id: int) -> String:
	var entry: Dictionary = Net.roster.get(peer_id, {})
	return str(entry.get("name", "Crew")) if not entry.is_empty() else "Crew"


func _refresh_prompt() -> void:
	if driver_peer_id == 0:
		prompt = "DRIVE THE RV"
	elif _free_ride_slot() >= 0:
		prompt = "RIDE ALONG AS CREW"
	else:
		prompt = "NO FREE SEAT"


## Shared winch control. The cable is a crew tool, not a driver key: a mechanic
## standing at a bog station can hook up while the driver keeps both hands on
## the wheel. Only the authority reaches this through an interactable request.
func operate_winch(front: bool) -> void:
	if multiplayer.is_server() or not Net.is_online:
		_toggle_winch(front_winch if front else rear_winch, front)

func set_local_driver_first_person(_active: bool) -> void:
	# The professional shell is authored for an interior camera: exterior faces
	# cull from inside while glazing remains visible. Never hide the motorhome in
	# first person; doing so removed the real windshield and made the cab a fake
	# overlay. The old duplicate frame remains disabled in every view.
	if body_shell:
		body_shell.visible = true
	if exterior_shell:
		exterior_shell.visible = true
	if interior_shell:
		interior_shell.visible = true
	if cockpit_frame:
		cockpit_frame.visible = false

func driver_seat_transform() -> Transform3D:
	# Camera eye = origin + 1.62 m. This puts the physical-device eye at 1.30 m,
	# behind the modeled dashboard and centered in the GMC panoramic windshield,
	# with clear distance from the seat back, header, steering rim and console.
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.72, -0.32, -2.85))

func exit_seat_transform() -> Transform3D:
	# Exit beside the real passenger doorway rather than through the opposite wall.
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(2.15, 0.02, 0.98))

func cabin_entry_transform() -> Transform3D:
	# Feet land in the clear centre aisle, facing inward from the passenger door.
	# This is an accessibility assist, not a substitute for the physical steps.
	var inward_facing := global_transform.basis * Basis(Vector3.UP, PI * 0.5)
	return Transform3D(inward_facing.orthonormalized(), global_transform * Vector3(0.82, 0.06, 0.98))

func assist_cabin_entry(player: Node) -> void:
	if not entry_door_open:
		return
	if player and player.has_method("place_inside_rv"):
		player.place_inside_rv(cabin_entry_transform())
		GameSession.toast_requested.emit("INSIDE THE RV", "Walk through the connected cabin, or aim at the cockpit and tap USE to drive.")

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
	freeze = driver_peer_id == 0
	for rider_id: int in rider_peers.keys():
		var rider: Node = Net.world.get_player(rider_id) if Net.world else null
		if rider and rider.has_method("enter_rider"):
			rider.call("enter_rider", self, int(rider_peers[rider_id]))
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

func _apply_grounded_stability(_delta: float) -> void:
	var contact_count := 0
	var terrain_support_count := 0
	for child: Node in get_children():
		if not child is VehicleWheel3D:
			continue
		var wheel := child as VehicleWheel3D
		if wheel.is_in_contact():
			contact_count += 1
		# Compatibility-renderer/mobile physics occasionally misses the first
		# VehicleWheel suspension ray after unfreezing a heavy body. Apply a real
		# spring force at each tire patch from the same analytic terrain surface;
		# unlike a height teleport, this preserves weight transfer, roll and bumps.
		if Net.world and Net.world.has_method("terrain_height"):
			var ground_height := float(Net.world.terrain_height(wheel.global_position.x, wheel.global_position.z))
			var clearance := wheel.global_position.y - ground_height
			var compression := maxf(0.0, 0.45 - clearance)
			if compression > 0.0:
				var spring_force := compression * mass * 28.0 - linear_velocity.y * mass * 4.8
				spring_force = clampf(spring_force, 0.0, mass * 9.0)
				apply_force(Vector3.UP * spring_force, wheel.global_position - global_position)
				terrain_support_count += 1
	if maxi(contact_count, terrain_support_count) < 2:
		return
	# A tall camper needs anti-roll resistance, not teleporting orientation.
	# Gentle torque keeps weight transfer and bumps while preventing the violent
	# snap/launch behaviour seen with the old high-centre suspension setup.
	var up := global_transform.basis.orthonormalized().y
	var correction_axis := up.cross(Vector3.UP)
	apply_torque(correction_axis * mass * 3.2 - angular_velocity * mass * 0.42)

func _simulate_driver(delta: float) -> void:
	var horizontal_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	var steering_limit := lerpf(MAX_STEER, 0.20, clampf(horizontal_speed / MAX_SAFE_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_input * steering_limit, delta * 1.8)
	var parked := driver_peer_id == 0
	var drive_throttle := maxf(throttle_input, 0.0)
	if parked or not engine_running or fuel <= 0.0 or health <= 0.0 or gear == 1:
		engine_force = 0.0
	else:
		var health_factor := lerpf(0.42, 1.0, health / 100.0)
		var speed_factor := clampf((MAX_SAFE_SPEED - linear_velocity.length()) / 8.0, 0.0, 1.0)
		var traction_factor := 1.0
		if Net.world and Net.world.has_method("vehicle_traction_factor"):
			traction_factor = float(Net.world.vehicle_traction_factor(global_position))
		engine_force = drive_throttle * GEAR_RATIOS[gear] * MAX_ENGINE_FORCE * health_factor * speed_factor * traction_factor
		if traction_factor < 0.9:
			var mud_drag := exp(-delta * 1.15)
			linear_velocity.x *= mud_drag
			linear_velocity.z *= mud_drag
		fuel = maxf(0.0, fuel - drive_throttle * delta * 0.16)
	var service_brake := throttle_input < -0.10
	brake = 95.0 if parked else (82.0 if handbrake_input else (42.0 if service_brake else (24.0 if drive_throttle < 0.05 else 0.0)))
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

func _add_shell_collision(collision_name: String, collision_position: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = collision_position
	add_child(collision)

func _build_rv() -> void:
	# Eight-metre vintage GMC proportions with a hollow, traversable shell. The
	# split passenger wall matches the actual cut mesh doorway; no invisible slab
	# sits across the threshold or the connected living floor.
	_add_shell_collision("RVMainCollision", Vector3(0.0, -0.03, 0.0), Vector3(2.62, 0.16, 7.55))
	_add_shell_collision("RVRoofCollision", Vector3(0.0, 2.01, 0.0), Vector3(2.62, 0.18, 7.55))
	_add_shell_collision("RVLeftWallCollision", Vector3(-1.30, 1.00, 0.0), Vector3(0.16, 1.95, 7.55))
	# End both wall segments outside the finished jambs. The former front segment
	# overlapped the visible opening by 13 cm, enough to catch a phone player's
	# capsule even though the door looked fully open.
	_add_shell_collision("RVRightFrontWallCollision", Vector3(1.30, 1.00, -1.70), Vector3(0.16, 1.95, 4.16))
	_add_shell_collision("RVRightRearWallCollision", Vector3(1.30, 1.00, 2.68), Vector3(0.16, 1.95, 2.20))
	_add_shell_collision("RVFrontWallCollision", Vector3(0.0, 1.00, -3.84), Vector3(2.62, 1.95, 0.16))
	_add_shell_collision("RVRearWallCollision", Vector3(0.0, 1.00, 3.84), Vector3(2.62, 1.95, 0.16))

	body_shell = Node3D.new()
	body_shell.name = "ExpeditionRVBody"
	add_child(body_shell)

	# Professional 43.4k-triangle CC-BY hero exterior. Source front is +Z, hence
	# the 180-degree yaw. Scale/offset align its three authored axles at a genuine
	# 0.43 m tire radius and place the cabin floor 0.86 m above terrain.
	var motorhome := RV_EXTERIOR_SCENE.instantiate() as Node3D
	motorhome.name = "ProfessionalGMCMotorhomeExterior"
	motorhome.scale = Vector3.ONE * 0.98
	motorhome.rotation.y = PI
	motorhome.position.y = 0.51
	body_shell.add_child(motorhome)
	exterior_shell = motorhome

	# Retain the detailed connected Dustbound living layout (dashboard, steering,
	# seats, refrigerator, kitchen, dinette, bed and storage) behind the new shell.
	# Its rejected slab exterior and duplicate windshield frame never render.
	var interior_source := RV_INTERIOR_SCENE.instantiate() as Node3D
	interior_source.name = "ConnectedModeledLivingInterior"
	body_shell.add_child(interior_source)
	var old_exterior := interior_source.find_child("StaticRVExterior", true, false) as Node3D
	if old_exterior:
		old_exterior.visible = false
	interior_shell = interior_source.find_child("StaticRVInterior", true, false) as Node3D
	var rejected_cockpit_blocks := interior_source.find_child("StaticCockpitInterior", true, false) as Node3D
	if rejected_cockpit_blocks:
		rejected_cockpit_blocks.visible = false
	cockpit_frame = interior_source.find_child("StaticCockpitFrame", true, false) as Node3D
	if cockpit_frame:
		cockpit_frame.visible = false
	roof_crate = interior_source.find_child("RoofCargo", true, false) as Node3D
	var old_bumper := interior_source.find_child("FrontBumper", true, false) as Node3D
	if old_bumper:
		old_bumper.visible = false
	bumper_visual = null
	_build_steering_visual(interior_source)
	_build_gear_visual(interior_source)
	_build_scaled_cockpit_seats()
	_build_entry_door(interior_source)
	_build_entry_steps_and_frame()
	_build_doorway_sightline()
	_build_vehicle_lighting()

	# Front steer axle plus a correctly spaced tandem rear bogie. Every wheel uses
	# Karol Miklas' modeled tire/rim geometry and rotates on VehicleWheel3D.
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		_add_wheel("Front%s" % side_name, Vector3(side * 1.16, -0.43, -3.00), true, false)
		_add_wheel("RearForward%s" % side_name, Vector3(side * 1.16, -0.43, 1.12), false, true)
		_add_wheel("RearAft%s" % side_name, Vector3(side * 1.16, -0.43, 2.14), false, true)

func _build_scaled_cockpit_seats() -> void:
	# The CC-BY shell shipped two duplicated ~3.4 m-tall seat meshes. They were the
	# giant headrest seen across the physical-device windshield and their geometry
	# also escaped through the side opening. Replace them with human-scale seats
	# behind the eye point, leaving the panoramic glass and dashboard unobstructed.
	var upholstery := Color("48585a")
	var vinyl := Color("263235")
	for side in [-1.0, 1.0]:
		var side_name := "Driver" if side < 0.0 else "Passenger"
		var seat_root := Node3D.new()
		seat_root.name = "%sCockpitSeat" % side_name
		body_shell.add_child(seat_root)
		PrimitiveFactory.box(seat_root, "%sSeatBase" % side_name,
			Vector3(side * 0.66, 0.39, -2.26), Vector3(0.58, 0.20, 0.68), vinyl)
		var back := PrimitiveFactory.box(seat_root, "%sSeatBack" % side_name,
			Vector3(side * 0.66, 0.83, -2.02), Vector3(0.60, 0.76, 0.16), upholstery)
		back.rotation.x = -0.10
		PrimitiveFactory.box(seat_root, "%sHeadrest" % side_name,
			Vector3(side * 0.66, 1.31, -1.98), Vector3(0.40, 0.25, 0.15), upholstery)

func _build_steering_visual(exterior: Node3D) -> void:
	var source_pivot := Vector3(0.53, 0.79, -2.22)
	var target_pivot := Vector3(-0.70, 0.76, -3.02)
	steering_visual_root = Node3D.new()
	steering_visual_root.name = "SteeringWheelPivot"
	steering_visual_root.position = target_pivot
	body_shell.add_child(steering_visual_root)
	for component_name in ["CockpitSteeringWheel", "SteeringHub", "SteeringSpokeHorizontal", "SteeringSpokeLower"]:
		var component := exterior.find_child(component_name, true, false) as Node3D
		if component:
			component.position += target_pivot - source_pivot
			component.reparent(steering_visual_root, true)

func _build_gear_visual(exterior: Node3D) -> void:
	var source_pivot := Vector3(0.10, 0.43, -2.19)
	var target_pivot := Vector3(-0.08, 0.43, -2.62)
	gear_visual_root = Node3D.new()
	gear_visual_root.name = "GearLeverPivot"
	gear_visual_root.position = target_pivot
	body_shell.add_child(gear_visual_root)
	for component_name in ["GearLever", "GearKnob"]:
		var component := exterior.find_child(component_name, true, false) as Node3D
		if component:
			component.position += target_pivot - source_pivot
			component.reparent(gear_visual_root, true)

func _build_entry_door(exterior: Node3D) -> void:
	entry_door_pivot = Node3D.new()
	entry_door_pivot.name = "EntryDoorHingePivot"
	entry_door_pivot.position = Vector3(1.377, 0.91, 1.40)
	body_shell.add_child(entry_door_pivot)
	for component_name in ["EntryDoor", "EntryDoorGlass", "EntryDoorHandle"]:
		var component := exterior.find_child(component_name, true, false) as Node3D
		if component:
			component.reparent(entry_door_pivot, true)
			if component is MeshInstance3D:
				var door_mesh := component as MeshInstance3D
				if component_name == "EntryDoor":
					door_mesh.material_override = PrimitiveFactory.material(Color("c98b32"), 0.78, 0.08)
				elif component_name == "EntryDoorHandle":
					door_mesh.material_override = PrimitiveFactory.material(Color("c7c5bb"), 0.28, 0.82)
	entry_door_interactable = RVDoorInteractableScript.new()
	entry_door_interactable.name = "FunctionalEntryDoor"
	entry_door_interactable.position = Vector3(1.58, 0.91, 0.98)
	entry_door_interactable.setup(self)
	add_child(entry_door_interactable)

func _build_entry_steps_and_frame() -> void:
	# Three visible treads bridge real terrain height to the unobstructed cabin
	# floor. The frame masks the deliberately opened source-mesh edge and makes
	# the portal read as manufactured coachwork rather than a texture decal.
	var metal := Color("3b3d3d")
	var tread := Color("272a28")
	PrimitiveFactory.box(body_shell, "DoorFrameFront", Vector3(1.35, 1.00, 0.46), Vector3(0.10, 1.96, 0.10), metal)
	PrimitiveFactory.box(body_shell, "DoorFrameRear", Vector3(1.35, 1.00, 1.50), Vector3(0.10, 1.96, 0.10), metal)
	PrimitiveFactory.box(body_shell, "DoorFrameHeader", Vector3(1.35, 1.98, 0.98), Vector3(0.10, 0.12, 1.14), metal)
	PrimitiveFactory.box(body_shell, "EntryThreshold", Vector3(1.40, -0.02, 0.98), Vector3(0.28, 0.10, 1.02), Color("b1a78e"))
	# A warm horizontal aisle surface makes the route visibly continue past the
	# threshold; the vertical far wall no longer reads as a slab blocking entry.
	PrimitiveFactory.box(body_shell, "ConnectedEntryAisle", Vector3(0.18, 0.025, 0.98),
		Vector3(2.35, 0.045, 0.94), Color("6f4b32"))
	PrimitiveFactory.box(body_shell, "EntryStepUpper", Vector3(1.57, -0.16, 0.98), Vector3(0.48, 0.12, 1.00), tread)
	PrimitiveFactory.box(body_shell, "EntryStepMiddle", Vector3(1.78, -0.38, 0.98), Vector3(0.54, 0.12, 0.94), tread)
	PrimitiveFactory.box(body_shell, "EntryStepLower", Vector3(2.00, -0.60, 0.98), Vector3(0.58, 0.12, 0.88), tread)

func _build_doorway_sightline() -> void:
	# Dress the far wall seen straight through the open passenger portal. A blank
	# pale backing surface made the connected cabin look like a white obstruction
	# in phone screenshots even though it was physically traversable. These thin
	# wall-mounted pieces stay behind the walking aisle and expose real depth.
	var warm_oak := Color("765039")
	var cabinet_oak := Color("493328")
	var window_glass := Color("1b3033")
	# The generated far-wall liner's inner face is x=-1.165, so every dressing
	# surface sits just toward the aisle from it rather than z-fighting behind it.
	PrimitiveFactory.box(body_shell, "DoorwayInteriorWoodPanel", Vector3(-1.130, 0.91, 0.98),
		Vector3(0.045, 1.66, 0.94), warm_oak)
	PrimitiveFactory.box(body_shell, "DoorwayInteriorWindow", Vector3(-1.097, 1.28, 0.98),
		Vector3(0.018, 0.48, 0.62), window_glass)
	PrimitiveFactory.box(body_shell, "DoorwayInteriorLowerCabinet", Vector3(-1.065, 0.38, 0.98),
		Vector3(0.10, 0.44, 0.78), cabinet_oak)
	PrimitiveFactory.box(body_shell, "DoorwayInteriorCabinetHandle", Vector3(-1.006, 0.47, 0.98),
		Vector3(0.025, 0.035, 0.22), Color("b8b1a0"))

func toggle_entry_door() -> void:
	set_entry_door_open(not entry_door_open)

func set_entry_door_open(should_open: bool) -> void:
	entry_door_open = should_open
	if entry_door_interactable:
		entry_door_interactable.refresh_prompt()
	if not entry_door_pivot:
		return
	var target_angle := -1.48 if should_open else 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(entry_door_pivot, "rotation:y", target_angle, 0.55)

func _build_vehicle_lighting() -> void:
	for x in [-0.79, 0.79]:
		var lamp := SpotLight3D.new()
		lamp.name = "HeadlampBeam"
		lamp.position = Vector3(x, 0.49, -3.72)
		lamp.light_color = Color("ffe2a0")
		lamp.light_energy = 2.2
		lamp.spot_range = 28.0
		lamp.spot_angle = 42.0
		lamp.shadow_enabled = false
		lamp.visible = false
		body_shell.add_child(lamp)
		headlamps.append(lamp)
	cabin_light = OmniLight3D.new()
	cabin_light.name = "ModeledCabinLight"
	cabin_light.position = Vector3(0.0, 1.72, -0.55)
	cabin_light.light_color = Color("ffd99b")
	cabin_light.light_energy = 0.52
	cabin_light.omni_range = 4.8
	cabin_light.shadow_enabled = false
	cabin_light.visible = false
	body_shell.add_child(cabin_light)

func _update_vehicle_visuals() -> void:
	if steering_visual_root:
		steering_visual_root.rotation.z = lerp_angle(steering_visual_root.rotation.z, -steering * 2.25, 0.24)
	if gear_visual_root:
		var lever_target := SHIFT_PATTERN[clampi(gear, 0, SHIFT_PATTERN.size() - 1)]
		gear_visual_root.rotation.x = lerp_angle(gear_visual_root.rotation.x, lever_target.x, 0.22)
		gear_visual_root.rotation.z = lerp_angle(gear_visual_root.rotation.z, lever_target.y, 0.22)
	if cabin_light:
		cabin_light.visible = engine_running or entry_door_open
	for lamp in headlamps:
		lamp.visible = engine_running

func _add_wheel(wheel_name: String, wheel_position: Vector3, steering_wheel: bool, traction_wheel: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = wheel_position
	wheel.wheel_radius = 0.43
	wheel.wheel_rest_length = 0.21
	wheel.suspension_travel = 0.24
	wheel.suspension_stiffness = 31.0
	wheel.suspension_max_force = 16500.0
	wheel.damping_compression = 0.82
	wheel.damping_relaxation = 0.94
	wheel.wheel_friction_slip = 1.82
	wheel.use_as_steering = steering_wheel
	wheel.use_as_traction = traction_wheel
	add_child(wheel)
	# The compact core sits within the authored 0.43 m sidewall and only catches
	# a missed first suspension ray; it cannot produce the old buried/floating
	# 0.61 m cylinders visible in the physical-device rejection screenshots.
	var tire_contact := CollisionShape3D.new()
	tire_contact.name = "%sTireContact" % wheel_name
	var tire_shape := CylinderShape3D.new()
	tire_shape.radius = 0.40
	tire_shape.height = 0.30
	tire_contact.shape = tire_shape
	tire_contact.position = wheel_position
	tire_contact.rotation.z = PI * 0.5
	add_child(tire_contact)
	var assembly := RV_WHEEL_SCENE.instantiate() as Node3D
	assembly.name = "DetailedWheelAssembly"
	var side_scale := -1.145 if wheel_position.x < 0.0 else 1.145
	assembly.scale = Vector3(side_scale, 1.145, 1.145)
	wheel.add_child(assembly)

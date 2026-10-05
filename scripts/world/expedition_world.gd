class_name ExpeditionWorld
extends Node3D
## Handcrafted original valley route, mission props and multiplayer spawns.

const PlayerScript = preload("res://scripts/player/player_controller.gd")
const RVScript = preload("res://scripts/vehicles/rv_controller.gd")
const InteractableScript = preload("res://scripts/gameplay/interactable.gd")
const PhysicsCargoScript = preload("res://scripts/gameplay/physics_cargo.gd")
const WildlifeScript = preload("res://scripts/gameplay/wildlife.gd")
const RockfallScript = preload("res://scripts/gameplay/rockfall_hazard.gd")
const PINE_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/kenney/nature-kit/tree-pinetalla-detailed.glb"),
	preload("res://assets/third_party/kenney/nature-kit/tree-pinetallb-detailed.glb")
]
const ROCK_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/kenney/nature-kit/rock-largea.glb"),
	preload("res://assets/third_party/kenney/nature-kit/rock-largeb.glb")
]
const GRASS_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/grass-large.glb")
const BUSH_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/plant-bushdetailed.glb")
const HERO_TREE_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/quaternius/nature/Pine_1.gltf"),
	preload("res://assets/third_party/quaternius/nature/Pine_3.gltf"),
	preload("res://assets/third_party/quaternius/nature/CommonTree_3.gltf"),
	preload("res://assets/third_party/quaternius/nature/CommonTree_4.gltf")
]
const REALISTIC_PINE_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/ez_tree/pine_realistic_a.glb"),
	preload("res://assets/third_party/ez_tree/pine_realistic_b.glb")
]
const REALISTIC_BARK_TEXTURE: Texture2D = preload("res://assets/third_party/quaternius/nature/Bark_NormalTree.jpg")
const REALISTIC_PINE_TEXTURE: Texture2D = preload("res://assets/third_party/quaternius/nature/Leaf_Pine_C.png")
const FOREST_FLOOR_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/quaternius/nature/Bush_Common.gltf"),
	preload("res://assets/third_party/quaternius/nature/Fern_1.gltf"),
	preload("res://assets/third_party/quaternius/nature/Grass_Wispy_Short.gltf"),
	preload("res://assets/third_party/quaternius/nature/Grass_Wispy_Tall.gltf"),
	preload("res://assets/third_party/quaternius/nature/Flower_3_Group.gltf")
]
const HERO_ROCK_SCENES: Array[PackedScene] = [
	preload("res://assets/third_party/quaternius/nature/Rock_Medium_1.gltf"),
	preload("res://assets/third_party/quaternius/nature/Rock_Medium_2.gltf")
]
const TENT_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/tent-detailedopen.glb")
const CAMPFIRE_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/campfire-stones.glb")
const SIGN_SCENE: PackedScene = preload("res://assets/models/trail_sign.gltf")
const GROUND_TEXTURE: Texture2D = preload("res://assets/textures/forest_ground_albedo.jpg")
const TERRAIN_DETAIL: Texture2D = preload("res://assets/textures/forest_ground_albedo.jpg")
const TERRAIN_NORMAL: Texture2D = preload("res://assets/textures/forest_ground_normal.png")
const ROAD_TEXTURE: Texture2D = preload("res://assets/textures/trail_ground_albedo.jpg")
const ROAD_NORMAL: Texture2D = preload("res://assets/textures/trail_ground_normal.png")

const ROUTE: Array[Vector3] = [
	Vector3(0, 2.2, 85), Vector3(-8, 2.0, 55), Vector3(14, 1.2, 24),
	Vector3(28, 3.0, -10), Vector3(38, 3.6, -28), Vector3(14, 7.0, -68),
	Vector3(-24, 2.4, -112), Vector3(12, 13.0, -158), Vector3(-18, 23.0, -195),
	Vector3(48, 28.0, -238)
]

var players := {}
var rv: ExpeditionRV
var players_root: Node3D
var props_root: Node3D
var last_checkpoint_transform := Transform3D.IDENTITY
var bridge_planks: Array[Node3D] = []
var physical_cargo: Array[PhysicsCargo] = []
var cargo_check_accumulator := 0.0
var random := RandomNumberGenerator.new()
var bootstrap_camera: Camera3D
var player_blockers: Array[Dictionary] = []
var world_environment: WorldEnvironment
var environment: Environment
var sun: DirectionalLight3D
var terrain_material: StandardMaterial3D
var road_material: StandardMaterial3D
var realistic_bark_material: StandardMaterial3D
var realistic_pine_material: StandardMaterial3D
var cinematic_detail_root: Node3D

func _ready() -> void:
	name = "RedmesaValley"
	random.seed = 17051991
	GameSession.world = self
	# Establish a lit 3D viewport and a safe floor before any expensive world
	# generation. If a device stalls while building terrain, it still renders a
	# real scene instead of the clear color behind the HUD.
	_build_environment()
	_apply_quality_profile()
	if not GameSession.settings_changed.is_connected(_apply_quality_profile):
		GameSession.settings_changed.connect(_apply_quality_profile)
	_build_bootstrap_view()
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	# Build the complete collision surface before adding the rigid vehicle. This
	# prevents even one physics tick against an incomplete world on slower phones.
	_build_terrain()
	_build_road()
	_build_landmarks()
	_build_scenery()
	# Apply again now that quality-dependent scenery roots exist. This makes a
	# saved HIGH preset—and a live switch to HIGH—materially denser instead of
	# changing only anti-aliasing and leaving the old sparse forest on screen.
	_apply_quality_profile()
	_build_mission_props()
	_spawn_rv()
	last_checkpoint_transform = rv.global_transform
	Net.register_world(self)
	call_deferred("_verify_playable_view")

func _physics_process(delta: float) -> void:
	if not rv or not is_instance_valid(rv) or (Net.is_online and not multiplayer.is_server()):
		return
	cargo_check_accumulator += delta
	if cargo_check_accumulator < 0.15:
		return
	cargo_check_accumulator = 0.0
	for cargo: PhysicsCargo in physical_cargo.duplicate():
		if not is_instance_valid(cargo):
			physical_cargo.erase(cargo)
			continue
		if cargo.cargo_kind != "supply" or cargo.stowed or cargo.carrier:
			continue
		if rv.contains_cabin_point(cargo.global_position):
			var slot := GameSession.supplies_loaded
			var local_slot := Vector3(-0.72 + float(slot % 2) * 1.44, 0.43, 1.72 + float(slot / 2) * 0.72)
			cargo.stow_in_rv(rv, local_slot)
			GameSession.supplies_loaded += 1
			GameSession.toast_requested.emit("SUPPLY STOWED", "%d / 3 physical crates secured" % GameSession.supplies_loaded)
			if GameSession.supplies_loaded >= 3:
				GameSession.complete_target("supplies")
			else:
				Net.broadcast_progress()

func _build_bootstrap_view() -> void:
	var safety_floor := StaticBody3D.new()
	safety_floor.name = "CampSafetyFloor"
	# A compact, hidden-under-terrain solid pad guarantees a valid starting
	# surface even when a mobile GPU needs extra frames to finish terrain setup.
	# Keep the fallback a full metre below the sculpted terrain. Near-coplanar
	# duplicate colliders were pinning CharacterBody3D in place on phones.
	safety_floor.position = Vector3(0.0, ROUTE[0].y - 1.4, ROUTE[0].z)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(26.0, 0.8, 26.0)
	floor_mesh.mesh = plane
	# Collision-only fallback: a visible square pad was reading as broken terrain.
	floor_mesh.visible = false
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_texture = GROUND_TEXTURE
	# Large-scale UVs avoid the obvious checkerboard visible in the phone shot.
	floor_material.uv1_scale = Vector3(2.2, 2.2, 2.2)
	floor_material.roughness = 0.96
	floor_mesh.material_override = floor_material
	safety_floor.add_child(floor_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = plane.size
	collision.shape = shape
	safety_floor.add_child(collision)
	add_child(safety_floor)

	# A deep canyon basin is a visual fail-safe behind the sculpted terrain. It
	# prevents clear-color voids on mobile even if a terrain chunk is culled.
	var basin := MeshInstance3D.new()
	basin.name = "CanyonBasinUnderlay"
	var basin_mesh := BoxMesh.new()
	basin_mesh.size = Vector3(300.0, 2.0, 410.0)
	basin.mesh = basin_mesh
	basin.position = Vector3(0.0, -10.5, -80.0)
	var basin_material := StandardMaterial3D.new()
	basin_material.albedo_texture = TERRAIN_DETAIL
	basin_material.albedo_color = Color("526b4b")
	basin_material.uv1_scale = Vector3(12.0, 12.0, 12.0)
	basin_material.roughness = 1.0
	basin.material_override = basin_material
	basin.ignore_occlusion_culling = true
	add_child(basin)

	var sign := SIGN_SCENE.instantiate() as Node3D
	sign.name = "CampTrailSignModel"
	sign.position = ROUTE[0] + Vector3(-7.0, 0.0, -3.0)
	sign.rotation.y = -0.35
	add_child(sign)
	_add_player_blocker(sign.position, 0.65)

	bootstrap_camera = Camera3D.new()
	bootstrap_camera.name = "BootstrapCamera"
	bootstrap_camera.fov = 66.0
	bootstrap_camera.position = ROUTE[0] + Vector3(12.0, 7.5, 14.0)
	add_child(bootstrap_camera)
	bootstrap_camera.look_at(ROUTE[0] + Vector3(0.0, 1.6, -3.0), Vector3.UP)
	bootstrap_camera.make_current()

func _verify_playable_view() -> void:
	if not GameSession.local_player and not Net.is_online:
		spawn_network_player(1, GameSession.player_name, GameSession.selected_role)
	if GameSession.local_player and is_instance_valid(GameSession.local_player):
		GameSession.local_player.camera.make_current()
		GameSession.toast_requested.emit("REDMESA TRAIL CAMP", "Find the marked supply crates and tap USE to load them.")
	elif is_instance_valid(bootstrap_camera):
		bootstrap_camera.make_current()
		push_error("Local expedition player was not created; bootstrap camera retained.")

func spawn_network_player(peer_id: int, player_name: String, role: int) -> void:
	if players.has(peer_id):
		return
	var player: ExpeditionPlayer = PlayerScript.new()
	players_root.add_child(player)
	var index := players.size()
	var spawn_x := ROUTE[0].x - 3.0 + index * 1.4
	var spawn_z := ROUTE[0].z + 8.5
	# Never place a character under the physical safety pad. This exact mistake
	# caused the device screenshots where the player fell forever below camp.
	var camp_height := maxf(terrain_height(spawn_x, spawn_z), ROUTE[0].y)
	var spawn := Vector3(spawn_x, camp_height + 0.35, spawn_z)
	player.setup(peer_id, player_name, role, spawn)
	players[peer_id] = player

func remove_network_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var player: Node = players[peer_id]
	players.erase(peer_id)
	player.queue_free()

func get_player(peer_id: int) -> Node:
	return players.get(peer_id)

func place_bridge_plank(index: int) -> void:
	if index <= bridge_planks.size():
		return
	var start := ROUTE[3]
	var finish := ROUTE[4]
	var center := (start + finish) * 0.5 + Vector3(0.0, -0.25, 0.0)
	var direction := finish - start
	var length := Vector2(direction.x, direction.z).length() + 2.0
	var yaw := atan2(direction.x, direction.z)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var offset := right * (-1.08 if index == 1 else 1.08)
	var plank := PrimitiveFactory.box(self, "BridgePlank%d" % index, center + offset,
		Vector3(1.75, 0.26, length), Color("8d5b31"), true, Vector3(0.0, yaw, 0.0))
	bridge_planks.append(plank)

func _add_player_blocker(world_position: Vector3, radius: float) -> void:
	player_blockers.append({"center": Vector2(world_position.x, world_position.z), "radius": radius})

func constrain_player_position(current: Vector3, candidate: Vector3) -> Vector3:
	for blocker: Dictionary in player_blockers:
		var center: Vector2 = blocker["center"]
		candidate = _push_player_outside(current, candidate, center, float(blocker["radius"]))
	if rv and is_instance_valid(rv):
		candidate = _guide_open_doorway(candidate)
		candidate = _push_player_outside_rv(candidate)
	return candidate

func _guide_open_doorway(candidate: Vector3) -> Vector3:
	if not rv.entry_door_open:
		return candidate
	var local := rv.global_transform.affine_inverse() * candidate
	# Touch sticks are imprecise. Within the visible stair width, gently centre
	# the player's feet between the jambs so the capsule cannot snag an edge.
	# The correction is capped per physics frame and never pulls a passer-by in.
	if local.x > 0.72 and local.x < 2.48 and local.z > 0.22 and local.z < 1.74:
		local.z = move_toward(local.z, 0.98, 0.075)
		var guided := rv.global_transform * local
		guided.y = candidate.y
		return guided
	return candidate

func _push_player_outside_rv(candidate: Vector3) -> Vector3:
	# The old circular 3.35 m blocker ended before the long front/rear overhangs,
	# allowing the character to stand visibly underneath the bumpers. Use the
	# vehicle's oriented footprint while keeping the passenger-side doorway near.
	var local := rv.global_transform.affine_inverse() * candidate
	var half_width := 1.72
	var half_length := 4.15
	if absf(local.x) >= half_width or absf(local.z) >= half_length:
		return candidate
	# The RV now has a hollow compound collider and connected cabin. Preserve the
	# overhang guard at terrain level, but allow an upright player already inside
	# and allow passage through the passenger aperture only while its door is open.
	var inside_cabin := absf(local.x) < 1.18 and local.z > -3.20 and local.z < 3.04 and local.y > -0.08 and local.y < 2.05
	# The candidate still has terrain-level Y on the first frame approaching the
	# stairs. Gate only on the horizontal aperture here; player_floor_height()
	# raises the feet over all three treads and onto the connected cabin floor.
	# A wider logical aperture plus centring assist gives a thumb-controlled
	# shoulder-width capsule enough tolerance around the finished visual jambs.
	var in_doorway := local.x > 0.92 and local.z > 0.28 and local.z < 1.68
	if inside_cabin or (in_doorway and rv.entry_door_open):
		return candidate
	var distance_to_side := half_width - absf(local.x)
	var distance_to_end := half_length - absf(local.z)
	if distance_to_side < distance_to_end:
		local.x = (1.0 if local.x >= 0.0 else -1.0) * half_width
	else:
		local.z = (1.0 if local.z >= 0.0 else -1.0) * half_length
	var corrected := rv.global_transform * local
	corrected.y = candidate.y
	return corrected

func player_floor_height(world_position: Vector3) -> float:
	var ground := terrain_height(world_position.x, world_position.z) + 0.03
	if not rv or not is_instance_valid(rv):
		return ground
	var local := rv.global_transform.affine_inverse() * world_position
	# A player already in the coach remains on its floor even if the door closes.
	if absf(local.x) <= 1.18 and local.z > -3.20 and local.z < 3.04:
		var cabin_world := rv.global_transform * Vector3(local.x, 0.06, local.z)
		return maxf(ground, cabin_world.y)
	if not rv.entry_door_open:
		return ground
	# Keep the authored three-tread staircase traversable with deterministic foot
	# heights. This mirrors the visible tread tops and avoids relying on mobile
	# CharacterBody step-up behavior while the RV is parked on uneven terrain.
	if local.z > 0.28 and local.z < 1.68:
		var local_floor := -INF
		if local.x > 1.78 and local.x < 2.34:
			local_floor = -0.54
		elif local.x > 1.54 and local.x <= 1.84:
			local_floor = -0.32
		elif local.x > 1.28 and local.x <= 1.60:
			local_floor = -0.10
		elif local.x > 1.02 and local.x <= 1.34:
			local_floor = 0.06
		if local_floor > -INF:
			var tread_world := rv.global_transform * Vector3(local.x, local_floor, local.z)
			return maxf(ground, tread_world.y)
	return ground

func _push_player_outside(current: Vector3, candidate: Vector3, center: Vector2, radius: float) -> Vector3:
	var offset := Vector2(candidate.x, candidate.z) - center
	if offset.length_squared() >= radius * radius:
		return candidate
	if offset.length_squared() < 0.0001:
		offset = Vector2(current.x, current.z) - center
	if offset.length_squared() < 0.0001:
		offset = Vector2.RIGHT
	offset = offset.normalized() * radius
	candidate.x = center.x + offset.x
	candidate.z = center.y + offset.y
	return candidate

func vehicle_traction_factor(world_position: Vector3) -> float:
	# The dark bog is a physical challenge, not only a painted rectangle. Its
	# elliptical falloff keeps entry readable and lets a winch meaningfully help.
	var offset := world_position - ROUTE[6]
	var normalized := Vector2(offset.x / 10.0, offset.z / 13.5)
	return 0.48 if normalized.length_squared() < 1.0 else 1.0

func terrain_height(x: float, z: float) -> float:
	var broad := sin(x * 0.038) * 2.6 + cos(z * 0.031) * 3.2 + sin((x + z) * 0.065) * 1.3
	var edge_rise := pow(absf(x) / 125.0, 2.2) * 35.0
	var north_rise := clampf((-z - 80.0) / 180.0, 0.0, 1.0) * 13.0
	var base := broad + edge_rise + north_rise
	var route_data := _nearest_route_data(Vector2(x, z))
	var distance: float = route_data.x
	var route_y: float = route_data.y
	var segment := int(route_data.z)
	var blend := smoothstep(9.5, 3.8, distance)
	if segment == 3:
		blend = 0.0
	var result := lerpf(base, route_y, blend)
	if z < -11.0 and z > -30.0 and x > 20.0 and x < 45.0:
		var chasm_edge := minf(minf(absf(z + 11.0), absf(z + 30.0)), minf(absf(x - 20.0), absf(x - 45.0)))
		result -= smoothstep(0.0, 5.0, chasm_edge) * 14.0
	# The route polyline points south from camp, so points just behind its first
	# endpoint previously dropped almost six metres. Flatten a generous campsite
	# apron to keep the player, supplies and RV on one coherent starting surface.
	var camp_distance := Vector2(x, z).distance_to(Vector2(ROUTE[0].x, ROUTE[0].z))
	var camp_blend := smoothstep(26.0, 16.0, camp_distance)
	return lerpf(result, ROUTE[0].y, camp_blend)

func _build_environment() -> void:
	world_environment = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	# Bright late-morning forest light replaces the underexposed sunset that
	# multiplied the terrain into an almost-black silhouette on Android.
	sky_material.sky_top_color = Color("4f91bc")
	sky_material.sky_horizon_color = Color("c9ded1")
	sky_material.ground_bottom_color = Color("526b55")
	sky_material.ground_horizon_color = Color("a9bea0")
	sky_material.sun_angle_max = 9.0
	sky_material.sun_curve = 0.12
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("dce6d5")
	environment.ambient_light_energy = 0.64
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = GameSession.graphics_quality >= 2
	environment.fog_enabled = true
	environment.fog_light_color = Color("c2d3c4")
	environment.fog_light_energy = 0.42
	environment.fog_density = 0.00125
	environment.fog_sky_affect = 0.34
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "HighFidelitySun"
	sun.rotation_degrees = Vector3(-55.0, -34.0, 0.0)
	sun.light_color = Color("fff0cf")
	sun.light_energy = 0.96
	sun.shadow_enabled = GameSession.graphics_quality > 0
	sun.directional_shadow_max_distance = 72.0 if GameSession.graphics_quality == 1 else 120.0
	sun.shadow_blur = 0.7
	add_child(sun)

func _apply_quality_profile() -> void:
	var quality := clampi(GameSession.graphics_quality, 0, 2)
	var viewport := get_viewport()
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	# HIGH always renders the 3D scene at native scale; FAST deliberately trades
	# resolution for battery life. Previously all presets shared the same soft
	# internal result, so HIGH looked almost identical on a 1080p phone.
	viewport.scaling_3d_scale = [0.78, 0.90, 1.0][quality]
	var advanced_renderer := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 2 and advanced_renderer else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = quality == 2
	if environment:
		environment.glow_enabled = quality == 2
		environment.ambient_light_energy = [0.72, 0.62, 0.58][quality]
		environment.fog_density = [0.0014, 0.0009, 0.00055][quality]
		environment.fog_sky_affect = [0.38, 0.28, 0.18][quality]
		environment.adjustment_enabled = quality == 2
		environment.adjustment_brightness = 1.02
		environment.adjustment_contrast = 1.10
		environment.adjustment_saturation = 1.06
	if sun:
		sun.shadow_enabled = quality > 0
		sun.light_energy = [0.92, 1.08, 1.22][quality]
		sun.directional_shadow_max_distance = [48.0, 82.0, 150.0][quality]
		sun.shadow_blur = [1.2, 0.85, 0.45][quality]
		sun.shadow_bias = [0.08, 0.055, 0.035][quality]
		sun.shadow_normal_bias = [1.4, 1.05, 0.72][quality]
	if terrain_material:
		terrain_material.normal_enabled = quality > 0
		terrain_material.normal_scale = 0.62 if quality == 2 else 0.38
	if road_material:
		road_material.normal_enabled = quality > 0
		road_material.normal_scale = 0.78 if quality == 2 else 0.45
	# HIGH is a real scene upgrade, not merely a brighter post-process preset.
	# Build/toggle a dedicated close-range foliage layer live so selecting HIGH
	# during an expedition immediately changes density, silhouettes and shadows.
	if props_root:
		if quality == 2:
			_ensure_cinematic_detail_layer()
			cinematic_detail_root.visible = true
			# Hero trees already opt into shadows individually. Do not force hundreds
			# of tiny grass/flower meshes into the mobile shadow atlas.
		elif cinematic_detail_root:
			cinematic_detail_root.visible = false

func _build_terrain() -> void:
	var terrain_sizes := [Vector2i(64, 88), Vector2i(88, 120), Vector2i(128, 176)]
	var terrain_size: Vector2i = terrain_sizes[GameSession.graphics_quality]
	var x_count := terrain_size.x
	var z_count := terrain_size.y
	var x_min := -130.0
	var x_max := 130.0
	var z_min := -270.0
	var z_max := 112.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z_index in z_count:
		var z := lerpf(z_min, z_max, float(z_index) / float(z_count - 1))
		for x_index in x_count:
			var x := lerpf(x_min, x_max, float(x_index) / float(x_count - 1))
			var y := terrain_height(x, z)
			vertices.append(Vector3(x, y, z))
			var sample := 0.65
			var normal := Vector3(terrain_height(x - sample, z) - terrain_height(x + sample, z), sample * 2.0,
				terrain_height(x, z - sample) - terrain_height(x, z + sample)).normalized()
			normals.append(normal)
			var tangent := (Vector3.RIGHT - normal * normal.dot(Vector3.RIGHT)).normalized()
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, -1.0]))
			var route_distance := float(_nearest_route_data(Vector2(x, z)).x)
			var terrain_tint := Color("d4dec4")
			if route_distance < 6.5:
				terrain_tint = Color("d9c5a6")
			elif normal.y < 0.70:
				terrain_tint = Color("b9afa0")
			elif y > 18.0:
				terrain_tint = Color("c4d2b8")
			var color_noise := (sin(x * 0.071 + z * 0.043) + cos(x * 0.037 - z * 0.061)) * 0.5
			terrain_tint = terrain_tint.lightened(color_noise * 0.055) if color_noise > 0.0 else terrain_tint.darkened(-color_noise * 0.045)
			colors.append(terrain_tint)
			uvs.append(Vector2(x * 0.11, z * 0.11))
	for z_index in z_count - 1:
		for x_index in x_count - 1:
			var current := z_index * x_count + x_index
			indices.append_array(PackedInt32Array([current, current + x_count, current + 1,
				current + 1, current + x_count, current + x_count + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.name = "RedmesaTerrain"
	terrain.mesh = mesh
	# StandardMaterial3D is deliberately used here instead of a custom shader.
	# It is reliable on Android's OpenGL fallback and still gets variation from
	# baked vertex colors, so scenery can never appear to float over a void.
	terrain_material = StandardMaterial3D.new()
	terrain_material.albedo_texture = TERRAIN_DETAIL
	terrain_material.albedo_color = Color(1.48, 1.42, 1.30, 1.0)
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.90
	terrain_material.normal_enabled = GameSession.graphics_quality > 0
	terrain_material.normal_texture = TERRAIN_NORMAL
	terrain_material.normal_scale = 0.62 if GameSession.graphics_quality == 2 else 0.38
	terrain_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	terrain_material.texture_repeat = true
	# Two-sided rendering plus explicit occlusion bypass fixes whole-terrain
	# disappearance observed on Android compatibility drivers.
	terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain.material_override = terrain_material
	terrain.ignore_occlusion_culling = true
	terrain.extra_cull_margin = 512.0
	add_child(terrain)
	terrain.create_trimesh_collision()

func _build_road() -> void:
	var road_mesh := ImmediateMesh.new()
	road_material = StandardMaterial3D.new()
	road_material.albedo_texture = ROAD_TEXTURE
	road_material.albedo_color = Color("e8dbc9")
	road_material.roughness = 0.92
	road_material.normal_enabled = GameSession.graphics_quality > 0
	road_material.normal_texture = ROAD_NORMAL
	road_material.normal_scale = 0.78 if GameSession.graphics_quality == 2 else 0.45
	road_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for segment in ROUTE.size() - 1:
		if segment == 3:
			continue
		var a := ROUTE[segment] + Vector3.UP * 0.09
		var b := ROUTE[segment + 1] + Vector3.UP * 0.09
		var forward := (b - a).normalized()
		var right := forward.cross(Vector3.UP).normalized() * 3.7
		var tile_length := a.distance_to(b) / 5.5
		var road_normal := right.normalized().cross(forward).normalized()
		road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, road_material)
		road_mesh.surface_set_normal(road_normal)
		road_mesh.surface_set_tangent(Plane(right.normalized(), -1.0))
		road_mesh.surface_set_uv(Vector2(0, 0)); road_mesh.surface_add_vertex(a - right)
		road_mesh.surface_set_uv(Vector2(1, 0)); road_mesh.surface_add_vertex(a + right)
		road_mesh.surface_set_uv(Vector2(0, tile_length)); road_mesh.surface_add_vertex(b - right)
		road_mesh.surface_set_uv(Vector2(0, tile_length)); road_mesh.surface_add_vertex(b - right)
		road_mesh.surface_set_uv(Vector2(1, 0)); road_mesh.surface_add_vertex(a + right)
		road_mesh.surface_set_uv(Vector2(1, tile_length)); road_mesh.surface_add_vertex(b + right)
		road_mesh.surface_end()
	var road := MeshInstance3D.new()
	road.name = "DustRoad"
	road.mesh = road_mesh
	add_child(road)

func _build_landmarks() -> void:
	props_root = Node3D.new()
	props_root.name = "OriginalLandmarks"
	add_child(props_root)
	# Starting campground uses detailed CC0 camping props rather than blockouts.
	var tent := TENT_SCENE.instantiate() as Node3D
	tent.name = "TrailCampTent"
	tent.position = ROUTE[0] + Vector3(-6.0, 0.08, 0.7)
	tent.rotation.y = 0.32
	tent.scale = Vector3.ONE * 3.25
	props_root.add_child(tent)
	_recolor_imported(tent, {
		"colorred": PrimitiveFactory.material(Color("a95836"), 0.94),
		"wood": PrimitiveFactory.material(Color("6f472c"), 0.96)
	})
	_add_player_blocker(tent.position, 2.05)
	var fire_ring := CAMPFIRE_SCENE.instantiate() as Node3D
	fire_ring.name = "CampfireRing"
	fire_ring.position = ROUTE[0] + Vector3(-2.5, 0.08, 2.0)
	fire_ring.scale = Vector3.ONE * 2.3
	props_root.add_child(fire_ring)
	_recolor_imported(fire_ring, {"stone": PrimitiveFactory.material(Color("76736a"), 1.0)})
	_add_player_blocker(fire_ring.position, 0.88)
	var fire_light := OmniLight3D.new()
	fire_light.position = fire_ring.position + Vector3.UP * 0.45
	fire_light.light_color = Color("ffad5a")
	fire_light.light_energy = 1.35
	fire_light.omni_range = 7.0
	props_root.add_child(fire_light)
	PrimitiveFactory.label_3d(props_root, "REDMESA\nTRAIL CAMP", ROUTE[0] + Vector3(-6.0, 3.25, -1.8), Color("fff0d0"), 48)
	# Broken span supports
	var bridge_mid := (ROUTE[3] + ROUTE[4]) * 0.5
	PrimitiveFactory.box(props_root, "BridgeApproachA", ROUTE[3] + Vector3(0, -0.2, 0), Vector3(7.2, 0.45, 5.0), Color("5e4939"), true, Vector3(0, 0.55, 0))
	PrimitiveFactory.box(props_root, "BridgeApproachB", ROUTE[4] + Vector3(0, -0.2, 0), Vector3(7.2, 0.45, 5.0), Color("5e4939"), true, Vector3(0, 0.55, 0))
	PrimitiveFactory.label_3d(props_root, "DRY CREEK\nBRIDGE OUT", bridge_mid + Vector3(7, 3, 0), Color("f2bb5c"), 42)
	# Ranger repair station
	var ranger := ROUTE[5] + Vector3(-7, 0, 2)
	PrimitiveFactory.box(props_root, "RangerGarage", ranger + Vector3(0, 2.1, 0), Vector3(8.5, 4.2, 6.2), Color("76513b"), true)
	PrimitiveFactory.box(props_root, "GarageDoor", ranger + Vector3(0, 1.55, -3.13), Vector3(5.2, 3.0, 0.12), Color("34464a"))
	PrimitiveFactory.box(props_root, "GarageRoof", ranger + Vector3(0, 4.35, 0), Vector3(9.2, 0.35, 7.0), Color("3a3836"), true)
	PrimitiveFactory.label_3d(props_root, "LANTERN POST\nRANGER GARAGE", ranger + Vector3(0, 5.2, 0), Color("fff0d0"), 45)
	# Mud bog visual
	PrimitiveFactory.box(props_root, "MudwaterBog", ROUTE[6] + Vector3(0, -0.25, 0), Vector3(20, 0.45, 27), Color("302d28"), true, Vector3(0, -0.55, 0))
	# Finish gate
	var finish := ROUTE[-1]
	PrimitiveFactory.box(props_root, "FinishPostL", finish + Vector3(-4.5, 2.8, 0), Vector3(0.45, 5.6, 0.45), Color("2d3436"), true)
	PrimitiveFactory.box(props_root, "FinishPostR", finish + Vector3(4.5, 2.8, 0), Vector3(0.45, 5.6, 0.45), Color("2d3436"), true)
	PrimitiveFactory.box(props_root, "FinishBeam", finish + Vector3(0, 5.5, 0), Vector3(9.4, 0.65, 0.5), Color("d78137"), true)
	PrimitiveFactory.label_3d(props_root, "ROUTE 17", finish + Vector3(0, 6.2, 0), Color("fff0d0"), 62)
	# Water catches sunset and marks the creek basin.
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(86, 58)
	water.mesh = water_mesh
	water.position = Vector3(31, -7.5, -20)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.13, 0.32, 0.37, 0.82)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.metallic = 0.35
	water_mat.roughness = 0.18
	water.material_override = water_mat
	add_child(water)

func _build_scenery() -> void:
	var tree_count: int = [46, 74, 150][GameSession.graphics_quality]
	for index in tree_count:
		var z := random.randf_range(-250.0, 103.0)
		var x := random.randf_range(-118.0, 118.0)
		var route_info := _nearest_route_data(Vector2(x, z))
		if route_info.x < 7.2 or route_info.x > 38.0:
			continue
		_make_tree(Vector3(x, terrain_height(x, z), z), 0.75 + random.randf() * 0.7, index % 5 == 0)
	var rock_count: int = [32, 52, 104][GameSession.graphics_quality]
	for index in rock_count:
		var z := random.randf_range(-255.0, 106.0)
		var x := random.randf_range(-122.0, 122.0)
		var route_info := _nearest_route_data(Vector2(x, z))
		if route_info.x < 5.4 or route_info.x > 42.0:
			continue
		var radius := random.randf_range(0.45, 1.75)
		_make_rock(Vector3(x, terrain_height(x, z), z), radius,
			Vector3(random.randf_range(0.8, 1.5), random.randf_range(0.55, 1.15), random.randf_range(0.8, 1.4)), index % 8 == 0)
	var cover_count: int = [42, 82, 220][GameSession.graphics_quality]
	for index in cover_count:
		var z := random.randf_range(-252.0, 104.0)
		var x := random.randf_range(-116.0, 116.0)
		var route_distance := _nearest_route_data(Vector2(x, z)).x
		if route_distance < 5.0 or route_distance > 32.0:
			continue
		var cover := (BUSH_SCENE if index % 6 == 0 else GRASS_SCENE).instantiate() as Node3D
		cover.name = "TrailBush" if index % 6 == 0 else "TrailGrass"
		cover.position = Vector3(x, terrain_height(x, z), z)
		cover.rotation.y = random.randf_range(-PI, PI)
		cover.scale = Vector3.ONE * random.randf_range(1.25, 2.15)
		props_root.add_child(cover)
		_recolor_imported(cover, {"grass": PrimitiveFactory.material(Color("4f7f42"), 0.98)})
		_set_shadow_mode(cover, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# A deliberate tree line gives the opening area a readable forest silhouette
	# instead of relying on sparse random placements in the player's first view.
	var camp_tree_count: int = [8, 13, 28][GameSession.graphics_quality]
	for index in camp_tree_count:
		var angle := TAU * float(index) / float(camp_tree_count) + sin(index * 2.1) * 0.16
		var radius := 21.0 + float(index % 4) * 4.5
		var x := ROUTE[0].x + cos(angle) * radius
		var z := ROUTE[0].z + sin(angle) * radius
		_make_tree(Vector3(x, terrain_height(x, z), z), 0.78 + float(index % 3) * 0.16, false)
	_build_high_detail_forest()
	_build_distant_forest()
	# Reliable cable anchors along challenge sections.
	for anchor_position in [Vector3(18, 5, -8), Vector3(46, 6, -32), Vector3(-34, 7, -109), Vector3(-13, 11, -131), Vector3(22, 19, -169), Vector3(-24, 29, -199)]:
		_make_winch_post(anchor_position)
	for wildlife_position in [Vector3(-36, 8, -82), Vector3(25, 17, -154), Vector3(-30, 28, -204)]:
		var wildlife: TrailWildlife = WildlifeScript.new()
		add_child(wildlife)
		wildlife.setup(Vector3(wildlife_position.x, terrain_height(wildlife_position.x, wildlife_position.z) + 0.2, wildlife_position.z))

func _realistic_tree_materials() -> void:
	if realistic_bark_material and realistic_pine_material:
		return
	realistic_bark_material = StandardMaterial3D.new()
	realistic_bark_material.albedo_texture = REALISTIC_BARK_TEXTURE
	realistic_bark_material.albedo_color = Color("9a8068")
	realistic_bark_material.roughness = 0.96
	realistic_bark_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	realistic_bark_material.texture_repeat = true
	realistic_pine_material = StandardMaterial3D.new()
	realistic_pine_material.albedo_texture = REALISTIC_PINE_TEXTURE
	realistic_pine_material.albedo_color = Color("b4c6a5")
	realistic_pine_material.roughness = 0.88
	realistic_pine_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	realistic_pine_material.alpha_scissor_threshold = 0.28
	realistic_pine_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	realistic_pine_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _make_realistic_pine(position: Vector3, index: int, tree_scale: float) -> Node3D:
	_realistic_tree_materials()
	var tree := REALISTIC_PINE_SCENES[index % REALISTIC_PINE_SCENES.size()].instantiate() as Node3D
	tree.name = "HighRealismProceduralPine%02d" % index
	tree.position = position
	tree.rotation.y = random.randf_range(-PI, PI)
	# EZ-Tree works in large authoring units; 0.13-0.18 yields mature 7-10 m
	# conifers while preserving its detailed branch silhouette.
	tree.scale = Vector3.ONE * tree_scale
	props_root.add_child(tree)
	for candidate: Node in tree.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		mesh.material_override = realistic_bark_material if mesh.name.contains("Bark") else realistic_pine_material
		mesh.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if GameSession.graphics_quality == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	return tree

func _ensure_cinematic_detail_layer() -> void:
	if cinematic_detail_root or not props_root:
		return
	cinematic_detail_root = Node3D.new()
	cinematic_detail_root.name = "CinematicHighDetailLayer"
	props_root.add_child(cinematic_detail_root)
	var detail_random := RandomNumberGenerator.new()
	detail_random.seed = 982451653

	# Extra branch-modelled conifers close the empty opening hills visible in the
	# phone capture. Their limited 12–42 m ring retains the road sightline while
	# detailed bark, alpha foliage and contact shadows fill the player's view.
	for index in 12:
		var angle := TAU * float(index) / 12.0 + detail_random.randf_range(-0.13, 0.13)
		var radius := detail_random.randf_range(23.0, 42.0)
		var position := ROUTE[0] + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if float(_nearest_route_data(Vector2(position.x, position.z)).x) < 9.5:
			continue
		position.y = terrain_height(position.x, position.z) + 0.10
		var tree := _make_realistic_pine(position, index + 400, detail_random.randf_range(0.132, 0.176))
		tree.reparent(cinematic_detail_root, true)

	# Dense undergrowth breaks the flat terrain silhouette at human/camera height.
	# Shadows remain disabled for these small meshes; the high setting spends its
	# shadow budget on the RV, people and branch-modelled hero trees instead.
	for index in 48:
		var angle := detail_random.randf_range(-PI, PI)
		var radius := detail_random.randf_range(7.0, 38.0)
		var position := ROUTE[0] + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if float(_nearest_route_data(Vector2(position.x, position.z)).x) < 4.4:
			continue
		position.y = terrain_height(position.x, position.z) + 0.035
		var cover := FOREST_FLOOR_SCENES[index % FOREST_FLOOR_SCENES.size()].instantiate() as Node3D
		cover.name = "CinematicForestFloor"
		cover.position = position
		cover.rotation.y = detail_random.randf_range(-PI, PI)
		cover.scale = Vector3.ONE * detail_random.randf_range(0.72, 1.38)
		cinematic_detail_root.add_child(cover)
		_tint_imported(cover, Color(0.76, 0.86, 0.72, 1.0))
		_set_shadow_mode(cover, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

func _build_high_detail_forest() -> void:
	# HIGH adds MIT EZ-Tree generated branch geometry with alpha-cutout CC0
	# foliage close to the player. Mid/far layers remain cheaper on mobile.
	# Build a deliberate opening grove first; route-wide random distribution left
	# the physical-phone campsite surrounded by large empty green hills.
	var camp_hero_count: int = [8, 14, 28][GameSession.graphics_quality]
	for index in camp_hero_count:
		var angle := TAU * float(index) / float(camp_hero_count) + sin(float(index) * 1.73) * 0.19
		var radius := 18.0 + float(index % 4) * 4.3
		var position := ROUTE[0] + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if float(_nearest_route_data(Vector2(position.x, position.z)).x) < 8.5:
			continue
		position.y = terrain_height(position.x, position.z) + 0.12
		var tree: Node3D
		if GameSession.graphics_quality == 2:
			tree = _make_realistic_pine(position, index, 0.135 + float(index % 4) * 0.012)
		else:
			tree = HERO_TREE_SCENES[index % HERO_TREE_SCENES.size()].instantiate() as Node3D
			tree.position = position
			tree.rotation.y = angle * 1.37
			tree.scale = Vector3.ONE * (0.92 + float(index % 3) * 0.13)
			props_root.add_child(tree)
			_tint_imported(tree, Color(0.72, 0.82, 0.70, 1.0))
		tree.name = "CampHeroTexturedTree%02d" % index
		if GameSession.graphics_quality == 0:
			_set_shadow_mode(tree, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var camp_floor_count: int = [20, 38, 92][GameSession.graphics_quality]
	for index in camp_floor_count:
		var angle := TAU * float(index) / float(camp_floor_count) + sin(float(index) * 2.31) * 0.24
		var radius := 9.0 + float(index % 7) * 2.75
		var position := ROUTE[0] + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if float(_nearest_route_data(Vector2(position.x, position.z)).x) < 4.8:
			continue
		position.y = terrain_height(position.x, position.z) + 0.04
		var cover := FOREST_FLOOR_SCENES[index % FOREST_FLOOR_SCENES.size()].instantiate() as Node3D
		cover.name = "CampTexturedForestFloor"
		cover.position = position
		cover.rotation.y = angle * -1.61
		cover.scale = Vector3.ONE * (0.62 + float(index % 4) * 0.14)
		props_root.add_child(cover)
		_tint_imported(cover, Color(0.78, 0.88, 0.76, 1.0))
		_set_shadow_mode(cover, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var hero_tree_count: int = [14, 26, 60][GameSession.graphics_quality]
	for index in hero_tree_count:
		var segment := index % (ROUTE.size() - 1)
		var t := 0.10 + random.randf() * 0.80
		var center := ROUTE[segment].lerp(ROUTE[segment + 1], t)
		var forward := ROUTE[segment + 1] - ROUTE[segment]
		forward.y = 0.0
		forward = forward.normalized()
		var side := Vector3(-forward.z, 0.0, forward.x)
		var side_sign := -1.0 if index % 2 == 0 else 1.0
		var distance := random.randf_range(10.5, 25.0)
		var position := center + side * distance * side_sign
		position.y = terrain_height(position.x, position.z) + 0.12
		var tree: Node3D
		if GameSession.graphics_quality == 2:
			tree = _make_realistic_pine(position, index + 100, random.randf_range(0.125, 0.175))
		else:
			tree = HERO_TREE_SCENES[index % HERO_TREE_SCENES.size()].instantiate() as Node3D
			tree.position = position
			tree.rotation.y = random.randf_range(-PI, PI)
			tree.scale = Vector3.ONE * random.randf_range(0.88, 1.34)
			props_root.add_child(tree)
			_tint_imported(tree, Color(0.72, 0.82, 0.70, 1.0))
		tree.name = "HeroTexturedForestTree"
		if GameSession.graphics_quality == 0:
			_set_shadow_mode(tree, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var floor_cover_count: int = [34, 68, 160][GameSession.graphics_quality]
	for index in floor_cover_count:
		var segment := index % (ROUTE.size() - 1)
		var t := random.randf_range(0.04, 0.96)
		var center := ROUTE[segment].lerp(ROUTE[segment + 1], t)
		var forward := ROUTE[segment + 1] - ROUTE[segment]
		forward.y = 0.0
		forward = forward.normalized()
		var side := Vector3(-forward.z, 0.0, forward.x)
		var side_sign := -1.0 if index % 2 == 0 else 1.0
		var position := center + side * random.randf_range(5.8, 19.0) * side_sign
		position.y = terrain_height(position.x, position.z) + 0.05
		var cover := FOREST_FLOOR_SCENES[index % FOREST_FLOOR_SCENES.size()].instantiate() as Node3D
		cover.name = "TexturedForestFloor"
		cover.position = position
		cover.rotation.y = random.randf_range(-PI, PI)
		cover.scale = Vector3.ONE * random.randf_range(0.58, 1.32)
		props_root.add_child(cover)
		_tint_imported(cover, Color(0.78, 0.88, 0.76, 1.0))
		_set_shadow_mode(cover, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var hero_rock_count: int = [8, 16, 36][GameSession.graphics_quality]
	for index in hero_rock_count:
		var segment := index % (ROUTE.size() - 1)
		var t := random.randf_range(0.08, 0.92)
		var center := ROUTE[segment].lerp(ROUTE[segment + 1], t)
		var forward := ROUTE[segment + 1] - ROUTE[segment]
		forward.y = 0.0
		forward = forward.normalized()
		var side := Vector3(-forward.z, 0.0, forward.x)
		var side_sign := -1.0 if index % 2 == 0 else 1.0
		var position := center + side * random.randf_range(8.0, 24.0) * side_sign
		position.y = terrain_height(position.x, position.z) + 0.04
		var rock := HERO_ROCK_SCENES[index % HERO_ROCK_SCENES.size()].instantiate() as Node3D
		rock.name = "TexturedHeroRock"
		rock.position = position
		rock.rotation = Vector3(0.0, random.randf_range(-PI, PI), random.randf_range(-0.10, 0.10))
		rock.scale = Vector3.ONE * random.randf_range(0.75, 1.65)
		props_root.add_child(rock)

func _build_distant_forest() -> void:
	# Batch the background forest into one MultiMesh instead of hundreds of
	# individual nodes/draw submissions. This adds the density missing from the
	# phone screenshots while remaining cheaper than the previous sparse trees.
	var template := PINE_SCENES[1].instantiate() as Node3D
	var source_mesh_nodes := template.find_children("*", "MeshInstance3D", true, false)
	var source_mesh_node := source_mesh_nodes[0] as MeshInstance3D if not source_mesh_nodes.is_empty() else null
	if not source_mesh_node or not source_mesh_node.mesh:
		template.free()
		return
	var forest_mesh := source_mesh_node.mesh.duplicate(true) as Mesh
	for surface in forest_mesh.get_surface_count():
		var source := forest_mesh.surface_get_material(surface)
		var material_name := source.resource_name.to_lower() if source else ""
		if material_name.contains("leaf"):
			forest_mesh.surface_set_material(surface, PrimitiveFactory.material(Color("315f3c"), 0.98))
		elif material_name.contains("wood"):
			forest_mesh.surface_set_material(surface, PrimitiveFactory.material(Color("60412e"), 0.97))
	template.free()
	var forest_count: int = [54, 96, 240][GameSession.graphics_quality]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = forest_mesh
	multimesh.instance_count = forest_count
	var forest := MultiMeshInstance3D.new()
	forest.name = "BatchedDistantForest"
	forest.multimesh = multimesh
	forest.custom_aabb = AABB(Vector3(-132.0, -12.0, -265.0), Vector3(264.0, 78.0, 370.0))
	forest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if GameSession.graphics_quality < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	props_root.add_child(forest)
	var placed := 0
	var attempts := 0
	while placed < forest_count and attempts < forest_count * 10:
		attempts += 1
		var x := random.randf_range(-124.0, 124.0)
		var z := random.randf_range(-258.0, 106.0)
		var route_distance := float(_nearest_route_data(Vector2(x, z)).x)
		if route_distance < 16.0 or route_distance > 76.0:
			continue
		var scale_factor := random.randf_range(3.0, 5.0)
		var basis := Basis(Vector3.UP, random.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_factor)
		multimesh.set_instance_transform(placed, Transform3D(basis, Vector3(x, terrain_height(x, z), z)))
		placed += 1
	# The acceptance range normally fills. Hide any unused transforms safely at
	# the basin floor rather than leaving identity trees at world origin.
	while placed < forest_count:
		multimesh.set_instance_transform(placed, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -30, 0)))
		placed += 1

func _make_tree(position: Vector3, scale_factor: float, anchor: bool) -> void:
	var tree := Node3D.new()
	tree.name = "CablePine" if anchor else "TexturedPine"
	tree.position = position
	tree.rotation.y = random.randf_range(-PI, PI)
	tree.scale = Vector3.ONE * scale_factor
	props_root.add_child(tree)
	var model := PINE_SCENES[random.randi_range(0, PINE_SCENES.size() - 1)].instantiate() as Node3D
	model.scale = Vector3.ONE * 3.45
	tree.add_child(model)
	_recolor_imported(model, {
		"leaf": PrimitiveFactory.material(Color("356b42"), 0.98),
		"wood": PrimitiveFactory.material(Color("67452f"), 0.97)
	})
	if GameSession.graphics_quality == 0 and not anchor:
		_set_shadow_mode(model, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if anchor:
		var trunk_body := StaticBody3D.new()
		var trunk_collision := CollisionShape3D.new()
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.radius = 0.24
		trunk_shape.height = 2.8
		trunk_collision.shape = trunk_shape
		trunk_collision.position.y = 1.4
		trunk_body.add_child(trunk_collision)
		tree.add_child(trunk_body)
		tree.add_to_group("winch_anchor")

func _make_rock(position: Vector3, radius: float, shape_scale: Vector3, collision_enabled: bool) -> void:
	var rock_root := Node3D.new()
	rock_root.name = "TexturedCanyonRock"
	rock_root.position = position
	rock_root.rotation.y = random.randf_range(-PI, PI)
	rock_root.scale = shape_scale * radius
	props_root.add_child(rock_root)
	var model := ROCK_SCENES[random.randi_range(0, ROCK_SCENES.size() - 1)].instantiate() as Node3D
	model.scale = Vector3.ONE * 2.15
	rock_root.add_child(model)
	_recolor_imported(model, {
		"grass": PrimitiveFactory.material(Color("537746"), 0.98),
		"dirt": PrimitiveFactory.material(Color("776755"), 1.0),
		"default": PrimitiveFactory.material(Color("80766a"), 1.0)
	})
	if GameSession.graphics_quality < 2 and not collision_enabled:
		_set_shadow_mode(model, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if collision_enabled:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.78
		collision.shape = shape
		collision.position.y = 0.6
		body.add_child(collision)
		rock_root.add_child(body)

func _recolor_imported(root_node: Node, palette: Dictionary) -> void:
	var mesh_nodes: Array[Node] = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		mesh_nodes.push_front(root_node)
	for candidate: Node in mesh_nodes:
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			var source_name := source.resource_name.to_lower() if source else ""
			for token: String in palette:
				if source_name.contains(token):
					mesh_instance.set_surface_override_material(surface, palette[token])
					break

func _tint_imported(root_node: Node, tint: Color) -> void:
	var mesh_nodes: Array[Node] = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		mesh_nodes.push_front(root_node)
	for candidate: Node in mesh_nodes:
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var tinted := source.duplicate() as StandardMaterial3D
				tinted.albedo_color *= tint
				mesh_instance.set_surface_override_material(surface, tinted)

func _set_shadow_mode(root_node: Node, mode: int) -> void:
	if root_node is GeometryInstance3D:
		(root_node as GeometryInstance3D).cast_shadow = mode
	for mesh_node: Node in root_node.find_children("*", "GeometryInstance3D", true, false):
		(mesh_node as GeometryInstance3D).cast_shadow = mode

func _make_winch_post(position: Vector3) -> void:
	var post := PrimitiveFactory.cylinder(props_root, "SteelWinchPost", position, 0.18, 2.6, Color("626c6c"), true)
	post.add_to_group("winch_anchor")
	PrimitiveFactory.box(post, "Marker", Vector3(0, 0.65, 0), Vector3(0.52, 0.32, 0.12), Color("e5a23b"))

func _build_mission_props() -> void:
	for offset in [Vector3(-7, 0.6, 5), Vector3(-4.8, 0.6, 5.6), Vector3(-2.6, 0.6, 5.1)]:
		_spawn_physics_cargo("supply", ROUTE[0] + offset)
	_spawn_physics_cargo("plank", ROUTE[3] + Vector3(-5.5, 0.6, 3.0))
	_spawn_physics_cargo("plank", ROUTE[3] + Vector3(-4.0, 0.6, 4.2))
	_spawn_interactable("bridge_socket", ROUTE[3] + Vector3(-1.1, 0.5, -2.2))
	_spawn_interactable("bridge_socket", ROUTE[3] + Vector3(1.1, 0.5, -2.2))
	# Distinct service points make damage readable and require the correct tool
	# interaction instead of one button magically repairing the entire vehicle.
	_spawn_interactable("repair_body", ROUTE[5] + Vector3(-5.0, 1.0, 1.2))
	_spawn_interactable("repair_frame", ROUTE[5] + Vector3(-3.7, 1.0, 1.2))
	_spawn_interactable("repair_engine", ROUTE[5] + Vector3(-2.4, 1.0, 1.2))
	_spawn_interactable("repair_tires", ROUTE[5] + Vector3(-1.1, 1.0, 1.2))
	# Every repair now starts with a real tool the player must locate, carry and
	# present to the matching service point.
	_spawn_physics_cargo("hammer", ROUTE[5] + Vector3(-5.0, 0.75, 3.0))
	_spawn_physics_cargo("welder", ROUTE[5] + Vector3(-3.7, 0.75, 3.0))
	_spawn_physics_cargo("oil", ROUTE[5] + Vector3(-2.6, 0.75, 3.0))
	_spawn_physics_cargo("oil", ROUTE[5] + Vector3(-2.1, 0.75, 3.0))
	_spawn_physics_cargo("drill", ROUTE[5] + Vector3(-1.1, 0.75, 3.0))
	_spawn_physics_cargo("spare_tire", ROUTE[5] + Vector3(0.1, 0.85, 3.0))
	_spawn_physics_cargo("spare_tire", ROUTE[5] + Vector3(1.1, 0.85, 3.0))
	_spawn_physics_cargo("extinguisher", ROUTE[0] + Vector3(1.0, 0.65, 4.8))
	_spawn_physics_cargo("extinguisher", ROUTE[5] + Vector3(2.0, 0.65, 3.0))
	_spawn_interactable("fuel", ROUTE[5] + Vector3(0.3, 0.6, 1.1))
	_create_checkpoint(ROUTE[2], 1, "Dry Creek Overlook", Vector3(10, 5, 7))
	_create_checkpoint(ROUTE[5], 2, "Lantern Post Garage", Vector3(12, 6, 8))
	_create_checkpoint(ROUTE[8], 3, "Last Light Summit", Vector3(12, 7, 8))
	_create_checkpoint(ROUTE[-1], 4, "Route 17 Exit", Vector3(13, 8, 10))
	var rockfall: RockfallHazard = RockfallScript.new()
	add_child(rockfall)
	rockfall.setup((ROUTE[7] + ROUTE[8]) * 0.5 + Vector3.UP * 3.0, self)

func _spawn_physics_cargo(kind: String, position: Vector3) -> PhysicsCargo:
	var cargo: PhysicsCargo = PhysicsCargoScript.new()
	add_child(cargo)
	cargo.setup(kind, position)
	physical_cargo.append(cargo)
	return cargo

func _spawn_interactable(kind: String, position: Vector3) -> TrailInteractable:
	var item: TrailInteractable = InteractableScript.new()
	add_child(item)
	item.setup(kind, position)
	return item

func _create_checkpoint(position: Vector3, index: int, title: String, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Checkpoint%d" % index
	area.position = position + Vector3.UP * size.y * 0.5
	area.collision_layer = 0
	area.collision_mask = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_checkpoint_entered.bind(index, title, position))
	add_child(area)
	PrimitiveFactory.label_3d(self, "TRAIL %02d" % index, position + Vector3(0, 3.4, 0), Color("f2b557"), 38)

func _on_checkpoint_entered(body: Node, index: int, title: String, checkpoint_position: Vector3) -> void:
	if body != rv or (Net.is_online and not multiplayer.is_server()):
		return
	var safe_height := terrain_height(checkpoint_position.x, checkpoint_position.z) + 0.86
	last_checkpoint_transform = Transform3D(rv.global_transform.basis.orthonormalized(),
		Vector3(checkpoint_position.x, safe_height, checkpoint_position.z))
	GameSession.set_checkpoint(index, title)
	if index == 4:
		GameSession.complete_target("finish")

func _spawn_rv() -> void:
	rv = RVScript.new()
	add_child(rv)
	var basis := Basis(Vector3.UP, PI)
	var spawn_x := ROUTE[0].x + 2.2
	var spawn_z := ROUTE[0].z - 2.0
	var spawn := Vector3(spawn_x, terrain_height(spawn_x, spawn_z) + 0.86, spawn_z)
	rv.setup(Transform3D(basis, spawn))
	GameSession.rv = rv

func _nearest_route_data(point: Vector2) -> Vector3:
	var best_distance := INF
	var best_y := 0.0
	var best_segment := 0
	for segment in ROUTE.size() - 1:
		var a := Vector2(ROUTE[segment].x, ROUTE[segment].z)
		var b := Vector2(ROUTE[segment + 1].x, ROUTE[segment + 1].z)
		var line := b - a
		var t := clampf((point - a).dot(line) / maxf(line.length_squared(), 0.001), 0.0, 1.0)
		var closest := a + line * t
		var distance := point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_y = lerpf(ROUTE[segment].y, ROUTE[segment + 1].y, t)
			best_segment = segment
	return Vector3(best_distance, best_y, best_segment)

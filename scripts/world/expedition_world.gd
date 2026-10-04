class_name ExpeditionWorld
extends Node3D
## Handcrafted original valley route, mission props and multiplayer spawns.

const PlayerScript = preload("res://scripts/player/player_controller.gd")
const RVScript = preload("res://scripts/vehicles/rv_controller.gd")
const InteractableScript = preload("res://scripts/gameplay/interactable.gd")
const WildlifeScript = preload("res://scripts/gameplay/wildlife.gd")
const RockfallScript = preload("res://scripts/gameplay/rockfall_hazard.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const PINE_SCENE: PackedScene = preload("res://assets/models/pine_tree.gltf")
const ROCK_SCENE: PackedScene = preload("res://assets/models/canyon_rock.gltf")
const SIGN_SCENE: PackedScene = preload("res://assets/models/trail_sign.gltf")
const GROUND_TEXTURE: Texture2D = preload("res://assets/textures/ground_dirt.png")

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
var random := RandomNumberGenerator.new()
var bootstrap_camera: Camera3D

func _ready() -> void:
	name = "RedmesaValley"
	random.seed = 17051991
	GameSession.world = self
	# Establish a lit 3D viewport and a safe floor before any expensive world
	# generation. If a device stalls while building terrain, it still renders a
	# real scene instead of the clear color behind the HUD.
	_build_environment()
	_build_bootstrap_view()
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	_spawn_rv()
	last_checkpoint_transform = rv.global_transform
	Net.register_world(self)

	_build_terrain()
	_build_road()
	_build_landmarks()
	_build_scenery()
	_build_mission_props()
	call_deferred("_verify_playable_view")
	if OS.has_feature("android"):
		OS.request_permissions()

func _build_bootstrap_view() -> void:
	var safety_floor := StaticBody3D.new()
	safety_floor.name = "CampSafetyFloor"
	safety_floor.position = Vector3(0.0, ROUTE[0].y - 0.8, ROUTE[0].z)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(58.0, 0.8, 58.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_texture = GROUND_TEXTURE
	floor_material.uv1_scale = Vector3(18.0, 18.0, 18.0)
	floor_material.roughness = 0.96
	floor_mesh.material_override = floor_material
	safety_floor.add_child(floor_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = plane.size
	collision.shape = shape
	safety_floor.add_child(collision)
	add_child(safety_floor)

	var sign := SIGN_SCENE.instantiate() as Node3D
	sign.name = "CampTrailSignModel"
	sign.position = ROUTE[0] + Vector3(-7.0, 0.0, -3.0)
	sign.rotation.y = -0.35
	add_child(sign)

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
	var spawn := ROUTE[0] + Vector3(-3.0 + index * 1.4, 1.0, 8.5)
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
	return result

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("263f55")
	sky_material.sky_horizon_color = Color("d2875a")
	sky_material.ground_bottom_color = Color("2a2627")
	sky_material.ground_horizon_color = Color("9a6247")
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = not GameSession.reduced_graphics
	environment.fog_enabled = true
	environment.fog_light_color = Color("be896a")
	environment.fog_light_energy = 0.28
	environment.fog_density = 0.0028
	environment.fog_sky_affect = 0.62
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("ffd69a")
	sun.light_energy = 1.18
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 135.0
	add_child(sun)

func _build_terrain() -> void:
	var x_count := 74 if GameSession.reduced_graphics else 96
	var z_count := 104 if GameSession.reduced_graphics else 132
	var x_min := -130.0
	var x_max := 130.0
	var z_min := -270.0
	var z_max := 112.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
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
			uvs.append(Vector2(x * 0.08, z * 0.08))
	for z_index in z_count - 1:
		for x_index in x_count - 1:
			var current := z_index * x_count + x_index
			indices.append_array(PackedInt32Array([current, current + x_count, current + 1,
				current + 1, current + x_count, current + x_count + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.name = "RedmesaTerrain"
	terrain.mesh = mesh
	var shader_material := ShaderMaterial.new()
	shader_material.shader = TERRAIN_SHADER
	shader_material.set_shader_parameter("ground_texture", GROUND_TEXTURE)
	terrain.material_override = shader_material
	add_child(terrain)
	terrain.create_trimesh_collision()

func _build_road() -> void:
	var road_mesh := ImmediateMesh.new()
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color("8c6245")
	road_material.roughness = 1.0
	for segment in ROUTE.size() - 1:
		if segment == 3:
			continue
		var a := ROUTE[segment] + Vector3.UP * 0.09
		var b := ROUTE[segment + 1] + Vector3.UP * 0.09
		var forward := (b - a).normalized()
		var right := forward.cross(Vector3.UP).normalized() * 3.7
		road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, road_material)
		road_mesh.surface_set_uv(Vector2(0, 0)); road_mesh.surface_add_vertex(a - right)
		road_mesh.surface_set_uv(Vector2(0, 1)); road_mesh.surface_add_vertex(a + right)
		road_mesh.surface_set_uv(Vector2(1, 0)); road_mesh.surface_add_vertex(b - right)
		road_mesh.surface_set_uv(Vector2(1, 0)); road_mesh.surface_add_vertex(b - right)
		road_mesh.surface_set_uv(Vector2(0, 1)); road_mesh.surface_add_vertex(a + right)
		road_mesh.surface_set_uv(Vector2(1, 1)); road_mesh.surface_add_vertex(b + right)
		road_mesh.surface_end()
	var road := MeshInstance3D.new()
	road.name = "DustRoad"
	road.mesh = road_mesh
	add_child(road)

func _build_landmarks() -> void:
	props_root = Node3D.new()
	props_root.name = "OriginalLandmarks"
	add_child(props_root)
	# Starting campground
	PrimitiveFactory.box(props_root, "CampDeck", ROUTE[0] + Vector3(-5, 0.05, 0), Vector3(7, 0.25, 5), Color("68442d"), true)
	PrimitiveFactory.box(props_root, "CampAwning", ROUTE[0] + Vector3(-5, 2.1, 0), Vector3(6, 0.18, 4), Color("d29b55"), false)
	for x in [-7.4, -2.6]:
		for z in [83.2, 86.8]:
			PrimitiveFactory.cylinder(props_root, "AwningPost", Vector3(x, 3.25, z), 0.09, 2.2, Color("302a28"), false)
	PrimitiveFactory.label_3d(props_root, "REDMESA\nTRAIL CAMP", ROUTE[0] + Vector3(-5, 3.25, -2.2), Color("fff0d0"), 48)
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
	var tree_count := 74 if GameSession.reduced_graphics else 118
	for index in tree_count:
		var z := random.randf_range(-250.0, 103.0)
		var x := random.randf_range(-118.0, 118.0)
		var route_info := _nearest_route_data(Vector2(x, z))
		if route_info.x < 7.2:
			continue
		_make_tree(Vector3(x, terrain_height(x, z), z), 0.75 + random.randf() * 0.7, index % 5 == 0)
	var rock_count := 54 if GameSession.reduced_graphics else 86
	for index in rock_count:
		var z := random.randf_range(-255.0, 106.0)
		var x := random.randf_range(-122.0, 122.0)
		var route_info := _nearest_route_data(Vector2(x, z))
		if route_info.x < 5.4:
			continue
		var radius := random.randf_range(0.45, 1.75)
		_make_rock(Vector3(x, terrain_height(x, z), z), radius,
			Vector3(random.randf_range(0.8, 1.5), random.randf_range(0.55, 1.15), random.randf_range(0.8, 1.4)), index % 8 == 0)
	# Reliable cable anchors along challenge sections.
	for anchor_position in [Vector3(18, 5, -8), Vector3(46, 6, -32), Vector3(-34, 7, -109), Vector3(-13, 11, -131), Vector3(22, 19, -169), Vector3(-24, 29, -199)]:
		_make_winch_post(anchor_position)
	for wildlife_position in [Vector3(-36, 8, -82), Vector3(25, 17, -154), Vector3(-30, 28, -204)]:
		var wildlife: TrailWildlife = WildlifeScript.new()
		add_child(wildlife)
		wildlife.setup(Vector3(wildlife_position.x, terrain_height(wildlife_position.x, wildlife_position.z) + 0.2, wildlife_position.z))

func _make_tree(position: Vector3, scale_factor: float, anchor: bool) -> void:
	var tree := Node3D.new()
	tree.name = "CablePine" if anchor else "TexturedPine"
	tree.position = position
	tree.rotation.y = random.randf_range(-PI, PI)
	tree.scale = Vector3.ONE * scale_factor
	props_root.add_child(tree)
	var model := PINE_SCENE.instantiate()
	tree.add_child(model)
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
	var model := ROCK_SCENE.instantiate()
	rock_root.add_child(model)
	if collision_enabled:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.78
		collision.shape = shape
		collision.position.y = 0.6
		body.add_child(collision)
		rock_root.add_child(body)

func _make_winch_post(position: Vector3) -> void:
	var post := PrimitiveFactory.cylinder(props_root, "SteelWinchPost", position, 0.18, 2.6, Color("626c6c"), true)
	post.add_to_group("winch_anchor")
	PrimitiveFactory.box(post, "Marker", Vector3(0, 0.65, 0), Vector3(0.52, 0.32, 0.12), Color("e5a23b"))

func _build_mission_props() -> void:
	for offset in [Vector3(-7, 0.6, 5), Vector3(-4.8, 0.6, 5.6), Vector3(-2.6, 0.6, 5.1)]:
		_spawn_interactable("supply", ROUTE[0] + offset)
	_spawn_interactable("plank", ROUTE[3] + Vector3(-5.5, 0.6, 3.0))
	_spawn_interactable("plank", ROUTE[3] + Vector3(-4.0, 0.6, 4.2))
	_spawn_interactable("bridge_socket", ROUTE[3] + Vector3(-1.1, 0.5, -2.2))
	_spawn_interactable("bridge_socket", ROUTE[3] + Vector3(1.1, 0.5, -2.2))
	_spawn_interactable("repair_station", ROUTE[5] + Vector3(-3.5, 1.0, 1.2))
	_spawn_interactable("fuel", ROUTE[5] + Vector3(-2.0, 0.6, 1.1))
	_create_checkpoint(ROUTE[2], 1, "Dry Creek Overlook", Vector3(10, 5, 7))
	_create_checkpoint(ROUTE[5], 2, "Lantern Post Garage", Vector3(12, 6, 8))
	_create_checkpoint(ROUTE[8], 3, "Last Light Summit", Vector3(12, 7, 8))
	_create_checkpoint(ROUTE[-1], 4, "Route 17 Exit", Vector3(13, 8, 10))
	var rockfall: RockfallHazard = RockfallScript.new()
	add_child(rockfall)
	rockfall.setup((ROUTE[7] + ROUTE[8]) * 0.5 + Vector3.UP * 3.0, self)

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
	last_checkpoint_transform = Transform3D(rv.global_transform.basis.orthonormalized(), checkpoint_position + Vector3.UP * 2.2)
	GameSession.set_checkpoint(index, title)
	if index == 4:
		GameSession.complete_target("finish")

func _spawn_rv() -> void:
	rv = RVScript.new()
	add_child(rv)
	var basis := Basis(Vector3.UP, PI)
	rv.setup(Transform3D(basis, ROUTE[0] + Vector3(2.2, 2.1, -2.0)))
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

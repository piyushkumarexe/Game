class_name MenuDiorama
extends Node3D
## Live 3D title-screen campsite assembled from the same models used in play.

const RV_INTERIOR_SCENE: PackedScene = preload("res://assets/models/rv_exterior.gltf")
const RV_SCENE: PackedScene = preload("res://assets/third_party/gmc_motorhome/motorhome.gltf")
const RV_WHEEL_SCENE: PackedScene = preload("res://assets/third_party/gmc_motorhome/wheel.gltf")
const PINE_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/tree-pinetallb-detailed.glb")
const ROCK_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/rock-largeb.glb")
const TENT_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/tent-detailedopen.glb")
const CAMPFIRE_SCENE: PackedScene = preload("res://assets/third_party/kenney/nature-kit/campfire-stones.glb")
const SIGN_SCENE: PackedScene = preload("res://assets/models/trail_sign.gltf")
const GROUND_TEXTURE: Texture2D = preload("res://assets/textures/terrain_detail.png")
const ROAD_TEXTURE: Texture2D = preload("res://assets/textures/road_gravel.png")

var camera: Camera3D
var rig: Node3D
var elapsed := 0.0

func _ready() -> void:
	name = "Live3DMenuCampsite"
	_build_environment()
	_build_ground()
	_build_rig()
	_build_scenery()
	camera = Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = 53.0
	camera.position = Vector3(10.8, 4.15, 12.2)
	add_child(camera)
	camera.look_at(Vector3(1.0, 1.38, -0.6), Vector3.UP)
	camera.make_current()

func _process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(camera):
		return
	camera.position = Vector3(10.8 + sin(elapsed * 0.16) * 0.55, 4.15 + sin(elapsed * 0.22) * 0.10, 12.2 + cos(elapsed * 0.16) * 0.5)
	camera.look_at(Vector3(1.0, 1.38, -0.6), Vector3.UP)
	if is_instance_valid(rig):
		rig.rotation.y = -0.68 + sin(elapsed * 0.3) * 0.012

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4f91bc")
	sky_material.sky_horizon_color = Color("c9ded1")
	sky_material.ground_bottom_color = Color("526b55")
	sky_material.ground_horizon_color = Color("a9bea0")
	sky_material.sun_angle_max = 10.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("dce6d5")
	environment.ambient_light_energy = 0.64
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c2d3c4")
	environment.fog_light_energy = 0.4
	environment.fog_density = 0.0035
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -34.0, 0.0)
	sun.light_color = Color("fff0cf")
	sun.light_energy = 0.96
	sun.shadow_enabled = GameSession.graphics_quality > 0
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "TexturedMenuGround"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80.0, 80.0)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = GROUND_TEXTURE
	material.albedo_color = Color("78995b")
	material.uv1_scale = Vector3(8.0, 8.0, 8.0)
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)
	var road := MeshInstance3D.new()
	var road_mesh := PlaneMesh.new()
	road_mesh.size = Vector2(7.5, 42.0)
	road.mesh = road_mesh
	road.position = Vector3(1.8, 0.025, -4.0)
	road.rotation.y = -0.34
	var road_material := StandardMaterial3D.new()
	road_material.albedo_texture = ROAD_TEXTURE
	road_material.albedo_color = Color("e2c394")
	road_material.uv1_scale = Vector3(2.0, 8.0, 2.0)
	road_material.roughness = 1.0
	road.material_override = road_material
	add_child(road)

func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "MenuExpeditionRV"
	rig.position = Vector3(2.0, 0.02, -1.2)
	rig.rotation.y = -0.68
	add_child(rig)
	var exterior := RV_SCENE.instantiate() as Node3D
	exterior.name = "ProfessionalGMCMotorhome"
	exterior.position.y = 1.37
	exterior.rotation.y = PI
	exterior.scale = Vector3.ONE * 0.98
	rig.add_child(exterior)
	var interior := RV_INTERIOR_SCENE.instantiate() as Node3D
	interior.name = "MenuConnectedLivingInterior"
	interior.position.y = 0.86
	rig.add_child(interior)
	var old_shell := interior.find_child("StaticRVExterior", true, false) as Node3D
	if old_shell:
		old_shell.visible = false
	var old_cockpit := interior.find_child("StaticCockpitInterior", true, false) as Node3D
	if old_cockpit:
		old_cockpit.visible = false
	var old_frame := interior.find_child("StaticCockpitFrame", true, false) as Node3D
	if old_frame:
		old_frame.visible = false
	for x in [-1.16, 1.16]:
		for z in [-3.00, 1.12, 2.14]:
			_add_menu_wheel(Vector3(x, 0.43, z))

func _add_menu_wheel(wheel_position: Vector3) -> void:
	var wheel := RV_WHEEL_SCENE.instantiate() as Node3D
	wheel.name = "DetailedMenuWheel"
	wheel.position = wheel_position
	var side_scale := -1.145 if wheel_position.x < 0.0 else 1.145
	wheel.scale = Vector3(side_scale, 1.145, 1.145)
	rig.add_child(wheel)

func _build_scenery() -> void:
	var tree_data := [
		[Vector3(-8, 0, -8), 1.35], [Vector3(-4, 0, -13), 1.05],
		[Vector3(9, 0, -11), 1.2], [Vector3(13, 0, -7), 1.5],
		[Vector3(-12, 0, 2), 1.1], [Vector3(15, 0, 3), 1.25]
	]
	for data: Array in tree_data:
		var tree := PINE_SCENE.instantiate() as Node3D
		tree.position = data[0]
		tree.scale = Vector3.ONE * float(data[1]) * 3.45
		add_child(tree)
		_recolor_imported(tree, {
			"leaf": PrimitiveFactory.material(Color("356b42"), 0.98),
			"wood": PrimitiveFactory.material(Color("67452f"), 0.97)
		})
	for index in 11:
		var rock := ROCK_SCENE.instantiate() as Node3D
		var side := -1.0 if index % 2 == 0 else 1.0
		rock.position = Vector3(side * (5.5 + index * 0.65), 0.0, -9.0 + index * 2.1)
		rock.scale = Vector3(0.5 + (index % 3) * 0.22, 0.45 + (index % 2) * 0.18, 0.62) * 2.15
		rock.rotation.y = index * 0.77
		add_child(rock)
		_recolor_imported(rock, {
			"grass": PrimitiveFactory.material(Color("537746"), 0.98),
			"dirt": PrimitiveFactory.material(Color("776755"), 1.0),
			"default": PrimitiveFactory.material(Color("80766a"), 1.0)
		})
	var tent := TENT_SCENE.instantiate() as Node3D
	tent.position = Vector3(-5.3, 0.0, 1.8)
	tent.rotation.y = 0.42
	tent.scale = Vector3.ONE * 3.2
	add_child(tent)
	_recolor_imported(tent, {
		"colorred": PrimitiveFactory.material(Color("a95836"), 0.94),
		"wood": PrimitiveFactory.material(Color("6f472c"), 0.96)
	})
	var fire_ring := CAMPFIRE_SCENE.instantiate() as Node3D
	fire_ring.position = Vector3(-1.8, 0.02, 2.1)
	fire_ring.scale = Vector3.ONE * 2.3
	add_child(fire_ring)
	_recolor_imported(fire_ring, {"stone": PrimitiveFactory.material(Color("76736a"), 1.0)})
	var sign := SIGN_SCENE.instantiate() as Node3D
	sign.position = Vector3(-2.7, 0.0, -4.6)
	sign.rotation.y = 0.42
	add_child(sign)

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

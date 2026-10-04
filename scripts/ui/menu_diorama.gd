class_name MenuDiorama
extends Node3D
## Live 3D title-screen campsite assembled from the same models used in play.

const RV_SCENE: PackedScene = preload("res://assets/models/rv_exterior.gltf")
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
	camera.position = Vector3(10.8, 5.0, 11.8)
	add_child(camera)
	camera.look_at(Vector3(1.0, 1.75, -0.6), Vector3.UP)
	camera.make_current()

func _process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(camera):
		return
	camera.position = Vector3(10.8 + sin(elapsed * 0.16) * 0.55, 5.0 + sin(elapsed * 0.22) * 0.12, 11.8 + cos(elapsed * 0.16) * 0.5)
	camera.look_at(Vector3(1.0, 1.75, -0.6), Vector3.UP)
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
	environment.ambient_light_energy = 0.82
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
	sun.light_energy = 1.08
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
	exterior.name = "OriginalDustboundCamper"
	exterior.position.y = 1.25
	rig.add_child(exterior)
	for x in [-1.18, 1.18]:
		for z in [-2.08, 1.92]:
			_add_menu_wheel(Vector3(x, 0.58, z))

func _add_menu_wheel(wheel_position: Vector3) -> void:
	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = 0.56
	tire_mesh.bottom_radius = 0.56
	tire_mesh.height = 0.34
	tire_mesh.radial_segments = 16
	tire.mesh = tire_mesh
	tire.position = wheel_position
	tire.rotation.z = PI * 0.5
	tire.material_override = PrimitiveFactory.material(Color("17191c"), 0.96)
	rig.add_child(tire)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.22
	hub_mesh.bottom_radius = 0.22
	hub_mesh.height = 0.38
	hub_mesh.radial_segments = 12
	hub.mesh = hub_mesh
	hub.position = wheel_position
	hub.rotation.z = PI * 0.5
	hub.material_override = PrimitiveFactory.material(Color("9ca59d"), 0.38, 0.45)
	rig.add_child(hub)

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
	for index in 11:
		var rock := ROCK_SCENE.instantiate() as Node3D
		var side := -1.0 if index % 2 == 0 else 1.0
		rock.position = Vector3(side * (5.5 + index * 0.65), 0.0, -9.0 + index * 2.1)
		rock.scale = Vector3(0.5 + (index % 3) * 0.22, 0.45 + (index % 2) * 0.18, 0.62) * 2.15
		rock.rotation.y = index * 0.77
		add_child(rock)
	var tent := TENT_SCENE.instantiate() as Node3D
	tent.position = Vector3(-5.3, 0.0, 1.8)
	tent.rotation.y = 0.42
	tent.scale = Vector3.ONE * 3.2
	add_child(tent)
	var fire_ring := CAMPFIRE_SCENE.instantiate() as Node3D
	fire_ring.position = Vector3(-1.8, 0.02, 2.1)
	fire_ring.scale = Vector3.ONE * 2.3
	add_child(fire_ring)
	var sign := SIGN_SCENE.instantiate() as Node3D
	sign.position = Vector3(-2.7, 0.0, -4.6)
	sign.rotation.y = 0.42
	add_child(sign)

class_name MenuDiorama
extends Node3D
## Live 3D title-screen campsite assembled from the same original models used in play.

const RV_SCENE: PackedScene = preload("res://assets/models/rv_exterior.gltf")
const PINE_SCENE: PackedScene = preload("res://assets/models/pine_tree.gltf")
const ROCK_SCENE: PackedScene = preload("res://assets/models/canyon_rock.gltf")
const SIGN_SCENE: PackedScene = preload("res://assets/models/trail_sign.gltf")
const GROUND_TEXTURE: Texture2D = preload("res://assets/textures/ground_dirt.png")

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
	camera.look_at(Vector3(1.0, 1.15, -0.6), Vector3.UP)
	camera.make_current()

func _process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(camera):
		return
	camera.position = Vector3(10.8 + sin(elapsed * 0.16) * 0.55, 5.0 + sin(elapsed * 0.22) * 0.12, 11.8 + cos(elapsed * 0.16) * 0.5)
	camera.look_at(Vector3(1.0, 1.15, -0.6), Vector3.UP)
	if is_instance_valid(rig):
		rig.rotation.y = -0.68 + sin(elapsed * 0.3) * 0.012

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("172f47")
	sky_material.sky_horizon_color = Color("e58b50")
	sky_material.ground_bottom_color = Color("171619")
	sky_material.ground_horizon_color = Color("8c4d35")
	sky_material.sun_angle_max = 10.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.88
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("cf7953")
	environment.fog_density = 0.008
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color("ffd19a")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
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
	material.uv1_scale = Vector3(18.0, 18.0, 18.0)
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
	road_material.albedo_color = Color("8c5639")
	road_material.roughness = 1.0
	road.material_override = road_material
	add_child(road)

func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "MenuTexturedRV"
	rig.position = Vector3(2.0, 0.58, -1.2)
	rig.rotation.y = -0.68
	add_child(rig)
	var exterior := RV_SCENE.instantiate()
	rig.add_child(exterior)
	for wheel_position in [Vector3(-1.2, 0.0, -1.82), Vector3(1.2, 0.0, -1.82), Vector3(-1.2, 0.0, 1.78), Vector3(1.2, 0.0, 1.78)]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.57
		wheel_mesh.bottom_radius = 0.57
		wheel_mesh.height = 0.36
		wheel_mesh.radial_segments = 16
		wheel.mesh = wheel_mesh
		wheel.position = wheel_position
		wheel.rotation.z = PI * 0.5
		wheel.material_override = PrimitiveFactory.material(Color("15171a"), 0.96)
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
		tree.scale = Vector3.ONE * float(data[1])
		add_child(tree)
	for index in 11:
		var rock := ROCK_SCENE.instantiate() as Node3D
		var side := -1.0 if index % 2 == 0 else 1.0
		rock.position = Vector3(side * (5.5 + index * 0.65), 0.0, -9.0 + index * 2.1)
		rock.scale = Vector3(0.5 + (index % 3) * 0.22, 0.45 + (index % 2) * 0.18, 0.62)
		rock.rotation.y = index * 0.77
		add_child(rock)
	var sign := SIGN_SCENE.instantiate() as Node3D
	sign.position = Vector3(-2.7, 0.0, -4.6)
	sign.rotation.y = 0.42
	add_child(sign)

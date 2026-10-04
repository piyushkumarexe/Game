class_name StylizedCrewVisual
extends Node3D
## Original rounded road-trip character with an articulated procedural rig.
## The proportions intentionally suit the chunky, readable mobile silhouette.

var body_root: Node3D
var left_shoulder: Node3D
var right_shoulder: Node3D
var left_hip: Node3D
var right_hip: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var phase := 0.0
var current_state := "Idle"

func _ready() -> void:
	_build_character()

func _build_character() -> void:
	body_root = Node3D.new()
	body_root.name = "CharacterMotionRoot"
	add_child(body_root)

	# Rounded body, shirt and separate padded vest panels.
	_ellipsoid(body_root, "ShirtBody", Vector3(0, 1.16, 0), Vector3(0.92, 1.02, 0.68), Color("f3eee0"))
	_ellipsoid(body_root, "Belly", Vector3(0, 0.89, 0.04), Vector3(0.88, 0.62, 0.64), Color("c5aa75"))
	_ellipsoid(body_root, "VestLeft", Vector3(-0.24, 1.22, 0.47), Vector3(0.40, 0.78, 0.16), Color("a8442d"))
	_ellipsoid(body_root, "VestRight", Vector3(0.24, 1.22, 0.47), Vector3(0.40, 0.78, 0.16), Color("a8442d"))
	_box(body_root, "VestZip", Vector3(0, 1.18, 0.565), Vector3(0.055, 0.70, 0.035), Color("e5d7bd"))
	for side in [-1.0, 1.0]:
		_box(body_root, "VestPocket", Vector3(side * 0.24, 1.00, 0.565), Vector3(0.27, 0.18, 0.035), Color("7f3024"))

	# Friendly large head, ears, nose, cap and proper sunglasses.
	_ellipsoid(body_root, "Head", Vector3(0, 1.91, 0.02), Vector3(0.72, 0.64, 0.65), Color("d49a70"))
	_ellipsoid(body_root, "Nose", Vector3(0, 1.84, 0.60), Vector3(0.18, 0.15, 0.18), Color("c98161"))
	_ellipsoid(body_root, "EarLeft", Vector3(-0.38, 1.91, 0.02), Vector3(0.15, 0.22, 0.11), Color("cb8c68"))
	_ellipsoid(body_root, "EarRight", Vector3(0.38, 1.91, 0.02), Vector3(0.15, 0.22, 0.11), Color("cb8c68"))
	_ellipsoid(body_root, "CapCrown", Vector3(0, 2.22, 0.01), Vector3(0.72, 0.30, 0.66), Color("292e35"))
	_box(body_root, "CapBrim", Vector3(0, 2.10, 0.47), Vector3(0.72, 0.08, 0.37), Color("20252a"))
	_cylinder_lens(body_root, "LeftLens", Vector3(-0.19, 1.95, 0.575))
	_cylinder_lens(body_root, "RightLens", Vector3(0.19, 1.95, 0.575))
	_box(body_root, "GlassesBridge", Vector3(0, 1.96, 0.59), Vector3(0.14, 0.045, 0.045), Color("11151a"))
	for side in [-1.0, 1.0]:
		_box(body_root, "GlassesArm", Vector3(side * 0.34, 1.98, 0.38), Vector3(0.18, 0.035, 0.04), Color("11151a"))

	# Shoulder and elbow hierarchy gives visible walk/run/jump motion.
	left_shoulder = _limb_pivot(body_root, "LeftShoulder", Vector3(-0.53, 1.48, 0.02))
	right_shoulder = _limb_pivot(body_root, "RightShoulder", Vector3(0.53, 1.48, 0.02))
	_build_arm(left_shoulder, "Left")
	_build_arm(right_shoulder, "Right")

	left_hip = _limb_pivot(body_root, "LeftHip", Vector3(-0.24, 0.72, 0.0))
	right_hip = _limb_pivot(body_root, "RightHip", Vector3(0.24, 0.72, 0.0))
	_build_leg(left_hip, "Left")
	_build_leg(right_hip, "Right")

func _build_arm(pivot: Node3D, prefix: String) -> void:
	_ellipsoid(pivot, prefix + "Sleeve", Vector3(0, -0.20, 0), Vector3(0.25, 0.42, 0.25), Color("efe8d8"))
	_ellipsoid(pivot, prefix + "Arm", Vector3(0, -0.46, 0), Vector3(0.18, 0.34, 0.18), Color("d49a70"))
	var forearm := Node3D.new()
	forearm.name = prefix + "Elbow"
	forearm.position = Vector3(0, -0.57, 0)
	pivot.add_child(forearm)
	_ellipsoid(forearm, prefix + "Hand", Vector3(0, -0.14, 0.02), Vector3(0.20, 0.28, 0.20), Color("d49a70"))
	if prefix == "Left":
		left_forearm = forearm
	else:
		right_forearm = forearm

func _build_leg(pivot: Node3D, prefix: String) -> void:
	_ellipsoid(pivot, prefix + "TrouserLeg", Vector3(0, -0.26, 0), Vector3(0.34, 0.52, 0.38), Color("62684d"))
	_ellipsoid(pivot, prefix + "Shoe", Vector3(0, -0.55, 0.12), Vector3(0.36, 0.22, 0.50), Color("26292c"))

func _limb_pivot(parent: Node3D, pivot_name: String, pivot_position: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = pivot_position
	parent.add_child(pivot)
	return pivot

func _ellipsoid(parent: Node3D, mesh_name: String, mesh_position: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 18
	mesh.rings = 10
	instance.mesh = mesh
	instance.position = mesh_position
	instance.scale = dimensions
	instance.material_override = PrimitiveFactory.material(color, 0.82)
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, mesh_name: String, mesh_position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = mesh_position
	instance.material_override = PrimitiveFactory.material(color, 0.80)
	parent.add_child(instance)
	return instance

func _cylinder_lens(parent: Node3D, mesh_name: String, mesh_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 0.055
	mesh.radial_segments = 18
	instance.mesh = mesh
	instance.position = mesh_position
	instance.rotation.x = PI * 0.5
	instance.scale = Vector3(1.0, 1.0, 0.78)
	instance.material_override = PrimitiveFactory.material(Color("11151a"), 0.22, 0.12)
	parent.add_child(instance)

func set_locomotion(state: String, horizontal_speed: float, vertical_speed: float, delta: float) -> void:
	current_state = state
	var stride := 0.0
	var arm_stride := 0.0
	var bob := 0.0
	var lean := 0.0
	if state == "Walk":
		phase += delta * maxf(4.8, horizontal_speed * 1.35)
		stride = sin(phase) * 0.48
		arm_stride = stride * 0.82
		bob = absf(sin(phase)) * 0.035
		lean = 0.05
	elif state == "Run":
		phase += delta * maxf(7.5, horizontal_speed * 1.55)
		stride = sin(phase) * 0.78
		arm_stride = stride * 0.92
		bob = absf(sin(phase)) * 0.075
		lean = 0.14
	elif state in ["Jump", "Jump_Idle"]:
		stride = -0.34 if vertical_speed > 0.0 else 0.18
		arm_stride = -0.72
		bob = 0.04
		lean = -0.04
	elif state == "Jump_Land":
		stride = 0.28
		arm_stride = 0.18
		bob = -0.11
		lean = 0.16
	else:
		phase += delta * 1.45
		bob = sin(phase) * 0.012
		arm_stride = sin(phase * 0.72) * 0.035

	left_hip.rotation.x = lerp_angle(left_hip.rotation.x, stride, minf(1.0, delta * 12.0))
	right_hip.rotation.x = lerp_angle(right_hip.rotation.x, -stride, minf(1.0, delta * 12.0))
	left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, -arm_stride, minf(1.0, delta * 11.0))
	right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, arm_stride, minf(1.0, delta * 11.0))
	left_forearm.rotation.x = lerp_angle(left_forearm.rotation.x, -0.12 - absf(arm_stride) * 0.28, minf(1.0, delta * 10.0))
	right_forearm.rotation.x = lerp_angle(right_forearm.rotation.x, -0.12 - absf(arm_stride) * 0.28, minf(1.0, delta * 10.0))
	body_root.position.y = lerpf(body_root.position.y, bob, minf(1.0, delta * 13.0))
	body_root.rotation.x = lerp_angle(body_root.rotation.x, lean, minf(1.0, delta * 9.0))

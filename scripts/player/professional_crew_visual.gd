class_name ProfessionalCrewVisual
extends Node3D
## Quaternius' professional CC0 skinned humanoid, composed with a Ranger outfit.
## The original named skeleton is driven directly so directional travel never
## becomes the static sideways slide that the rejected placeholder displayed.

const HEAD_SCENE: PackedScene = preload("res://assets/third_party/quaternius_crew/crew_head.gltf")
const OUTFIT_SCENE: PackedScene = preload("res://assets/third_party/quaternius_crew/ranger_outfit.gltf")

var motion_root: Node3D
var skeletons: Array[Skeleton3D] = []
var phase := 0.0
var current_state := "Idle"

func _ready() -> void:
	_build_character()

func _build_character() -> void:
	motion_root = Node3D.new()
	motion_root.name = "ProfessionalCharacterMotionRoot"
	# A slightly broader chest/depth gives the requested stout road-trip silhouette
	# without distorting facial placement or shortening the authored skeleton.
	motion_root.scale = Vector3(1.10, 0.99, 1.14)
	add_child(motion_root)

	var outfit := OUTFIT_SCENE.instantiate() as Node3D
	outfit.name = "QuaterniusRangerOutfit"
	motion_root.add_child(outfit)
	var head := HEAD_SCENE.instantiate() as Node3D
	head.name = "QuaterniusProfessionalHead"
	motion_root.add_child(head)
	_collect_skeletons(outfit)
	_collect_skeletons(head)
	_build_expedition_accessories()
	# Lower the A-pose immediately rather than exposing one T/A-pose frame.
	_apply_pose(0.0, 0.0, 0.0, 1.0)

func _collect_skeletons(node: Node) -> void:
	if node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	for child in node.get_children():
		_collect_skeletons(child)

func _material(color: Color, roughness := 0.76, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh(parent: Node3D, mesh_name: String, mesh: PrimitiveMesh, mesh_position: Vector3,
		material: Material, mesh_scale := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = mesh_position
	instance.scale = mesh_scale
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _build_expedition_accessories() -> void:
	var charcoal := _material(Color("20262b"), 0.88)
	var lens := _material(Color("111b21"), 0.16, 0.18)
	var vest := _material(Color("a84b2e"), 0.84)
	var trim := _material(Color("e1c9a4"), 0.70)

	var crown := CylinderMesh.new()
	crown.top_radius = 0.145
	crown.bottom_radius = 0.190
	crown.height = 0.145
	crown.radial_segments = 24
	_mesh(motion_root, "ExpeditionCapCrown", crown, Vector3(0.0, 1.790, 0.002), charcoal)
	var brim := BoxMesh.new()
	brim.size = Vector3(0.29, 0.035, 0.19)
	var brim_instance := _mesh(motion_root, "ExpeditionCapBrim", brim, Vector3(0.0, 1.735, 0.120), charcoal)
	brim_instance.rotation.x = -0.08

	# Compact, correctly spaced lenses sit over the authored normal-spaced eyes.
	for side in [-1.0, 1.0]:
		var lens_mesh := BoxMesh.new()
		lens_mesh.size = Vector3(0.105, 0.064, 0.018)
		var lens_instance := _mesh(motion_root, "SunglassLens", lens_mesh,
			Vector3(side * 0.061, 1.693, 0.142), lens)
		lens_instance.rotation.z = side * -0.025
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.035, 0.014, 0.020)
	_mesh(motion_root, "SunglassBridge", bridge, Vector3(0.0, 1.694, 0.144), charcoal)
	for side in [-1.0, 1.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(0.09, 0.014, 0.014)
		_mesh(motion_root, "SunglassArm", arm, Vector3(side * 0.125, 1.696, 0.108), charcoal)

	# Lightweight padded vest panels layer over the authored Ranger body while
	# preserving its belts, boots, gloves, normals and skinning.
	for side in [-1.0, 1.0]:
		var panel := SphereMesh.new()
		panel.radius = 0.5
		panel.height = 1.0
		panel.radial_segments = 20
		panel.rings = 10
		_mesh(motion_root, "PaddedVestPanel", panel, Vector3(side * 0.145, 1.235, 0.158), vest,
			Vector3(0.29, 0.50, 0.105))
		for row in range(3):
			var seam := BoxMesh.new()
			seam.size = Vector3(0.24, 0.012, 0.012)
			_mesh(motion_root, "VestQuiltSeam", seam,
				Vector3(side * 0.145, 1.065 + row * 0.17, 0.252), trim)
	var zipper := BoxMesh.new()
	zipper.size = Vector3(0.022, 0.62, 0.018)
	_mesh(motion_root, "VestZipper", zipper, Vector3(0.0, 1.225, 0.250), trim)

func _set_bone(skeleton: Skeleton3D, bone_name: String, target: Quaternion, weight: float) -> void:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return
	var current := skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, current.slerp(target, clampf(weight, 0.0, 1.0)))

func _apply_pose(stride: float, arm_swing: float, crouch: float, weight: float) -> void:
	# Local Z lowers the authored A-pose arms; local X supplies opposing natural
	# gait swing. Knees flex on every planted half-cycle instead of remaining rigid.
	for skeleton in skeletons:
		_set_bone(skeleton, "upperarm_l",
			Quaternion(Vector3.FORWARD, 1.42) * Quaternion(Vector3.RIGHT, -arm_swing), weight)
		_set_bone(skeleton, "upperarm_r",
			Quaternion(Vector3.FORWARD, -1.42) * Quaternion(Vector3.RIGHT, arm_swing), weight)
		_set_bone(skeleton, "lowerarm_l", Quaternion(Vector3.RIGHT, -0.16 - absf(arm_swing) * 0.18), weight)
		_set_bone(skeleton, "lowerarm_r", Quaternion(Vector3.RIGHT, -0.16 - absf(arm_swing) * 0.18), weight)
		_set_bone(skeleton, "thigh_l", Quaternion(Vector3.RIGHT, stride + crouch), weight)
		_set_bone(skeleton, "thigh_r", Quaternion(Vector3.RIGHT, -stride + crouch), weight)
		_set_bone(skeleton, "calf_l", Quaternion(Vector3.RIGHT, -maxf(0.05, -stride * 0.55) - crouch), weight)
		_set_bone(skeleton, "calf_r", Quaternion(Vector3.RIGHT, -maxf(0.05, stride * 0.55) - crouch), weight)
		_set_bone(skeleton, "spine_01", Quaternion(Vector3.RIGHT, -crouch * 0.35), weight)
		_set_bone(skeleton, "Head", Quaternion(Vector3.UP, sin(phase * 0.42) * 0.025), weight)

func set_locomotion(state: String, horizontal_speed: float, vertical_speed: float, delta: float) -> void:
	current_state = state
	var stride := 0.0
	var arm_swing := 0.0
	var crouch := 0.0
	var bob := 0.0
	var lean := 0.0
	if state == "Walk":
		phase += delta * maxf(5.2, horizontal_speed * 1.45)
		stride = sin(phase) * 0.56
		arm_swing = stride * 0.78
		bob = absf(sin(phase)) * 0.030
		lean = 0.035
	elif state == "Run":
		phase += delta * maxf(8.0, horizontal_speed * 1.65)
		stride = sin(phase) * 0.82
		arm_swing = stride * 0.90
		bob = absf(sin(phase)) * 0.065
		lean = 0.105
	elif state in ["Jump", "Jump_Idle"]:
		stride = -0.28 if vertical_speed > 0.0 else 0.18
		arm_swing = -0.62
		crouch = 0.16
		bob = 0.025
		lean = -0.025
	elif state == "Jump_Land":
		crouch = 0.38
		arm_swing = 0.15
		bob = -0.085
		lean = 0.13
	else:
		phase += delta * 1.35
		arm_swing = sin(phase * 0.55) * 0.025
		bob = sin(phase) * 0.008
	var blend := minf(1.0, delta * (15.0 if state.begins_with("Jump") else 10.0))
	_apply_pose(stride, arm_swing, crouch, blend)
	motion_root.position.y = lerpf(motion_root.position.y, bob, minf(1.0, delta * 13.0))
	motion_root.rotation.x = lerp_angle(motion_root.rotation.x, lean, minf(1.0, delta * 9.0))

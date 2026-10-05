class_name ProfessionalCrewVisual
extends Node3D
## Quaternius' CC0 skinned crew, driven by its authored animation library.
## The outfit and retained head use identical named skeletons; each frame copies
## the official source pose instead of guessing rotations on importer-rolled axes.

const HEAD_SCENE: PackedScene = preload("res://assets/third_party/quaternius_crew/crew_head.gltf")
const OUTFIT_SCENE: PackedScene = preload("res://assets/third_party/quaternius_crew/ranger_outfit.gltf")
const ANIMATION_SCENE: PackedScene = preload("res://assets/third_party/quaternius_crew/animations.glb")

var motion_root: Node3D
var animation_rig: Node3D
var animation_skeleton: Skeleton3D
var animation_player: AnimationPlayer
var skeletons: Array[Skeleton3D] = []
var accessory_root: Node3D
var current_state := ""
var current_clip := ""

func _ready() -> void:
	_build_character()

func _build_character() -> void:
	motion_root = Node3D.new()
	motion_root.name = "ProfessionalCharacterMotionRoot"
	# A restrained broadening creates the stout expedition silhouette without
	# warping the skeleton, face, hands or leg length.
	motion_root.scale = Vector3(1.06, 1.0, 1.08)
	add_child(motion_root)

	animation_rig = ANIMATION_SCENE.instantiate() as Node3D
	animation_rig.name = "QuaterniusAuthoredAnimationRig"
	motion_root.add_child(animation_rig)
	animation_skeleton = _find_skeleton(animation_rig)
	animation_player = _find_animation_player(animation_rig)
	# The animation file includes a neutral preview mannequin. Only its skeleton
	# is used; the textured Ranger outfit and retained professional head render.
	for candidate: Node in animation_rig.find_children("*", "GeometryInstance3D", true, false):
		(candidate as GeometryInstance3D).visible = false

	var outfit := OUTFIT_SCENE.instantiate() as Node3D
	outfit.name = "QuaterniusRangerOutfit"
	motion_root.add_child(outfit)
	_collect_target_skeletons(outfit)

	var head := HEAD_SCENE.instantiate() as Node3D
	head.name = "QuaterniusProfessionalHead"
	# Scale around the authored 1.70 m face centre instead of the character feet.
	head.scale = Vector3.ONE * 1.12
	head.position.y = -0.205
	motion_root.add_child(head)
	_collect_target_skeletons(head)

	_build_head_accessories()
	_configure_animation_loops()
	_play_clip("Idle_No", 1.0, 0.0)
	_copy_animation_pose()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	var best := node as AnimationPlayer if node is AnimationPlayer else null
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found and (not best or found.get_animation_list().size() > best.get_animation_list().size()):
			best = found
	return best

func _collect_target_skeletons(node: Node) -> void:
	if node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	for child: Node in node.get_children():
		_collect_target_skeletons(child)

func _material(color: Color, roughness := 0.76, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh(parent: Node3D, mesh_name: String, mesh: PrimitiveMesh, mesh_position: Vector3,
		material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = mesh_position
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _build_head_accessories() -> void:
	# Accessories follow the animated Head bone as one assembly. The previous
	# world-space boxes separated from the face during jumps and looked broken.
	accessory_root = Node3D.new()
	accessory_root.name = "AnimatedHeadAccessories"
	motion_root.add_child(accessory_root)
	var charcoal := _material(Color("20262b"), 0.82)
	var lens := _material(Color("070b0d"), 0.34, 0.02)

	# A low rounded crown reads as a real expedition/baseball cap. The former
	# flat cylinder looked like an oversized top hat in the phone close-up.
	var crown := SphereMesh.new()
	crown.radius = 0.112
	crown.height = 0.224
	crown.radial_segments = 32
	crown.rings = 12
	var crown_instance := _mesh(accessory_root, "ExpeditionCapCrown", crown, Vector3(0.0, 0.157, 0.022), charcoal)
	crown_instance.scale.y = 0.44
	var brim := BoxMesh.new()
	brim.size = Vector3(0.202, 0.016, 0.108)
	var brim_instance := _mesh(accessory_root, "ExpeditionCapBrim", brim, Vector3(0.0, 0.120, 0.128), charcoal)
	brim_instance.rotation.x = -0.10

	# Rounded lenses sit over the authored eyes—not over the eyebrows. The former
	# high rectangular pair made the eyes look detached and exaggerated their gap
	# in the phone close-up. Shallow spheres provide a convincing curved silhouette
	# while remaining inexpensive enough for the mobile character.
	for side in [-1.0, 1.0]:
		var lens_mesh := SphereMesh.new()
		lens_mesh.radius = 0.042
		lens_mesh.height = 0.084
		lens_mesh.radial_segments = 20
		lens_mesh.rings = 8
		var lens_instance := _mesh(accessory_root, "SunglassLens", lens_mesh,
			Vector3(side * 0.040, -0.005, 0.178), lens)
		lens_instance.scale = Vector3(1.08, 0.67, 0.16)
		lens_instance.rotation.z = side * -0.025
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.018, 0.006, 0.010)
	_mesh(accessory_root, "SunglassBridge", bridge, Vector3(0.0, -0.004, 0.181), charcoal)
	for side in [-1.0, 1.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(0.055, 0.007, 0.012)
		_mesh(accessory_root, "SunglassTemple", arm,
			Vector3(side * 0.084, -0.002, 0.158), charcoal)

func _resolve_clip(requested: String) -> StringName:
	if not animation_player:
		return StringName()
	if animation_player.has_animation(requested):
		return StringName(requested)
	# Godot places glTF animations in a named library on some import backends,
	# producing `library/Clip` even though the source animation name is `Clip`.
	for available: StringName in animation_player.get_animation_list():
		var available_name := str(available)
		if available_name == requested or available_name.ends_with("/" + requested):
			return available
	return StringName()

func _configure_animation_loops() -> void:
	if not animation_player:
		return
	for requested in ["Idle_No", "Walk_Carry", "NinjaJump_Idle"]:
		var clip := _resolve_clip(requested)
		if not clip.is_empty():
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR

func _play_clip(requested: String, speed: float, blend := 0.14) -> void:
	var clip := _resolve_clip(requested)
	if clip.is_empty():
		return
	if current_clip != requested:
		current_clip = requested
		animation_player.play(clip, blend, speed)
		animation_player.advance(0.0)
	else:
		animation_player.speed_scale = speed

func _copy_animation_pose() -> void:
	if not animation_skeleton:
		return
	# The source's generic `Idle_No` clip looks sharply at the ground through both
	# neck and head tracks. Preserve the authored body motion but neutralize those
	# two joints so the face, cap and glasses present forward in normal gameplay.
	for neutral_bone_name in ["Neck", "Head"]:
		var neutral_bone_index := animation_skeleton.find_bone(neutral_bone_name)
		if neutral_bone_index >= 0:
			animation_skeleton.set_bone_pose_rotation(neutral_bone_index, Quaternion.IDENTITY)
	for target: Skeleton3D in skeletons:
		for source_index in animation_skeleton.get_bone_count():
			var target_index := target.find_bone(animation_skeleton.get_bone_name(source_index))
			if target_index < 0:
				continue
			target.set_bone_pose_position(target_index, animation_skeleton.get_bone_pose_position(source_index))
			target.set_bone_pose_rotation(target_index, animation_skeleton.get_bone_pose_rotation(source_index))
			target.set_bone_pose_scale(target_index, animation_skeleton.get_bone_pose_scale(source_index))
		# The source idle keeps its gaze several degrees below the horizon even
		# after its animation tracks are neutralized. A restrained lift presents
		# the face to the gameplay camera without stretching the neck or changing
		# the normal-spaced authored eyes.
		for correction in [["Neck", -0.07], ["Head", -0.10]]:
			var correction_index := target.find_bone(str(correction[0]))
			if correction_index >= 0:
				var copied_rotation := target.get_bone_pose_rotation(correction_index)
				target.set_bone_pose_rotation(correction_index,
					Quaternion(Vector3.RIGHT, float(correction[1])) * copied_rotation)
	if accessory_root:
		var head_index := animation_skeleton.find_bone("Head")
		if head_index >= 0:
			var head_pose := animation_skeleton.get_bone_global_pose(head_index)
			# Bone bases describe joint roll, not the mesh's facial forward axis.
			# Applying that basis turned the brim and glasses ninety degrees across
			# the face. Follow the animated head position while the neutral head and
			# accessories retain the character model's +Z facial orientation.
			accessory_root.position = head_pose.origin + Vector3(0.0, 0.018, 0.012)
			accessory_root.rotation = Vector3.ZERO
			accessory_root.scale = Vector3.ONE

func set_locomotion(state: String, horizontal_speed: float, _vertical_speed: float, _delta: float) -> void:
	current_state = state
	match state:
		"Walk":
			_play_clip("Walk_Carry", clampf(horizontal_speed / 4.4, 0.75, 1.25))
		"Run":
			_play_clip("Walk_Carry", clampf(horizontal_speed / 4.4, 1.35, 1.85), 0.10)
		"Jump":
			_play_clip("NinjaJump_Start", 1.0, 0.08)
		"Jump_Idle":
			_play_clip("NinjaJump_Idle", 1.0, 0.08)
		"Jump_Land":
			_play_clip("NinjaJump_Land", 1.0, 0.06)
		_:
			_play_clip("Idle_No", 1.0)
	_copy_animation_pose()

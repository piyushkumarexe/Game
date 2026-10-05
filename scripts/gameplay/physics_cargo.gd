class_name PhysicsCargo
extends RigidBody3D
## Carryable, droppable cargo that remains a real world object.

const CRATE_SCENE: PackedScene = preload("res://assets/third_party/kenney/platformer-kit/crate-strong.glb")
const WHEEL_SCENE: PackedScene = preload("res://assets/third_party/gmc_motorhome/wheel.gltf")

var cargo_kind := "supply"
var prompt := "CARRY SUPPLY CRATE"
var carrier: Node
var stowed := false
var uses_remaining := 0
var original_layer := 8
var original_mask := 1 | 4 | 8

func setup(kind: String, world_position: Vector3) -> void:
	cargo_kind = kind
	name = "%sCargo" % kind.capitalize()
	uses_remaining = 5 if kind == "extinguisher" else 0
	global_position = world_position
	mass = 18.0 if kind == "supply" else (9.0 if kind == "plank" or kind == "spare_tire" else 3.5)
	linear_damp = 0.55
	angular_damp = 1.8
	continuous_cd = true
	can_sleep = true
	collision_layer = original_layer
	collision_mask = original_mask
	contact_monitor = true
	max_contacts_reported = 6
	_build_visual()

func interact(player: Node) -> void:
	if stowed or carrier:
		return
	if player and player.has_method("pick_up_cargo"):
		player.pick_up_cargo(self)

func attach_to_carrier(player: Node, mount: Node3D) -> void:
	carrier = player
	freeze = true
	collision_layer = 0
	collision_mask = 0
	reparent(mount, false)
	position = Vector3(0.0, -0.20, -1.35)
	rotation = Vector3(0.08, 0.0, 0.05)

func drop_from_carrier(world_parent: Node, drop_transform: Transform3D, inherited_velocity: Vector3) -> void:
	carrier = null
	reparent(world_parent, false)
	global_transform = drop_transform
	collision_layer = original_layer
	collision_mask = original_mask
	freeze = false
	sleeping = false
	linear_velocity = inherited_velocity
	angular_velocity = Vector3.ZERO

func stow_in_rv(vehicle: Node3D, local_position: Vector3) -> void:
	carrier = null
	stowed = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	reparent(vehicle, false)
	position = local_position
	rotation = Vector3.ZERO
	prompt = "SUPPLY STOWED"

func use_charge() -> bool:
	if uses_remaining <= 0:
		return false
	uses_remaining -= 1
	return true

func consume() -> void:
	stowed = true
	carrier = null
	collision_layer = 0
	collision_mask = 0
	visible = false
	queue_free()

func _build_visual() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if cargo_kind == "plank":
		shape.size = Vector3(2.8, 0.18, 0.48)
		_add_box_visual(shape.size, Color("8f6137"))
		prompt = "CARRY BRIDGE PLANK"
	elif cargo_kind == "supply":
		shape.size = Vector3(0.92, 0.76, 0.78)
		var crate := CRATE_SCENE.instantiate() as Node3D
		crate.name = "PhysicalSupplyCrate"
		add_child(crate)
		prompt = "CARRY SUPPLY CRATE"
	elif cargo_kind == "hammer":
		shape.size = Vector3(0.18, 0.58, 0.20)
		_add_box_visual(Vector3(0.12, 0.55, 0.12), Color("704a2e"))
		PrimitiveFactory.box(self, "HammerHead", Vector3(0, -0.22, 0), Vector3(0.48, 0.18, 0.20), Color("555b5d"))
		prompt = "TAKE REPAIR HAMMER"
	elif cargo_kind == "welder":
		shape.size = Vector3(0.52, 0.46, 0.42)
		_add_box_visual(shape.size, Color("397f82"))
		PrimitiveFactory.box(self, "WelderGrip", Vector3(0, 0.31, 0), Vector3(0.16, 0.28, 0.16), Color("252b2c"))
		prompt = "TAKE WELDING TOOL"
	elif cargo_kind == "oil":
		shape.size = Vector3(0.34, 0.52, 0.28)
		_add_box_visual(shape.size, Color("b84e32"))
		PrimitiveFactory.box(self, "OilCap", Vector3(0, 0.31, 0), Vector3(0.14, 0.10, 0.14), Color("262a29"))
		prompt = "TAKE MOTOR OIL"
	elif cargo_kind == "drill":
		shape.size = Vector3(0.44, 0.38, 0.24)
		_add_box_visual(Vector3(0.42, 0.24, 0.22), Color("d1a13b"))
		PrimitiveFactory.box(self, "DrillGrip", Vector3(0, -0.22, 0), Vector3(0.16, 0.30, 0.18), Color("282d2d"))
		prompt = "TAKE POWER DRILL"
	elif cargo_kind == "spare_tire":
		shape.size = Vector3(0.34, 0.86, 0.86)
		var wheel := WHEEL_SCENE.instantiate() as Node3D
		wheel.name = "PhysicalSpareTire"
		wheel.rotation.z = PI * 0.5
		wheel.scale = Vector3.ONE * 1.05
		add_child(wheel)
		prompt = "CARRY SPARE TIRE"
	elif cargo_kind == "extinguisher":
		shape.size = Vector3(0.26, 0.66, 0.26)
		var bottle := MeshInstance3D.new()
		var bottle_mesh := CylinderMesh.new()
		bottle_mesh.top_radius = 0.12
		bottle_mesh.bottom_radius = 0.12
		bottle_mesh.height = 0.62
		bottle_mesh.radial_segments = 12
		bottle.mesh = bottle_mesh
		bottle.material_override = PrimitiveFactory.material(Color("c83f32"), 0.54, 0.18)
		add_child(bottle)
		PrimitiveFactory.box(self, "ExtinguisherHandle", Vector3(0, 0.38, 0), Vector3(0.20, 0.10, 0.10), Color("252929"))
		prompt = "TAKE FIRE EXTINGUISHER"
	else:
		shape.size = Vector3(0.42, 0.42, 0.42)
		_add_box_visual(shape.size, Color("8d8d83"))
		prompt = "CARRY ITEM"
	collision.shape = shape
	add_child(collision)

func _add_box_visual(size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = PrimitiveFactory.material(color, 0.78, 0.08)
	add_child(mesh_instance)

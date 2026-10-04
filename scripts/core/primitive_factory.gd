class_name PrimitiveFactory
extends RefCounted
## Lightweight original low-poly asset kit used by the mobile build.

static var _materials: Dictionary = {}

static func material(color: Color, roughness: float = 0.86, metallic: float = 0.0, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s" % [color.to_html(), roughness, metallic, emission.to_html()]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(emission.r, emission.g, emission.b)
		mat.emission_energy_multiplier = emission.a
	_materials[key] = mat
	return mat

static func box(parent: Node, object_name: String, position: Vector3, size: Vector3, color: Color, collision := false, rotation := Vector3.ZERO) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	if collision:
		var body := StaticBody3D.new()
		body.name = object_name
		body.position = position
		body.rotation = rotation
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material(color)
		body.add_child(visual)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		parent.add_child(body)
		return body
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = position
	instance.rotation = rotation
	parent.add_child(instance)
	return instance

static func cylinder(parent: Node, object_name: String, position: Vector3, radius: float, height: float, color: Color, collision := false, rotation := Vector3.ZERO, sides := 12) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	if collision:
		var body := StaticBody3D.new()
		body.name = object_name
		body.position = position
		body.rotation = rotation
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material(color)
		body.add_child(visual)
		var shape_node := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		shape_node.shape = shape
		body.add_child(shape_node)
		parent.add_child(body)
		return body
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = position
	instance.rotation = rotation
	parent.add_child(instance)
	return instance

static func sphere(parent: Node, object_name: String, position: Vector3, radius: float, color: Color, collision := false) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 7
	if collision:
		var body := StaticBody3D.new()
		body.name = object_name
		body.position = position
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material(color)
		body.add_child(visual)
		var shape_node := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		shape_node.shape = shape
		body.add_child(shape_node)
		parent.add_child(body)
		return body
	var instance := MeshInstance3D.new()
	instance.name = object_name
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = position
	parent.add_child(instance)
	return instance

static func label_3d(parent: Node, text: String, position: Vector3, color := Color("fff0cf"), size := 52) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = size
	label.pixel_size = 0.0034
	label.modulate = color
	label.outline_modulate = Color("171a25")
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

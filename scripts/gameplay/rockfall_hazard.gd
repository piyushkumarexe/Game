class_name RockfallHazard
extends Area3D
## One-shot network-authoritative rockfall at Last Light Pass.

var triggered := false
var rock_parent: Node3D

func setup(trigger_position: Vector3, parent: Node3D) -> void:
	position = trigger_position
	rock_parent = parent
	collision_layer = 0
	collision_mask = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(18, 10, 18)
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if triggered or body != GameSession.rv or (Net.is_online and not multiplayer.is_server()):
		return
	triggered = true
	GameSession.toast_requested.emit("ROCKFALL!", "Keep moving—do not stop below the ridge.")
	_spawn_rocks.rpc()

@rpc("authority", "call_local", "reliable")
func _spawn_rocks() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 7744
	for index in 9:
		var rock := RigidBody3D.new()
		rock.name = "FallingRock%d" % index
		rock.mass = 120.0 + index * 18.0
		rock.position = global_position + Vector3(random.randf_range(-9, 9), 12.0 + index * 1.7, random.randf_range(-9, 5))
		rock.rotation = Vector3(random.randf() * PI, random.randf() * PI, random.randf() * PI)
		rock.collision_layer = 8
		rock.collision_mask = 1 | 4
		var visual := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var radius := random.randf_range(0.65, 1.25)
		mesh.radius = radius
		mesh.height = radius * 1.7
		mesh.radial_segments = 9
		mesh.rings = 5
		visual.mesh = mesh
		visual.scale = Vector3(1.3, 0.9, 1.0)
		visual.material_override = PrimitiveFactory.material(Color("423b39"))
		rock.add_child(visual)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		collision.shape = shape
		rock.add_child(collision)
		rock_parent.add_child(rock)
		rock.apply_central_impulse(Vector3(random.randf_range(-4, 4), -4, random.randf_range(2, 8)) * rock.mass)
		get_tree().create_timer(18.0).timeout.connect(rock.queue_free)

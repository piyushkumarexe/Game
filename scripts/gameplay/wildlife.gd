class_name TrailWildlife
extends CharacterBody3D
## Original low-poly ridge boar hazard with host-authoritative AI.

var home := Vector3.ZERO
var target: Node3D
var wander_angle := 0.0
var attack_cooldown := 0.0
var peer_target := Transform3D.IDENTITY

func setup(spawn_position: Vector3) -> void:
	position = spawn_position
	home = spawn_position
	peer_target = transform
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	_build_visual()

func _physics_process(delta: float) -> void:
	if Net.is_online and not multiplayer.is_server():
		transform = transform.interpolate_with(peer_target, minf(1.0, delta * 10.0))
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_choose_target()
	var direction := Vector3.ZERO
	var speed := 1.4
	if target and global_position.distance_to(target.global_position) < 18.0:
		direction = global_position.direction_to(target.global_position)
		direction.y = 0.0
		speed = 5.8
	else:
		wander_angle += delta * 0.45
		var wander_target := home + Vector3(cos(wander_angle), 0.0, sin(wander_angle)) * 5.0
		direction = global_position.direction_to(wander_target)
		direction.y = 0.0
	velocity.x = direction.normalized().x * speed
	velocity.z = direction.normalized().z * speed
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	move_and_slide()
	if direction.length_squared() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), delta * 5.0)
	if target and global_position.distance_to(target.global_position) < 1.65 and attack_cooldown <= 0.0:
		attack_cooldown = 1.3
		if target.has_method("damage"):
			target.damage(7.0, "RIDGE BOAR")
		elif target is CharacterBody3D:
			target.velocity += global_position.direction_to(target.global_position) * 5.0 + Vector3.UP * 2.0
	if Net.is_online:
		_sync_wildlife.rpc(transform)

func _choose_target() -> void:
	var best_distance := 22.0
	target = null
	if GameSession.rv:
		var rv_distance := global_position.distance_to(GameSession.rv.global_position)
		if rv_distance < best_distance:
			best_distance = rv_distance
			target = GameSession.rv
	if Net.world:
		for player: Node in Net.world.players.values():
			var distance := global_position.distance_to(player.global_position)
			if distance < best_distance and not player.is_driving:
				best_distance = distance
				target = player

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync_wildlife(new_transform: Transform3D) -> void:
	peer_target = new_transform

func _build_visual() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.52
	shape.height = 1.25
	collision.shape = shape
	collision.position.y = 0.62
	add_child(collision)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.62
	body_mesh.height = 1.15
	body_mesh.radial_segments = 10
	body_mesh.rings = 6
	body.mesh = body_mesh
	body.scale = Vector3(0.88, 0.72, 1.35)
	body.position = Vector3(0, 0.7, 0)
	body.material_override = PrimitiveFactory.material(Color("46332d"))
	add_child(body)
	var head := PrimitiveFactory.sphere(self, "BoarHead", Vector3(0, 0.76, -0.72), 0.43, Color("4d3730"))
	head.scale = Vector3(0.85, 0.78, 1.0)
	PrimitiveFactory.cylinder(self, "TuskL", Vector3(-0.31, 0.65, -1.02), 0.045, 0.34, Color("e1d2ae"), false, Vector3(PI * 0.5, 0, 0), 7)
	PrimitiveFactory.cylinder(self, "TuskR", Vector3(0.31, 0.65, -1.02), 0.045, 0.34, Color("e1d2ae"), false, Vector3(PI * 0.5, 0, 0), 7)

class_name TrailInteractable
extends StaticBody3D
## Network-friendly world interaction: supplies, planks, repair bench and map props.

const CRATE_SCENE: PackedScene = preload("res://assets/third_party/kenney/platformer-kit/crate-strong.glb")

var kind := "supply"
var prompt := "TAKE SUPPLY CRATE"
var consumed := false
var amount := 1
var display_color := Color("b95a36")

func setup(interaction_kind: String, world_position: Vector3, custom_prompt := "") -> void:
	kind = interaction_kind
	position = world_position
	if not custom_prompt.is_empty():
		prompt = custom_prompt
	_match_appearance()
	_build_visual()

func interact(player: Node) -> void:
	if consumed:
		return
	if Net.is_online and not multiplayer.is_server():
		_request_interaction.rpc_id(1, multiplayer.get_unique_id())
	else:
		_apply_interaction(player)

@rpc("any_peer", "call_remote", "reliable")
func _request_interaction(peer_id: int) -> void:
	if not multiplayer.is_server() or not Net.world:
		return
	var player: Node = Net.world.get_player(peer_id)
	if player and global_position.distance_to(player.global_position) < 4.2:
		_apply_interaction(player)

func _apply_interaction(player: Node) -> void:
	match kind:
		"supply":
			GameSession.supplies_loaded += 1
			GameSession.toast_requested.emit("SUPPLY STOWED", "%d / 3 crates loaded" % GameSession.supplies_loaded)
			if GameSession.supplies_loaded >= 3:
				GameSession.complete_target("supplies")
			else:
				Net.broadcast_progress()
			_consume.rpc()
		"plank":
			if player.carried_item.is_empty():
				player.carried_item = "plank"
				player.update_carried_visual()
				GameSession.toast_requested.emit("PLANK CARRIED", "Take it to a yellow bridge socket.")
				_consume.rpc()
		"bridge_socket":
			if player.has_method("consume_carried_cargo") and player.consume_carried_cargo("plank"):
				GameSession.planks_placed += 1
				if Net.world:
					Net.world.place_bridge_plank(GameSession.planks_placed)
				GameSession.toast_requested.emit("PLANK SECURED", "%d / 2 bridge planks" % GameSession.planks_placed)
				if GameSession.planks_placed >= 2:
					GameSession.complete_target("bridge")
				else:
					Net.broadcast_progress()
				_consume.rpc()
			else:
				GameSession.toast_requested.emit("BRIDGE GAP", "Find a plank at the worksite.")
		"repair_body", "repair_frame", "repair_engine", "repair_tires":
			var component := kind.trim_prefix("repair_")
			if component == "tires" and GameSession.rv and GameSession.rv.has_missing_wheel():
				if player.has_method("has_carried_tool") and player.has_carried_tool("spare_tire"):
					if GameSession.rv.install_spare_tire():
						player.consume_carried_cargo("spare_tire")
						GameSession.complete_target("repair")
						GameSession.toast_requested.emit("SPARE INSTALLED", "Replacement wheel secured at 72% condition.")
				else:
					GameSession.toast_requested.emit("SPARE TIRE REQUIRED", "A wheel is missing. Carry a spare tire to this station.")
				return
			var required_tool := str({"body": "hammer", "frame": "welder", "engine": "oil", "tires": "drill"}.get(component, ""))
			if not player.has_method("has_carried_tool") or not player.has_carried_tool(required_tool):
				GameSession.toast_requested.emit("TOOL REQUIRED", "Bring the %s to this service point." % _tool_display_name(required_tool))
				return
			if GameSession.rv and GameSession.rv.repair_component(component, 38.0):
				# Oil is a consumable; durable hand tools remain physically carried.
				if required_tool == "oil":
					player.consume_carried_cargo("oil")
				GameSession.complete_target("repair")
				GameSession.toast_requested.emit("%s REPAIR" % component.to_upper(), "%s restored part of the system." % _tool_display_name(required_tool))
			else:
				GameSession.toast_requested.emit("NO REPAIR NEEDED", "%s is already serviceable." % component.capitalize())
		"fuel":
			if GameSession.rv:
				GameSession.rv.add_fuel(30.0)
				GameSession.toast_requested.emit("FUEL LOADED", "+30 L")
				_consume.rpc()

@rpc("authority", "call_local", "reliable")
func _consume() -> void:
	consumed = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_process(false)

func _tool_display_name(tool: String) -> String:
	return str({"hammer": "REPAIR HAMMER", "welder": "WELDING TOOL", "oil": "MOTOR OIL", "drill": "POWER DRILL"}.get(tool, "CORRECT TOOL"))

func _match_appearance() -> void:
	match kind:
		"supply":
			prompt = "LOAD SUPPLY CRATE"
			display_color = Color("a84f31")
		"plank":
			prompt = "CARRY PLANK"
			display_color = Color("8f6137")
		"bridge_socket":
			prompt = "PLACE PLANK"
			display_color = Color("f1a83b")
		"repair_body":
			prompt = "USE HAMMER — BODY"
			display_color = Color("65a879")
		"repair_frame":
			prompt = "USE WELDER — FRAME"
			display_color = Color("4f9f91")
		"repair_engine":
			prompt = "ADD MOTOR OIL — ENGINE"
			display_color = Color("b95a36")
		"repair_tires":
			prompt = "USE POWER DRILL — TIRES"
			display_color = Color("c7a34a")
		"fuel":
			prompt = "TAKE FUEL CAN"
			display_color = Color("c4482e")

func _build_visual() -> void:
	var visual: Node3D
	var shape_node := CollisionShape3D.new()
	if kind == "supply":
		visual = CRATE_SCENE.instantiate() as Node3D
		visual.name = "TexturedSupplyCrate"
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.92, 0.76, 0.78)
		shape_node.shape = shape
	elif kind == "plank" or kind == "bridge_socket":
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.8, 0.18, 0.48)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = PrimitiveFactory.material(display_color, 0.82, 0.05)
		visual = mesh_instance
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		shape_node.shape = shape
	else:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.85, 0.72, 0.72)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = PrimitiveFactory.material(display_color, 0.82, 0.05)
		visual = mesh_instance
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		shape_node.shape = shape
	add_child(visual)
	add_child(shape_node)
	if kind == "fuel":
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.91, 0.13, 0.76)
		band.mesh = band_mesh
		band.material_override = PrimitiveFactory.material(Color("e7d5ae"))
		add_child(band)

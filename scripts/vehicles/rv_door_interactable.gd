class_name RVEntryDoorInteractable
extends Area3D
## World-space interaction for the motorhome's animated passenger door.

var rv: Node
var prompt := "OPEN RV DOOR"

func setup(owner_rv: Node) -> void:
	rv = owner_rv
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
	var collision := CollisionShape3D.new()
	collision.name = "DoorInteractionShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.44, 1.78, 1.02)
	collision.shape = shape
	add_child(collision)
	refresh_prompt()

func refresh_prompt() -> void:
	prompt = "ENTER RV CABIN" if rv and rv.entry_door_open else "OPEN RV DOOR"

func interact(player: Node) -> void:
	if not rv:
		return
	if rv.driver_peer_id != 0 and not rv.freeze:
		GameSession.toast_requested.emit("DOOR LOCKED", "Stop and exit the driver seat before opening the coach door.")
		return
	if not rv.entry_door_open:
		rv.set_entry_door_open(true)
		GameSession.toast_requested.emit("RV DOOR OPEN", "Walk up all three steps, or tap USE again for entry assist.")
		return

	# Never close the door under a player who is trying to enter. The old action
	# did exactly that during mission one, making a visually open doorway feel
	# blocked. From outside, USE now assists onto the connected interior floor;
	# from inside, the same handle closes the door normally.
	var local_player_position: Vector3 = rv.global_transform.affine_inverse() * player.global_position
	if local_player_position.x > 1.24:
		rv.assist_cabin_entry(player)
	else:
		rv.set_entry_door_open(false)
		GameSession.toast_requested.emit("RV DOOR CLOSED", "The cabin remains accessible from the inside handle.")

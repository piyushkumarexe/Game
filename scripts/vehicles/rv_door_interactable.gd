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
	shape.size = Vector3(0.34, 1.74, 0.92)
	collision.shape = shape
	add_child(collision)
	refresh_prompt()

func refresh_prompt() -> void:
	prompt = "CLOSE RV DOOR" if rv and rv.entry_door_open else "OPEN RV DOOR"

func interact(_player: Node) -> void:
	if not rv:
		return
	if rv.driver_peer_id != 0 and not rv.freeze:
		GameSession.toast_requested.emit("DOOR LOCKED", "Stop and exit the driver seat before opening the coach door.")
		return
	rv.toggle_entry_door()
	GameSession.toast_requested.emit("RV DOOR OPEN" if rv.entry_door_open else "RV DOOR CLOSED",
		"The entry door now uses a real hinge pivot." if rv.entry_door_open else "Door secured for travel.")

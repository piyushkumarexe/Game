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
	prompt = "ENTER RV" if rv and rv.entry_door_open else "OPEN RV DOOR"

func interact(player: Node) -> void:
	if not rv:
		return
	if rv.driver_peer_id != 0 and not rv.freeze:
		GameSession.toast_requested.emit("DOOR LOCKED", "Stop and exit the driver seat before opening the coach door.")
		return
	if rv.entry_door_open:
		# The second interaction follows the same supply/driver-seat rules as the
		# main vehicle target; successful entry closes the door automatically.
		rv.interact(player)
		return
	rv.set_entry_door_open(true)
	GameSession.toast_requested.emit("RV DOOR OPEN", "The clear doorway leads into the modeled living cabin. Tap again to enter.")

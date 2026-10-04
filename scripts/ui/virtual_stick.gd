class_name VirtualStick
extends Control
## Multi-touch analog stick used for movement and camera look.

@export var look_stick := false
var pointer_id := -1
var value := Vector2.ZERO
var center := Vector2.ZERO
var radius := 76.0

func _ready() -> void:
	custom_minimum_size = Vector2(190, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP
	center = size * 0.5
	queue_redraw()

func _resized() -> void:
	center = size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and pointer_id < 0:
			pointer_id = event.index
			_update_value(event.position)
			accept_event()
		elif not event.pressed and event.index == pointer_id:
			pointer_id = -1
			value = Vector2.ZERO
			_push_value()
			queue_redraw()
			accept_event()
	elif event is InputEventScreenDrag and event.index == pointer_id:
		_update_value(event.position)
		accept_event()
	elif event is InputEventMouseButton:
		if event.pressed:
			pointer_id = 99
			_update_value(event.position)
		else:
			pointer_id = -1
			value = Vector2.ZERO
			_push_value()
			queue_redraw()
	elif event is InputEventMouseMotion and pointer_id == 99:
		_update_value(event.position)

func _update_value(local_position: Vector2) -> void:
	value = (local_position - center) / radius
	if value.length() > 1.0:
		value = value.normalized()
	if value.length() < 0.08:
		value = Vector2.ZERO
	_push_value()
	queue_redraw()

func _push_value() -> void:
	if look_stick:
		GameSession.add_touch_look(value * 9.0)
	else:
		GameSession.mobile_move = value

func _draw() -> void:
	draw_circle(center, radius + 13.0, Color(0.025, 0.035, 0.05, 0.48))
	draw_circle(center, radius, Color(0.95, 0.88, 0.72, 0.08))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.95, 0.78, 0.42, 0.36), 3.0)
	draw_circle(center + value * radius, 33.0, Color(0.93, 0.62, 0.23, 0.86))
	draw_circle(center + value * radius, 25.0, Color(1.0, 0.91, 0.73, 0.25))

class_name TouchLookArea
extends Control
## Drag-anywhere camera control for mobile. Unlike a virtual look joystick,
## relative swipes provide direct, familiar first/third-person camera aiming.

var pointer_id := -1
var hint_alpha := 0.72

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(self, "hint_alpha", 0.0, 1.0)
	tween.tween_callback(queue_redraw)

func _process(_delta: float) -> void:
	if hint_alpha > 0.0:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and pointer_id < 0:
			pointer_id = event.index
			accept_event()
		elif not event.pressed and event.index == pointer_id:
			pointer_id = -1
			accept_event()
	elif event is InputEventScreenDrag and event.index == pointer_id:
		GameSession.add_touch_look(event.relative)
		accept_event()
	elif event is InputEventMouseButton:
		pointer_id = 99 if event.pressed else -1
	elif event is InputEventMouseMotion and pointer_id == 99:
		GameSession.add_touch_look(event.relative)

func _draw() -> void:
	if hint_alpha <= 0.01:
		return
	var center := Vector2(size.x * 0.48, size.y * 0.58)
	var color := Color(1.0, 0.86, 0.62, hint_alpha * 0.38)
	draw_arc(center, 33.0, -1.0, 1.0, 24, color, 2.0)
	draw_line(center + Vector2(-34, 0), center + Vector2(34, 0), color, 2.0)

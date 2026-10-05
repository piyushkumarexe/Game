class_name TouchLookArea
extends Control
## Passive swipe hint. MobileInputRouter handles viewport-level touch events so
## camera look remains reliable during simultaneous movement and button input.

var hint_alpha := 0.72

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(self, "hint_alpha", 0.0, 1.0)
	tween.tween_callback(queue_redraw)

func _process(_delta: float) -> void:
	if hint_alpha > 0.0:
		queue_redraw()

func _draw() -> void:
	if hint_alpha <= 0.01:
		return
	var center := Vector2(size.x * 0.48, size.y * 0.58)
	var color := Color(1.0, 0.86, 0.62, hint_alpha * 0.38)
	draw_arc(center, 33.0, -1.0, 1.0, 24, color, 2.0)
	draw_line(center + Vector2(-34, 0), center + Vector2(34, 0), color, 2.0)

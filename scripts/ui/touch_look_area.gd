class_name TouchLookArea
extends Control
## Direct mobile free-look. Screen drags are observed at the viewport input
## level so Android GUI focus/capture cannot swallow camera motion. The left
## portion is reserved for the movement stick and taps still reach buttons.

const LOOK_ZONE_START := 0.30

var pointer_id := -1
var hint_alpha := 0.72

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	queue_redraw()
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(self, "hint_alpha", 0.0, 1.0)
	tween.tween_callback(queue_redraw)

func _process(_delta: float) -> void:
	if hint_alpha > 0.0:
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and pointer_id < 0 and _inside_look_zone(event.position):
			pointer_id = event.index
		elif not event.pressed and event.index == pointer_id:
			pointer_id = -1
	elif event is InputEventScreenDrag and event.index == pointer_id:
		# Do not mark the event handled: USE/VIEW/JUMP buttons must continue to
		# receive taps, while a genuine drag still controls the camera.
		GameSession.add_touch_look(event.relative.limit_length(150.0))

func _inside_look_zone(screen_position: Vector2) -> bool:
	var viewport_width := get_viewport_rect().size.x
	return viewport_width > 0.0 and screen_position.x >= viewport_width * LOOK_ZONE_START

func _draw() -> void:
	if hint_alpha <= 0.01:
		return
	var center := Vector2(size.x * 0.48, size.y * 0.58)
	var color := Color(1.0, 0.86, 0.62, hint_alpha * 0.38)
	draw_arc(center, 33.0, -1.0, 1.0, 24, color, 2.0)
	draw_line(center + Vector2(-34, 0), center + Vector2(34, 0), color, 2.0)

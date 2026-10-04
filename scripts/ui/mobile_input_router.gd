class_name MobileInputRouter
extends Node
## One viewport-level multi-touch router for every gameplay control. Android can
## skip Control._gui_input focus/capture during multi-touch, so movement, look
## and actions are resolved here before GUI dispatch and never depend on focus.

const LOOK_ZONE_START := 0.30
const MAX_LOOK_DELTA := 150.0

var move_stick: VirtualStick
var buttons: Array[Button] = []
var move_pointer := -1
var look_pointer := -1
var pointer_actions: Dictionary = {}

func setup(stick: VirtualStick, action_buttons: Array[Button]) -> void:
	move_stick = stick
	buttons = action_buttons
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_touch(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		_update_touch(event.index, event.position, _drag_delta(event))

func _begin_touch(pointer: int, screen_position: Vector2) -> void:
	var button := _button_at(screen_position)
	if button:
		var action := StringName(button.get_meta("input_action", ""))
		var hold_action := bool(button.get_meta("hold_action", false))
		pointer_actions[pointer] = {"action": action, "hold": hold_action, "button": button}
		button.modulate = Color(1.18, 1.08, 0.88, 1.0)
		if hold_action:
			GameSession.set_touch_action(action, true)
		else:
			GameSession.pulse_touch_action(action)
		return
	if move_pointer < 0 and _inside_move_zone(screen_position):
		move_pointer = pointer
		_update_move(screen_position)
		return
	if look_pointer < 0 and _inside_look_zone(screen_position):
		look_pointer = pointer

func _update_touch(pointer: int, screen_position: Vector2, relative: Vector2) -> void:
	if pointer == move_pointer:
		_update_move(screen_position)
	elif pointer == look_pointer:
		GameSession.add_touch_look(relative.limit_length(MAX_LOOK_DELTA))

func _end_touch(pointer: int) -> void:
	if pointer == move_pointer:
		move_pointer = -1
		GameSession.mobile_move = Vector2.ZERO
		if is_instance_valid(move_stick):
			move_stick.set_external_value(Vector2.ZERO)
	if pointer == look_pointer:
		look_pointer = -1
	if pointer_actions.has(pointer):
		var info: Dictionary = pointer_actions[pointer]
		var action: StringName = info["action"]
		if bool(info["hold"]):
			GameSession.set_touch_action(action, false)
		var button: Button = info["button"]
		if is_instance_valid(button):
			button.modulate = Color.WHITE
		pointer_actions.erase(pointer)

func _inside_move_zone(screen_position: Vector2) -> bool:
	if not is_instance_valid(move_stick) or not move_stick.is_visible_in_tree():
		return false
	return move_stick.get_global_rect().grow(28.0).has_point(screen_position)

func _inside_look_zone(screen_position: Vector2) -> bool:
	var width := get_viewport().get_visible_rect().size.x
	return width > 0.0 and screen_position.x >= width * LOOK_ZONE_START

func _button_at(screen_position: Vector2) -> Button:
	# Reverse iteration matches draw order if controls overlap.
	for index in range(buttons.size() - 1, -1, -1):
		var button := buttons[index]
		if (is_instance_valid(button)
				and button.is_visible_in_tree()
				and button.get_global_rect().grow(10.0).has_point(screen_position)):
			return button
	return null

func _update_move(screen_position: Vector2) -> void:
	if not is_instance_valid(move_stick):
		return
	var rect := move_stick.get_global_rect()
	var radius := minf(rect.size.x, rect.size.y) * 0.40
	var value := (screen_position - rect.get_center()) / maxf(radius, 1.0)
	if value.length() > 1.0:
		value = value.normalized()
	if value.length() < 0.08:
		value = Vector2.ZERO
	GameSession.mobile_move = value
	move_stick.set_external_value(value)

func _drag_delta(event: InputEventScreenDrag) -> Vector2:
	# screen_relative is stable under stretch/content scaling on Godot 4. On
	# platforms that do not populate it, relative remains a valid fallback.
	return event.screen_relative if not event.screen_relative.is_zero_approx() else event.relative

func clear_all() -> void:
	if move_pointer >= 0:
		_end_touch(move_pointer)
	if look_pointer >= 0:
		look_pointer = -1
	for pointer: int in pointer_actions.keys():
		_end_touch(pointer)
	GameSession.mobile_move = Vector2.ZERO
	GameSession.mobile_look_delta = Vector2.ZERO

func _exit_tree() -> void:
	clear_all()

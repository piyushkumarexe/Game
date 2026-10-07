class_name ControlLayoutEditor
extends CanvasLayer
## Touch-first control customizer. It deliberately handles pointer IDs at the
## viewport level, just like gameplay, so editing works even on Android devices
## whose GUI focus/capture is unreliable.

const ACTION_LABELS := {
	"move": "MOVE",
	"toggle_view": "VIEW",
	"interact": "USE",
	"jump": "JUMP",
	"sprint": "SPRINT",
	"winch_front": "FRONT\nWINCH",
	"winch_rear": "REAR\nWINCH",
	"voice": "RADIO",
	"shift_up": "GEAR +",
	"shift_down": "GEAR −",
	"handbrake": "BRAKE"
}
const ACTION_ORDER := ["move", "winch_rear", "winch_front", "voice", "sprint", "jump", "handbrake", "interact", "shift_down", "shift_up", "toggle_view"]

var cards: Dictionary = {}
var tools: Dictionary = {}
var drag_action := ""
var drag_pointer := -1
var drag_offset := Vector2.ZERO
var close_callback: Callable
var root: Control
var status_label: Label
var previous_tree_paused := false

func setup(callback := Callable()) -> void:
	close_callback = callback

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_tree_paused = get_tree().paused
	get_tree().paused = true
	_build_interface()
	set_process_input(true)

func _build_interface() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.035, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.offset_left = 12.0
	header.offset_top = 10.0
	header.offset_right = -12.0
	header.offset_bottom = 114.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", _style(Color(0.025, 0.04, 0.055, 0.96), Color(0.25, 0.70, 0.64, 0.65), 16))
	root.add_child(header)
	var header_content := Control.new()
	header_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_content)

	var title := Label.new()
	title.text = "CUSTOMIZE MOBILE CONTROLS"
	title.position = Vector2(18, 12)
	title.size = Vector2(360, 28)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("f5f2df"))
	header_content.add_child(title)
	status_label = Label.new()
	status_label.text = "Drag every control to a comfortable position. Changes are saved on this device."
	status_label.position = Vector2(18, 45)
	status_label.size = Vector2(420, 44)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("bfc9c2"))
	header_content.add_child(status_label)

	var tool_specs := [
		["size_down", "SIZE −"], ["size_up", "SIZE +"], ["opacity", "ALPHA"],
		["look", "LOOK"], ["quality", "QUALITY"], ["reset", "RESET"], ["save", "SAVE & CLOSE"]
	]
	var x := 450.0
	for spec: Array in tool_specs:
		var key: String = spec[0]
		var button := Button.new()
		button.name = "LayoutTool_%s" % key
		button.text = spec[1]
		button.position = Vector2(x, 28.0)
		button.size = Vector2(102.0 if key != "save" else 132.0, 52.0)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", Color("fff4df"))
		button.add_theme_stylebox_override("normal", _style(Color(0.08, 0.12, 0.14, 0.95), Color(0.94, 0.65, 0.26, 0.65), 12))
		header_content.add_child(button)
		tools[key] = button
		x += button.size.x + 8.0

	for action: String in ACTION_ORDER:
		var card := PanelContainer.new()
		card.name = "Layout_%s" % action
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var driving := action.begins_with("winch") or action.begins_with("shift") or action == "handbrake"
		var color := Color(0.10, 0.30, 0.32, 0.92) if driving else Color(0.34, 0.18, 0.08, 0.92)
		card.add_theme_stylebox_override("panel", _style(color, Color(0.95, 0.72, 0.34, 0.86), 24))
		var label := Label.new()
		label.text = ACTION_LABELS[action]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("fff5df"))
		card.add_child(label)
		root.add_child(card)
		cards[action] = card

	root.resized.connect(_layout_cards)
	_layout_cards()
	_refresh_tool_text()

func _layout_cards() -> void:
	if not root:
		return
	var viewport_size := root.size
	for action: String in ACTION_ORDER:
		var card: Control = cards[action]
		var base_size := Vector2(154.0, 154.0) if action == "move" else Vector2(88.0, 70.0)
		card.size = base_size * GameSession.control_scale
		card.position = GameSession.control_position(action) * viewport_size - card.size * 0.5
		card.modulate.a = GameSession.control_opacity

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_save_and_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointer_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == drag_pointer:
		_pointer_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down(0, event.position)
		else:
			_pointer_up(0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_pointer == 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pointer_drag(event.position)
		get_viewport().set_input_as_handled()

func _pointer_down(pointer: int, position: Vector2) -> void:
	if drag_pointer >= 0:
		return
	for key: String in tools:
		var tool: Control = tools[key]
		if tool.get_global_rect().has_point(position):
			_activate_tool(key)
			return
	for index in range(ACTION_ORDER.size() - 1, -1, -1):
		var action: String = ACTION_ORDER[index]
		var card: Control = cards[action]
		if card.get_global_rect().grow(10.0).has_point(position):
			drag_pointer = pointer
			drag_action = action
			drag_offset = position - card.get_global_rect().get_center()
			card.modulate = Color(1.20, 1.08, 0.86, GameSession.control_opacity)
			return

func _pointer_drag(position: Vector2) -> void:
	if drag_action.is_empty() or root.size.x <= 0.0 or root.size.y <= 0.0:
		return
	var normalized := (position - drag_offset) / root.size
	GameSession.set_control_position(drag_action, normalized)
	_layout_cards()
	var card: Control = cards[drag_action]
	card.modulate = Color(1.20, 1.08, 0.86, GameSession.control_opacity)

func _pointer_up(pointer: int) -> void:
	if pointer != drag_pointer:
		return
	if not drag_action.is_empty() and cards.has(drag_action):
		(cards[drag_action] as Control).modulate = Color(1, 1, 1, GameSession.control_opacity)
	drag_pointer = -1
	drag_action = ""

func _activate_tool(key: String) -> void:
	match key:
		"size_down":
			GameSession.control_scale = clampf(GameSession.control_scale - 0.08, 0.72, 1.35)
		"size_up":
			GameSession.control_scale = clampf(GameSession.control_scale + 0.08, 0.72, 1.35)
		"opacity":
			GameSession.control_opacity += 0.18
			if GameSession.control_opacity > 1.01:
				GameSession.control_opacity = 0.46
		"look":
			GameSession.touch_look_speed += 0.25
			if GameSession.touch_look_speed > 1.66:
				GameSession.touch_look_speed = 0.65
		"quality":
			GameSession.graphics_quality = (GameSession.graphics_quality + 1) % 3
			GameSession.reduced_graphics = GameSession.graphics_quality == 0
		"reset":
			GameSession.reset_control_layout()
		"save":
			_save_and_close()
	_layout_cards()
	_refresh_tool_text()

func _refresh_tool_text() -> void:
	if tools.is_empty():
		return
	(tools["opacity"] as Button).text = "ALPHA\n%d%%" % roundi(GameSession.control_opacity * 100.0)
	(tools["look"] as Button).text = "LOOK\n%d%%" % roundi(GameSession.touch_look_speed * 100.0)
	(tools["quality"] as Button).text = "QUALITY\n%s" % ["FAST", "BALANCED", "HIGH"][GameSession.graphics_quality]

func _save_and_close() -> void:
	if is_queued_for_deletion():
		return
	GameSession.save_settings()
	set_process_input(false)
	get_tree().paused = previous_tree_paused
	if close_callback.is_valid():
		close_callback.call()
	queue_free()

func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = previous_tree_paused

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

class_name ExpeditionHUD
extends CanvasLayer
## Mission, vehicle and mobile co-op HUD.

const TouchLookAreaScript = preload("res://scripts/ui/touch_look_area.gd")
const MobileInputRouterScript = preload("res://scripts/ui/mobile_input_router.gd")
const ControlLayoutEditorScript = preload("res://scripts/ui/control_layout_editor.gd")

var mission_title: Label
var mission_detail: Label
var mission_count: Label
var health_bar: ProgressBar
var fuel_bar: ProgressBar
var speed_label: Label
var gear_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var toast_panel: PanelContainer
var toast_title: Label
var toast_detail: Label
var crew_label: Label
var toast_tween: Tween
var touch_root: Control
var input_router: MobileInputRouter
var settings_editor: ControlLayoutEditor

func _ready() -> void:
	layer = 20
	_build_hud()
	GameSession.mission_changed.connect(_on_mission_changed)
	GameSession.toast_requested.connect(_show_toast)
	GameSession.checkpoint_reached.connect(_on_checkpoint)
	Net.peer_roster_changed.connect(_update_roster)
	if GameSession.mission_index < GameSession.MISSIONS.size():
		var mission: Dictionary = GameSession.MISSIONS[GameSession.mission_index]
		_on_mission_changed(str(mission["title"]), str(mission["detail"]), GameSession.mission_index + 1, GameSession.MISSIONS.size())
	await get_tree().process_frame
	if GameSession.rv:
		GameSession.rv.stats_changed.connect(_update_rv_stats)
	_update_roster(Net.roster)

func _process(_delta: float) -> void:
	var has_player := GameSession.local_player and is_instance_valid(GameSession.local_player)
	var driving := false
	if has_player:
		var text: String = GameSession.local_player.interaction_text
		prompt_panel.visible = not text.is_empty()
		prompt_label.text = "TAP USE  •  %s" % text
		driving = GameSession.local_player.is_driving
	else:
		prompt_panel.visible = false
	if touch_root:
		for node: Node in touch_root.get_children():
			if node.has_meta("driving_only"):
				node.visible = driving
			elif node.has_meta("walking_only"):
				node.visible = not driving
	if GameSession.consume_touch_press("control_settings") and not is_instance_valid(settings_editor):
		_open_control_editor()

func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var objective := PanelContainer.new()
	objective.anchor_left = 0.0
	objective.anchor_top = 0.0
	objective.anchor_right = 0.0
	objective.anchor_bottom = 0.0
	objective.offset_left = 20.0
	objective.offset_top = 18.0
	objective.offset_right = 470.0
	objective.offset_bottom = 118.0
	objective.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.06, 0.86), Color("d89138"), 16))
	root.add_child(objective)
	var objective_margin := MarginContainer.new()
	objective_margin.add_theme_constant_override("margin_left", 20)
	objective_margin.add_theme_constant_override("margin_right", 20)
	objective_margin.add_theme_constant_override("margin_top", 12)
	objective_margin.add_theme_constant_override("margin_bottom", 11)
	objective.add_child(objective_margin)
	var objective_box := VBoxContainer.new()
	objective_margin.add_child(objective_box)
	var objective_head := HBoxContainer.new()
	objective_box.add_child(objective_head)
	mission_count = _label("LEG 1 / 8", 14, Color("e3a54c"), true)
	objective_head.add_child(mission_count)
	mission_title = _label("PACK FOR THE DETOUR", 23, Color("fff2d5"), true)
	objective_box.add_child(mission_title)
	mission_detail = _label("Load the supplies.", 14, Color("c7c3b8"))
	objective_box.add_child(mission_detail)

	var rig_panel := PanelContainer.new()
	rig_panel.anchor_left = 0.5
	rig_panel.anchor_top = 0.0
	rig_panel.anchor_right = 0.5
	rig_panel.anchor_bottom = 0.0
	rig_panel.offset_left = -190.0
	rig_panel.offset_top = 18.0
	rig_panel.offset_right = 190.0
	rig_panel.offset_bottom = 104.0
	rig_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.06, 0.86), Color(1, 1, 1, 0.08), 16))
	root.add_child(rig_panel)
	var rig_margin := MarginContainer.new()
	for side in ["left", "right"]:
		rig_margin.add_theme_constant_override("margin_" + side, 17)
	rig_margin.add_theme_constant_override("margin_top", 11)
	rig_margin.add_theme_constant_override("margin_bottom", 8)
	rig_panel.add_child(rig_margin)
	var rig_row := HBoxContainer.new()
	rig_row.add_theme_constant_override("separation", 15)
	rig_margin.add_child(rig_row)
	var bars := VBoxContainer.new()
	bars.custom_minimum_size.x = 245
	rig_row.add_child(bars)
	health_bar = _status_bar("RIG", Color("65b87f"))
	fuel_bar = _status_bar("FUEL", Color("e2a03b"))
	bars.add_child(health_bar)
	bars.add_child(fuel_bar)
	var drive_stats := VBoxContainer.new()
	rig_row.add_child(drive_stats)
	speed_label = _label("0 KM/H", 18, Color("fff2d5"), true)
	gear_label = _label("GEAR 1", 16, Color("e2a03b"), true)
	drive_stats.add_child(speed_label)
	drive_stats.add_child(gear_label)

	crew_label = _label("SOLO RUN", 14, Color("d7d2c2"), true)
	crew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crew_label.anchor_left = 1.0
	crew_label.anchor_top = 0.0
	crew_label.anchor_right = 1.0
	crew_label.anchor_bottom = 0.0
	crew_label.offset_left = -320.0
	crew_label.offset_top = 27.0
	crew_label.offset_right = -20.0
	crew_label.offset_bottom = 88.0
	root.add_child(crew_label)

	prompt_panel = PanelContainer.new()
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_left = -205.0
	prompt_panel.offset_top = -96.0
	prompt_panel.offset_right = 205.0
	prompt_panel.offset_bottom = -42.0
	prompt_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.06, 0.92), Color("e2a03b"), 18))
	root.add_child(prompt_panel)
	prompt_label = _label("INTERACT", 17, Color("fff2d5"), true)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false

	toast_panel = PanelContainer.new()
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_top = 0.0
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_bottom = 0.0
	toast_panel.offset_left = -220.0
	toast_panel.offset_top = 142.0
	toast_panel.offset_right = 220.0
	toast_panel.offset_bottom = 225.0
	toast_panel.modulate.a = 0.0
	toast_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.055, 0.07, 0.94), Color("d89138"), 18))
	root.add_child(toast_panel)
	var toast_box := VBoxContainer.new()
	toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_panel.add_child(toast_box)
	toast_title = _label("MISSION UPDATED", 20, Color("fff1d2"), true)
	toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_detail = _label("Keep rolling.", 13, Color("c9c4b8"))
	toast_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_box.add_child(toast_title)
	toast_box.add_child(toast_detail)

	var reticle := Label.new()
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.anchor_left = 0.5
	reticle.anchor_top = 0.5
	reticle.anchor_right = 0.5
	reticle.anchor_bottom = 0.5
	reticle.offset_left = -13.0
	reticle.offset_top = -13.0
	reticle.offset_right = 13.0
	reticle.offset_bottom = 13.0
	reticle.add_theme_font_size_override("font_size", 21)
	reticle.add_theme_color_override("font_color", Color(1.0, 0.91, 0.74, 0.76))
	root.add_child(reticle)

	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--smoke-expedition" in OS.get_cmdline_user_args():
		_build_touch_controls(root)

func _build_touch_controls(root: Control) -> void:
	touch_root = Control.new()
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_root)
	var move_stick := VirtualStick.new()
	move_stick.name = "MoveStick"
	move_stick.anchor_left = 0.0
	move_stick.anchor_top = 1.0
	move_stick.anchor_right = 0.0
	move_stick.anchor_bottom = 1.0
	move_stick.offset_left = 18.0
	move_stick.offset_top = -198.0
	move_stick.offset_right = 198.0
	move_stick.offset_bottom = -18.0
	touch_root.add_child(move_stick)
	var look_area := TouchLookAreaScript.new()
	look_area.name = "SwipeLookArea"
	look_area.anchor_left = 0.30
	look_area.anchor_top = 0.18
	look_area.anchor_right = 1.0
	look_area.anchor_bottom = 1.0
	touch_root.add_child(look_area)
	var action_buttons: Array[Button] = []
	var view := _make_touch_button("VIEW\n1P / 3P", "toggle_view", Vector2(-112, -368), false)
	action_buttons.append(view)
	var use := _make_touch_button("USE", "interact", Vector2(-112, -190), false)
	action_buttons.append(use)
	var jump := _make_touch_button("JUMP", "jump", Vector2(-102, -100), false)
	jump.set_meta("walking_only", true)
	action_buttons.append(jump)
	var sprint := _make_touch_button("SPRINT", "sprint", Vector2(-205, -94), true)
	sprint.set_meta("walking_only", true)
	action_buttons.append(sprint)
	var front := _make_touch_button("FRONT\nWINCH", "winch_front", Vector2(-302, -95), false)
	front.set_meta("driving_only", true)
	front.visible = false
	action_buttons.append(front)
	var rear := _make_touch_button("REAR\nWINCH", "winch_rear", Vector2(-400, -95), false)
	rear.set_meta("driving_only", true)
	rear.visible = false
	action_buttons.append(rear)
	var up := _make_touch_button("GEAR +", "shift_up", Vector2(-105, -285), false)
	up.set_meta("driving_only", true)
	up.visible = false
	action_buttons.append(up)
	var down := _make_touch_button("GEAR −", "shift_down", Vector2(-205, -285), false)
	down.set_meta("driving_only", true)
	down.visible = false
	action_buttons.append(down)
	var handbrake := _make_touch_button("BRAKE", "handbrake", Vector2(-205, -190), true)
	handbrake.set_meta("driving_only", true)
	handbrake.visible = false
	action_buttons.append(handbrake)
	var settings := _make_touch_button("LAYOUT", "control_settings", Vector2(-103, -590), false)
	settings.anchor_top = 0.0
	settings.anchor_bottom = 0.0
	settings.offset_left = -98.0
	settings.offset_top = 104.0
	settings.offset_right = -18.0
	settings.offset_bottom = 150.0
	settings.add_theme_font_size_override("font_size", 11)
	settings.set_meta("fixed_control", true)
	action_buttons.append(settings)
	_apply_control_layout()
	input_router = MobileInputRouterScript.new()
	input_router.name = "MobileInputRouter"
	add_child(input_router)
	input_router.setup(move_stick, action_buttons)

func _apply_control_layout() -> void:
	if not touch_root:
		return
	var move_stick := touch_root.find_child("MoveStick", true, false) as Control
	if move_stick:
		_place_custom_control(move_stick, "move", Vector2(180.0, 180.0))
	for action: String in GameSession.DEFAULT_CONTROL_LAYOUT:
		if action == "move":
			continue
		var button := touch_root.find_child("Touch_%s" % action, true, false) as Button
		if button:
			_place_custom_control(button, action, Vector2(88.0, 70.0))
			var base_modulate := Color(1, 1, 1, GameSession.control_opacity)
			button.set_meta("base_modulate", base_modulate)
			button.modulate = base_modulate

func _place_custom_control(control: Control, action: String, base_size: Vector2) -> void:
	var anchor := GameSession.control_position(action)
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	var scaled_size := base_size * GameSession.control_scale
	control.offset_left = -scaled_size.x * 0.5
	control.offset_right = scaled_size.x * 0.5
	control.offset_top = -scaled_size.y * 0.5
	control.offset_bottom = scaled_size.y * 0.5
	control.modulate.a = GameSession.control_opacity

func _open_control_editor() -> void:
	if is_instance_valid(settings_editor):
		return
	if input_router:
		input_router.clear_all()
		input_router.set_process_input(false)
	settings_editor = ControlLayoutEditorScript.new()
	settings_editor.setup(_close_control_editor)
	get_tree().root.add_child(settings_editor)

func _close_control_editor() -> void:
	_apply_control_layout()
	if input_router:
		input_router.set_process_input(true)
	settings_editor = null

func _make_touch_button(text: String, action: StringName, bottom_right_offset: Vector2, hold: bool) -> Button:
	var button := Button.new()
	button.name = "Touch_%s" % action
	button.text = text
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = bottom_right_offset.x
	button.offset_top = bottom_right_offset.y
	button.offset_right = bottom_right_offset.x + 88.0
	button.offset_bottom = bottom_right_offset.y + 70.0
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.set_meta("input_action", action)
	button.set_meta("hold_action", hold)
	button.set_meta("base_modulate", Color(1, 1, 1, GameSession.control_opacity))
	button.modulate = button.get_meta("base_modulate")
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("fff2d5"))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.055, 0.07, 0.58), Color(0.94, 0.67, 0.28, 0.55), 24))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.85, 0.45, 0.16, 0.9), Color("ffe4ad"), 24))
	touch_root.add_child(button)
	return button

func _on_mission_changed(title: String, detail: String, index: int, total: int) -> void:
	mission_title.text = title
	mission_detail.text = detail
	mission_count.text = "LEG %d / %d" % [index, total]

func _update_rv_stats(health: float, fuel: float, gear: int, speed: float) -> void:
	health_bar.value = health
	fuel_bar.value = fuel
	speed_label.text = "%d KM/H" % roundi(speed)
	gear_label.text = "REVERSE" if gear == 0 else ("NEUTRAL" if gear == 1 else "GEAR %d" % (gear - 1))

func _show_toast(title: String, detail: String) -> void:
	toast_title.text = title
	toast_detail.text = detail
	if toast_tween:
		toast_tween.kill()
	toast_panel.modulate.a = 0.0
	toast_panel.position.y = 138
	toast_tween = create_tween()
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.18)
	toast_tween.parallel().tween_property(toast_panel, "position:y", 152.0, 0.24).set_trans(Tween.TRANS_BACK)
	toast_tween.tween_interval(2.45)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.28)

func _on_checkpoint(_index: int, title: String) -> void:
	_show_toast("CHECKPOINT SECURED", title)

func _update_roster(_roster: Dictionary) -> void:
	crew_label.text = "SINGLE PLAYER\n%s" % GameSession.player_name

func _status_bar(title: String, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(245, 25)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _panel_style(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 5))
	bar.add_theme_stylebox_override("fill", _panel_style(color, Color.TRANSPARENT, 5))
	var label := _label(title, 11, Color("fff2d5"), true)
	label.position = Vector2(8, 3)
	bar.add_child(label)
	return bar

func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.8))
	return label

func _panel_style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2 if border.a > 0.0 else 0)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

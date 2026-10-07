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
var trip_bar: ProgressBar
var trip_label: Label
var session_chip: Label
var mic_chip: Button
var deafen_chip: Button
var roster_refresh_left := 0.0
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
	Net.crew_spoken.connect(func(_peer: int) -> void: _update_roster(Net.roster))
	if GameSession.mission_index < GameSession.MISSIONS.size():
		var mission: Dictionary = GameSession.MISSIONS[GameSession.mission_index]
		_on_mission_changed(str(mission["title"]), str(mission["detail"]), GameSession.mission_index + 1, GameSession.MISSIONS.size())
	await get_tree().process_frame
	if GameSession.rv:
		GameSession.rv.stats_changed.connect(_update_rv_stats)
	_update_roster(Net.roster)

func _process(delta: float) -> void:
	_update_trip(delta)
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
	if Input.is_action_just_pressed("toggle_voice") or GameSession.consume_touch_press("toggle_voice"):
		_toggle_deafen()
	if is_instance_valid(mic_chip):
		mic_chip.visible = Net.is_online
		deafen_chip.visible = Net.is_online

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
	# "Are we there yet?" is the whole joke of a road trip, so the leg progress
	# bar lives in the objective card where a passenger reads it, not in a corner.
	var trip_row := HBoxContainer.new()
	trip_row.add_theme_constant_override("separation", 9)
	objective_box.add_child(trip_row)
	trip_bar = ProgressBar.new()
	trip_bar.max_value = 100.0
	trip_bar.value = 0.0
	trip_bar.show_percentage = false
	trip_bar.custom_minimum_size = Vector2(150.0, 13)
	trip_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trip_bar.add_theme_stylebox_override("background", _panel_style(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 5))
	trip_bar.add_theme_stylebox_override("fill", _panel_style(Color("d89138"), Color.TRANSPARENT, 5))
	trip_row.add_child(trip_bar)
	trip_label = _label("REDMESA → ROUTE 17", 11, Color("bcb9ae"), true)
	trip_row.add_child(trip_label)

	var rig_panel := PanelContainer.new()
	rig_panel.anchor_left = 0.5
	rig_panel.anchor_top = 0.0
	rig_panel.anchor_right = 0.5
	rig_panel.anchor_bottom = 0.0
	rig_panel.offset_left = -238.0
	rig_panel.offset_top = 18.0
	rig_panel.offset_right = 238.0
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
	var radio_column := VBoxContainer.new()
	radio_column.add_theme_constant_override("separation", 4)
	rig_row.add_child(radio_column)
	mic_chip = _chip_button("PUSH TALK", _toggle_voice_mode)
	deafen_chip = _chip_button("RADIO ON", _toggle_deafen)
	radio_column.add_child(mic_chip)
	radio_column.add_child(deafen_chip)

	crew_label = _label("SOLO RUN", 14, Color("d7d2c2"), true)
	crew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crew_label.anchor_left = 1.0
	crew_label.anchor_top = 0.0
	crew_label.anchor_right = 1.0
	crew_label.anchor_bottom = 0.0
	crew_label.offset_left = -330.0
	crew_label.offset_top = 30.0
	crew_label.offset_right = -112.0
	crew_label.offset_bottom = 136.0
	root.add_child(crew_label)

	session_chip = _label("SOLO", 11, Color("9fe8cf"), true)
	session_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	session_chip.anchor_left = 1.0
	session_chip.anchor_top = 0.0
	session_chip.anchor_right = 1.0
	session_chip.anchor_bottom = 0.0
	session_chip.offset_left = -320.0
	session_chip.offset_top = 9.0
	session_chip.offset_right = -20.0
	session_chip.offset_bottom = 26.0
	root.add_child(session_chip)

	# Radio state is one tap on a phone and one key on a keyboard, and it has to be
	# readable at a glance: nobody can tell a muted buddy from a good one at
	# forty metres of mud. The chips live in the centre rig card for that reason.

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
	var radio := _make_touch_button("RADIO", "voice", Vector2(-498, -95), true)
	radio.add_theme_font_size_override("font_size", 12)
	action_buttons.append(radio)
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

func _update_trip(delta: float) -> void:
	roster_refresh_left = maxf(0.0, roster_refresh_left - delta)
	if not GameSession.rv or not is_instance_valid(GameSession.rv):
		return
	var position: Vector3 = GameSession.rv.global_position
	var progress := 0.0
	var remaining := 0.0
	if Net.world and is_instance_valid(Net.world):
		progress = float(Net.world.call("trip_progress", position))
		remaining = float(Net.world.call("distance_to_finish", position))
	trip_bar.value = progress * 100.0
	trip_label.text = "%d M TO ROUTE 17" % roundi(remaining) if remaining > 4.0 else "AT THE EXIT"
	if roster_refresh_left > 0.0:
		return
	roster_refresh_left = 0.4
	_update_roster(Net.roster)


func _update_roster(roster: Dictionary) -> void:
	var driving := int(GameSession.rv.driver_peer_id) if GameSession.rv and is_instance_valid(GameSession.rv) else 0
	if not Net.is_online:
		crew_label.text = "SOLO RUN\n%s · %s" % [GameSession.player_name, GameSession.role_label(GameSession.selected_role)]
		session_chip.text = "OFFLINE"
		return
	var lines: Array[String] = Net.roster_lines(driving)
	crew_label.text = "CREW %d / %d\n%s" % [roster.size(), Net.MAX_PLAYERS, "\n".join(lines)]
	var speaking := ""
	var local_player: Node = GameSession.local_player
	var voice_node: Node = local_player.get("voice") if local_player else null
	if voice_node and bool(voice_node.call("is_speaking")):
		speaking = " · TALKING"
	session_chip.text = "%d CREW · %s%s" % [roster.size(), Net.transport_name().to_upper(), speaking]


func _chip_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(104.0, 25.0)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("fff2d5"))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.055, 0.07, 0.8), Color(0.62, 0.86, 0.78, 0.4), 14))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.07, 0.09, 0.11, 0.9), Color(0.62, 0.86, 0.78, 0.75), 14))
	button.pressed.connect(handler)
	return button


func _toggle_voice_mode() -> void:
	GameSession.voice_mode = GameSession.VoiceMode.OPEN_MIC if GameSession.voice_mode == GameSession.VoiceMode.PUSH_TO_TALK else GameSession.VoiceMode.PUSH_TO_TALK
	GameSession.save_settings()
	mic_chip.text = "OPEN MIC" if GameSession.voice_mode == GameSession.VoiceMode.OPEN_MIC else "PUSH TALK"


func _toggle_deafen() -> void:
	GameSession.toggle_mute()
	deafen_chip.text = "RADIO MUTED" if GameSession.voice_deafened else "RADIO ON"

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

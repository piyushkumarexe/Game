class_name ExpeditionHUD
extends CanvasLayer
## Mission, vehicle and mobile co-op HUD.

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
	if GameSession.local_player and is_instance_valid(GameSession.local_player):
		var text: String = GameSession.local_player.interaction_text
		prompt_panel.visible = not text.is_empty()
		prompt_label.text = "  TAP • %s  " % text
		if touch_root:
			var driving: bool = GameSession.local_player.is_driving
			for node: Node in touch_root.get_children():
				if node.has_meta("driving_only"):
					node.visible = driving

func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var objective := PanelContainer.new()
	objective.position = Vector2(28, 24)
	objective.size = Vector2(470, 105)
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
	rig_panel.position = Vector2(518, 24)
	rig_panel.size = Vector2(395, 88)
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
	crew_label.position = Vector2(935, 33)
	crew_label.size = Vector2(310, 60)
	root.add_child(crew_label)

	prompt_panel = PanelContainer.new()
	prompt_panel.position = Vector2(448, 598)
	prompt_panel.size = Vector2(384, 54)
	prompt_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.06, 0.92), Color("e2a03b"), 18))
	root.add_child(prompt_panel)
	prompt_label = _label("INTERACT", 17, Color("fff2d5"), true)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false

	toast_panel = PanelContainer.new()
	toast_panel.position = Vector2(420, 152)
	toast_panel.size = Vector2(440, 83)
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

	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		_build_touch_controls(root)

func _build_touch_controls(root: Control) -> void:
	touch_root = Control.new()
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_root)
	var move_stick := VirtualStick.new()
	move_stick.position = Vector2(28, 490)
	move_stick.size = Vector2(190, 190)
	touch_root.add_child(move_stick)
	var look_stick := VirtualStick.new()
	look_stick.look_stick = true
	look_stick.position = Vector2(835, 500)
	look_stick.size = Vector2(180, 180)
	touch_root.add_child(look_stick)
	_make_touch_button("USE", "interact", Vector2(1110, 430), false)
	_make_touch_button("JUMP", "jump", Vector2(1182, 548), false)
	_make_touch_button("SPRINT", "sprint", Vector2(1055, 585), true)
	var front := _make_touch_button("FRONT\nCABLE", "winch_front", Vector2(710, 570), false)
	front.set_meta("driving_only", true)
	var rear := _make_touch_button("REAR\nCABLE", "winch_rear", Vector2(620, 596), false)
	rear.set_meta("driving_only", true)
	var up := _make_touch_button("GEAR +", "shift_up", Vector2(1130, 300), false)
	up.set_meta("driving_only", true)
	var down := _make_touch_button("GEAR −", "shift_down", Vector2(1025, 320), false)
	down.set_meta("driving_only", true)

func _make_touch_button(text: String, action: StringName, position: Vector2, hold: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = Vector2(92, 76)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("fff2d5"))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.05, 0.06, 0.08, 0.65), Color(0.94, 0.67, 0.28, 0.5), 28))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.85, 0.45, 0.16, 0.9), Color("ffe4ad"), 28))
	if hold:
		button.button_down.connect(GameSession.set_touch_action.bind(action, true))
		button.button_up.connect(GameSession.set_touch_action.bind(action, false))
	else:
		button.button_down.connect(GameSession.pulse_touch_action.bind(action))
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

func _update_roster(roster: Dictionary) -> void:
	if roster.is_empty():
		crew_label.text = "SOLO EXPEDITION"
		return
	var names: Array[String] = []
	for id: int in roster:
		names.append(str(roster[id]["name"]))
	crew_label.text = "CREW %d/4\n%s" % [roster.size(), "  •  ".join(names)]

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

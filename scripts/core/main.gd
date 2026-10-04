extends Node
## Application shell: cinematic menu, network lobby and expedition lifecycle.

const WorldScript = preload("res://scripts/world/expedition_world.gd")
const HUDScript = preload("res://scripts/ui/expedition_hud.gd")
const MenuDioramaScript = preload("res://scripts/ui/menu_diorama.gd")

var menu_layer: CanvasLayer
var name_input: LineEdit
var address_input: LineEdit
var role_picker: OptionButton
var status_label: Label
var active_world: ExpeditionWorld
var active_hud: ExpeditionHUD
var menu_world: MenuDiorama

func _ready() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	Net.joined_server.connect(_on_joined_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	GameSession.run_finished.connect(_show_results)
	if "--smoke-expedition" in OS.get_cmdline_user_args():
		_run_expedition_smoke_test()
	else:
		_show_main_menu()

func _show_main_menu() -> void:
	_clear_game()
	GameSession.mode = GameSession.Mode.MENU
	if menu_world and is_instance_valid(menu_world):
		menu_world.queue_free()
	menu_world = MenuDioramaScript.new()
	add_child(menu_world)

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 50
	add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(root)

	var cinematic_shade := ColorRect.new()
	cinematic_shade.color = Color(0.015, 0.022, 0.032, 0.24)
	cinematic_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cinematic_shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.025
	panel.anchor_top = 0.035
	panel.anchor_right = 0.43
	panel.anchor_bottom = 0.965
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.032, 0.045, 0.93), Color(0.93, 0.62, 0.25, 0.34), 18))
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := _label("DUSTBOUND", 49, Color("fff0d1"), true)
	content.add_child(title)
	var subtitle := _label("E X P E D I T I O N S", 17, Color("eea23b"), true)
	content.add_child(subtitle)
	var pitch := _label("ONE RIG. FOUR CREWMATES. A VERY BAD ROAD HOME.", 13, Color("d7d2c4"), true)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(pitch)
	var separator := HSeparator.new()
	separator.modulate = Color(0.9, 0.59, 0.25, 0.45)
	content.add_child(separator)

	var profile_label := _label("CREW PROFILE", 12, Color("eea23b"), true)
	content.add_child(profile_label)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 10)
	content.add_child(profile_row)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Callsign"
	name_input.text = GameSession.player_name
	name_input.custom_minimum_size = Vector2(210, 44)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_field(name_input)
	profile_row.add_child(name_input)
	role_picker = OptionButton.new()
	role_picker.custom_minimum_size = Vector2(165, 44)
	for role_name in ["DRIVER", "MECHANIC", "SCOUT", "NAVIGATOR"]:
		role_picker.add_item(role_name)
	role_picker.select(GameSession.selected_role)
	_style_field(role_picker)
	profile_row.add_child(role_picker)

	var solo := _button("START SOLO EXPEDITION", Vector2.ZERO, Vector2(0, 53), Color("dd8f33"))
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.pressed.connect(_start_solo)
	content.add_child(solo)
	var crew_row := HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 10)
	content.add_child(crew_row)
	var host := _button("HOST CREW", Vector2.ZERO, Vector2(0, 48), Color("496e6d"))
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_host_game)
	crew_row.add_child(host)
	var join := _button("JOIN CREW", Vector2.ZERO, Vector2(0, 48), Color("496e6d"))
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_join_game)
	crew_row.add_child(join)
	address_input = LineEdit.new()
	address_input.placeholder_text = "Host IP — e.g. 192.168.1.8"
	address_input.custom_minimum_size.y = 43
	_style_field(address_input)
	content.add_child(address_input)

	status_label = _label("SOLO IS READY • HOST/JOIN USES LAN OR DIRECT IP", 11, Color("bcb9ae"), true)
	status_label.custom_minimum_size.y = 34
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)
	var feature := _label("FIRST-PERSON 3D  •  PHYSICS RV  •  MANUAL GEARS\nREPAIRS  •  MISSIONS  •  WINCHES  •  PROXIMITY VOICE", 11, Color("f1d6a9"), true)
	feature.add_theme_constant_override("line_spacing", 5)
	content.add_child(feature)

	var badge := Label.new()
	badge.text = "LIVE 3D CAMPSITE  •  ORIGINAL MOBILE CO-OP"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.anchor_left = 0.68
	badge.anchor_top = 0.885
	badge.anchor_right = 0.975
	badge.anchor_bottom = 0.95
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("fff0d1"))
	badge.add_theme_stylebox_override("normal", _style(Color(0.03, 0.04, 0.055, 0.72), Color(1, 1, 1, 0.16), 14))
	root.add_child(badge)

func _start_solo() -> void:
	_save_profile()
	Net.start_solo()
	_start_expedition()

func _host_game() -> void:
	_save_profile()
	var error := Net.host_game(GameSession.player_name, GameSession.selected_role)
	if error == OK:
		status_label.text = "CREW LOBBY OPEN ON %s:%d — STARTING…" % [Net._best_local_address(), Net.PORT]
		_start_expedition()

func _join_game() -> void:
	_save_profile()
	status_label.text = "CONTACTING HOST…"
	Net.join_game(address_input.text, GameSession.player_name, GameSession.selected_role)

func _on_joined_server() -> void:
	_start_expedition()

func _on_connection_failed(reason: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = reason.to_upper()

func _on_disconnected() -> void:
	_show_main_menu()
	if status_label:
		status_label.text = "HOST DISCONNECTED — RUN ENDED"

func _start_expedition() -> void:
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	if menu_world and is_instance_valid(menu_world):
		menu_world.queue_free()
		menu_world = null
	GameSession.reset_run()
	active_world = WorldScript.new()
	add_child(active_world)
	active_hud = HUDScript.new()
	add_child(active_hud)

func _run_expedition_smoke_test() -> void:
	GameSession.player_name = "Render Scout"
	GameSession.selected_role = GameSession.Role.DRIVER
	Net.start_solo()
	_start_expedition()
	await get_tree().create_timer(3.0).timeout
	# Capture the 3D viewport without CanvasLayer UI. The resulting proof cannot
	# pass merely because HUD elements rendered over an empty world.
	if active_hud and is_instance_valid(active_hud):
		active_hud.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var failures: Array[String] = []
	if not active_world or not is_instance_valid(active_world):
		failures.append("expedition world missing")
	if not GameSession.local_player or not is_instance_valid(GameSession.local_player):
		failures.append("local player missing")
	if not GameSession.rv or not is_instance_valid(GameSession.rv):
		failures.append("physics RV missing")
	var current_camera := get_viewport().get_camera_3d()
	if not current_camera:
		failures.append("current 3D camera missing")
	var mesh_count := get_tree().get_nodes_in_group("render_smoke_mesh").size()
	if active_world:
		mesh_count = active_world.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count < 50:
		failures.append("expected at least 50 world meshes, found %d" % mesh_count)
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		failures.append("viewport capture is empty")
	else:
		var colors := {}
		var width := image.get_width()
		var height := image.get_height()
		for y in range(0, height, maxi(1, int(height / 18.0))):
			for x in range(0, width, maxi(1, int(width / 24.0))):
				colors[image.get_pixel(x, y).to_rgba32()] = true
		if colors.size() < 18:
			failures.append("viewport lacks visual variation (%d sampled colors)" % colors.size())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/validation"))
		image.save_png("res://build/validation/expedition-render.png")
	print("3D_RENDER_SMOKE camera=%s meshes=%d failures=%s" % [current_camera.name if current_camera else "none", mesh_count, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _show_results(success: bool) -> void:
	var results := CanvasLayer.new()
	results.layer = 80
	add_child(results)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.035, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.add_child(shade)
	var title := _label("ROUTE 17 FOUND" if success else "THE VALLEY WON", 58, Color("fff0d1"), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 180)
	title.size = Vector2(680, 90)
	results.add_child(title)
	var detail := _label("The rig and crew made it out together." if success else "Recover the rig and try a better line.", 18, Color("c9c4b7"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.position = Vector2(300, 276)
	detail.size = Vector2(680, 45)
	results.add_child(detail)
	var retry := _button("RUN IT AGAIN", Vector2(405, 370), Vector2(220, 64), Color("dd8f33"))
	retry.pressed.connect(func() -> void:
		results.queue_free()
		_clear_game()
		_start_expedition()
	)
	results.add_child(retry)
	var menu := _button("MAIN MENU", Vector2(655, 370), Vector2(220, 64), Color("485156"))
	menu.pressed.connect(func() -> void:
		results.queue_free()
		Net.shutdown()
		_show_main_menu()
	)
	results.add_child(menu)

func _clear_game() -> void:
	if active_hud and is_instance_valid(active_hud):
		active_hud.queue_free()
	if active_world and is_instance_valid(active_world):
		active_world.queue_free()
	active_hud = null
	active_world = null

func _save_profile() -> void:
	GameSession.player_name = name_input.text.strip_edges().left(18) if not name_input.text.strip_edges().is_empty() else "Rover"
	GameSession.selected_role = role_picker.selected

func _button(text: String, position: Vector2, size: Vector2, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("fff4dc"))
	button.add_theme_stylebox_override("normal", _style(color, Color(1, 1, 1, 0.16), 14))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.09), Color("ffe3ad"), 14))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.12), Color("fff0d1"), 14))
	return button

func _style_field(control: Control) -> void:
	control.add_theme_font_size_override("font_size", 15)
	control.add_theme_color_override("font_color", Color("fff0d1"))
	control.add_theme_stylebox_override("normal", _style(Color(0.04, 0.05, 0.065, 0.88), Color(1, 1, 1, 0.13), 10))

func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.85))
	return label

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

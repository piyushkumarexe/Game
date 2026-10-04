extends Node
## Application shell: cinematic menu, network lobby and expedition lifecycle.

const WorldScript = preload("res://scripts/world/expedition_world.gd")
const HUDScript = preload("res://scripts/ui/expedition_hud.gd")

var menu_layer: CanvasLayer
var name_input: LineEdit
var address_input: LineEdit
var role_picker: OptionButton
var status_label: Label
var active_world: ExpeditionWorld
var active_hud: ExpeditionHUD

func _ready() -> void:
	Net.joined_server.connect(_on_joined_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	GameSession.run_finished.connect(_show_results)
	_show_main_menu()

func _show_main_menu() -> void:
	_clear_game()
	GameSession.mode = GameSession.Mode.MENU
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 50
	add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(root)

	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/ui/roadtrip-hero.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.055, 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var left_shade := ColorRect.new()
	left_shade.color = Color(0.025, 0.032, 0.045, 0.88)
	left_shade.position = Vector2(0, 0)
	left_shade.size = Vector2(570, 720)
	root.add_child(left_shade)

	var title := _label("DUSTBOUND", 76, Color("fff0d1"), true)
	title.position = Vector2(54, 38)
	root.add_child(title)
	var subtitle := _label("E X P E D I T I O N S", 25, Color("eea23b"), true)
	subtitle.position = Vector2(60, 122)
	root.add_child(subtitle)
	var pitch := _label("ONE RIG. FOUR CREWMATES.\nA VERY BAD ROAD HOME.", 16, Color("d7d2c4"), true)
	pitch.position = Vector2(60, 177)
	root.add_child(pitch)

	var profile_label := _label("CREW PROFILE", 13, Color("eea23b"), true)
	profile_label.position = Vector2(60, 252)
	root.add_child(profile_label)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Callsign"
	name_input.text = GameSession.player_name
	name_input.position = Vector2(60, 278)
	name_input.size = Vector2(238, 47)
	_style_field(name_input)
	root.add_child(name_input)
	role_picker = OptionButton.new()
	role_picker.position = Vector2(310, 278)
	role_picker.size = Vector2(196, 47)
	for role_name in ["DRIVER", "MECHANIC", "SCOUT", "NAVIGATOR"]:
		role_picker.add_item(role_name)
	role_picker.select(GameSession.selected_role)
	_style_field(role_picker)
	root.add_child(role_picker)

	var solo := _button("SOLO EXPEDITION", Vector2(60, 348), Vector2(446, 62), Color("dd8f33"))
	solo.pressed.connect(_start_solo)
	root.add_child(solo)
	var host := _button("HOST CREW", Vector2(60, 422), Vector2(214, 54), Color("496e6d"))
	host.pressed.connect(_host_game)
	root.add_child(host)
	var join := _button("JOIN CREW", Vector2(292, 422), Vector2(214, 54), Color("496e6d"))
	join.pressed.connect(_join_game)
	root.add_child(join)
	address_input = LineEdit.new()
	address_input.placeholder_text = "Host IP — e.g. 192.168.1.8"
	address_input.position = Vector2(60, 489)
	address_input.size = Vector2(446, 45)
	_style_field(address_input)
	root.add_child(address_input)

	status_label = _label("HOST + JOIN SUPPORTS 1–4 PLAYERS OVER LAN OR DIRECT IP", 11, Color("bcb9ae"), true)
	status_label.position = Vector2(60, 550)
	status_label.size = Vector2(450, 42)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var feature := _label("3D PHYSICS  •  MANUAL GEARS  •  TWIN WINCHES\nREPAIRS  •  MISSIONS  •  PROXIMITY VOICE", 12, Color("f1d6a9"), true)
	feature.position = Vector2(60, 618)
	feature.add_theme_constant_override("line_spacing", 7)
	root.add_child(feature)

	var badge := Label.new()
	badge.text = "ORIGINAL MOBILE CO-OP ADVENTURE"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.position = Vector2(890, 646)
	badge.size = Vector2(350, 35)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("fff0d1"))
	badge.add_theme_stylebox_override("normal", _style(Color(0.03, 0.04, 0.055, 0.65), Color(1, 1, 1, 0.16), 14))
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
	GameSession.reset_run()
	active_world = WorldScript.new()
	add_child(active_world)
	active_hud = HUDScript.new()
	add_child(active_hud)

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

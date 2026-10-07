extends Node
## Shared run state and mobile input bridge.

signal mission_changed(title: String, detail: String, index: int, total: int)
signal checkpoint_reached(index: int, title: String)
signal toast_requested(title: String, detail: String)
signal run_finished(success: bool)
signal local_player_ready(player: Node)
signal touch_input_changed
signal settings_changed

enum Mode { MENU, LOBBY, PLAYING, RESULTS }
enum Role { DRIVER, MECHANIC, SCOUT, NAVIGATOR }
enum VoiceMode { PUSH_TO_TALK, OPEN_MIC }

const MISSIONS: Array[Dictionary] = [
	{"title": "PACK FOR THE DETOUR", "detail": "Load 3 supply crates into the RV.", "target": "supplies"},
	{"title": "WAKE THE OLD RIG", "detail": "Get in the driver seat and start the engine.", "target": "engine"},
	{"title": "CROSS DRY CREEK", "detail": "Reach the first trail marker with the RV.", "target": "checkpoint_1"},
	{"title": "THE BROKEN SPAN", "detail": "Place 2 planks, then drive over the washout.", "target": "bridge"},
	{"title": "REPAIR AT LANTERN POST", "detail": "Use scrap to restore the RV at the ranger garage.", "target": "repair"},
	{"title": "MUDWATER BOG", "detail": "Attach a winch and pull the RV through the mud.", "target": "winch"},
	{"title": "LAST LIGHT PASS", "detail": "Climb the switchbacks and survive the rockfall.", "target": "checkpoint_3"},
	{"title": "FIND ROUTE 17", "detail": "Bring the RV safely home.", "target": "finish"}
]

var mode: Mode = Mode.MENU
var mission_index: int = 0
var checkpoint_index: int = 0
var supplies_loaded: int = 0
var planks_placed: int = 0
var local_player: Node
var rv: Node
var world: Node
var mobile_move := Vector2.ZERO
var mobile_look_delta := Vector2.ZERO
var mobile_actions: Dictionary = {}
var player_name: String = "Rover"
var selected_role: Role = Role.DRIVER
## True when this process is a rendering-free authoritative host (`--server`).
var dedicated := false
var last_join_address := ""
var voice_enabled := true
var voice_deafened := false
var voice_mode: VoiceMode = VoiceMode.PUSH_TO_TALK
var reduced_graphics: bool = false
var graphics_quality := 1
var control_scale := 1.0
var control_opacity := 0.82
var touch_look_speed := 1.0
var control_layout: Dictionary = {}

const SETTINGS_PATH := "user://dustbound_settings.cfg"
const DEFAULT_CONTROL_LAYOUT := {
	"move": Vector2(0.085, 0.85),
	"toggle_view": Vector2(0.945, 0.52),
	"interact": Vector2(0.945, 0.77),
	"jump": Vector2(0.953, 0.91),
	"sprint": Vector2(0.872, 0.91),
	"winch_front": Vector2(0.800, 0.91),
	"winch_rear": Vector2(0.722, 0.91),
	"voice": Vector2(0.645, 0.905),
	"shift_up": Vector2(0.947, 0.64),
	"shift_down": Vector2(0.870, 0.64),
	"handbrake": Vector2(0.870, 0.77)
}

func _ready() -> void:
	_create_input_actions()
	# Host-raised toasts reach every client through the network layer, so the
	# crew shares one feed of what happened to the rig.
	toast_requested.connect(_relay_toast_to_crew)
	graphics_quality = 1 if OS.has_feature("mobile") else 2
	control_layout = DEFAULT_CONTROL_LAYOUT.duplicate(true)
	_load_settings()
	reduced_graphics = graphics_quality == 0

func _relay_toast_to_crew(title: String, detail: String) -> void:
	Net.broadcast_toast(title, detail)


func reset_run() -> void:
	mission_index = 0
	checkpoint_index = 0
	supplies_loaded = 0
	planks_placed = 0
	local_player = null
	rv = null
	world = null
	mobile_move = Vector2.ZERO
	mobile_look_delta = Vector2.ZERO
	mobile_actions.clear()
	mode = Mode.PLAYING
	_emit_mission()

func control_position(action: StringName) -> Vector2:
	return Vector2(control_layout.get(str(action), DEFAULT_CONTROL_LAYOUT.get(str(action), Vector2(0.5, 0.5))))

func set_control_position(action: StringName, normalized_position: Vector2) -> void:
	control_layout[str(action)] = Vector2(
		clampf(normalized_position.x, 0.035, 0.965),
		clampf(normalized_position.y, 0.08, 0.94)
	)

func reset_control_layout() -> void:
	control_layout = DEFAULT_CONTROL_LAYOUT.duplicate(true)
	control_scale = 1.0
	control_opacity = 0.82
	touch_look_speed = 1.0
	settings_changed.emit()

func save_profile() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("profile", "name", player_name)
	config.set_value("profile", "role", selected_role)
	config.set_value("profile", "last_join", last_join_address)
	config.save(SETTINGS_PATH)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("video", "quality", graphics_quality)
	config.set_value("controls", "scale", control_scale)
	config.set_value("controls", "opacity", control_opacity)
	config.set_value("controls", "look_speed", touch_look_speed)
	config.set_value("voice", "enabled", voice_enabled)
	config.set_value("voice", "mode", voice_mode)
	for action: String in control_layout:
		config.set_value("layout", action, control_layout[action])
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save mobile settings: %s" % error_string(error))
	reduced_graphics = graphics_quality == 0
	settings_changed.emit()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = str(config.get_value("profile", "name", player_name))
	selected_role = clampi(int(config.get_value("profile", "role", selected_role)), 0, 3)
	last_join_address = str(config.get_value("profile", "last_join", ""))
	graphics_quality = clampi(int(config.get_value("video", "quality", graphics_quality)), 0, 2)
	control_scale = clampf(float(config.get_value("controls", "scale", 1.0)), 0.72, 1.35)
	control_opacity = clampf(float(config.get_value("controls", "opacity", 0.82)), 0.35, 1.0)
	touch_look_speed = clampf(float(config.get_value("controls", "look_speed", 1.0)), 0.55, 1.65)
	voice_enabled = bool(config.get_value("voice", "enabled", true))
	voice_mode = clampi(int(config.get_value("voice", "mode", VoiceMode.PUSH_TO_TALK)), 0, 1)
	for action: String in DEFAULT_CONTROL_LAYOUT:
		var saved_position: Variant = config.get_value("layout", action, DEFAULT_CONTROL_LAYOUT[action])
		if saved_position is Vector2:
			set_control_position(action, saved_position)

func role_label(role: int) -> String:
	match clampi(role, 0, 3):
		0:
			return "DRIVER"
		1:
			return "MECHANIC"
		2:
			return "SCOUT"
		_:
			return "NAVIGATOR"


func toggle_mute() -> void:
	voice_deafened = not voice_deafened
	toast_requested.emit("RADIO %s" % ("DEAFENED" if voice_deafened else "LISTENING"),
		"You will not hear the crew." if voice_deafened else "Crew voice is back on.")


func toggle_voice() -> void:
	voice_enabled = not voice_enabled
	toast_requested.emit("RADIO %s" % ("ON" if voice_enabled else "OFF"),
		"Hold V or the RADIO button to talk." if voice_enabled else "Microphone capture is disabled.")


func complete_target(target: String) -> bool:
	if mission_index >= MISSIONS.size():
		return false
	if str(MISSIONS[mission_index]["target"]) != target:
		return false
	mission_index += 1
	if mission_index >= MISSIONS.size():
		run_finished.emit(true)
	else:
		_emit_mission()
	Net.broadcast_progress()
	return true

func set_checkpoint(index: int, title: String) -> void:
	if index <= checkpoint_index:
		return
	checkpoint_index = index
	checkpoint_reached.emit(index, title)
	toast_requested.emit("CHECKPOINT SECURED", title + " — run state saved")
	if not complete_target("checkpoint_%d" % index):
		Net.broadcast_progress()

func register_local_player(player: Node) -> void:
	local_player = player
	local_player_ready.emit(player)

func set_touch_action(action: StringName, pressed: bool) -> void:
	mobile_actions[action] = pressed
	touch_input_changed.emit()

func touch_action(action: StringName) -> bool:
	return bool(mobile_actions.get(action, false))

func movement_vector() -> Vector2:
	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return mobile_move if mobile_move.length_squared() > keyboard.length_squared() else keyboard

func look_vector() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")

func add_touch_look(relative: Vector2) -> void:
	mobile_look_delta += relative

func consume_touch_look() -> Vector2:
	var relative := mobile_look_delta
	mobile_look_delta = Vector2.ZERO
	return relative

func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action) or touch_action(action)

func is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action) or bool(mobile_actions.get(StringName("just_" + str(action)), false))

func consume_touch_press(action: StringName) -> bool:
	var key := StringName("just_" + str(action))
	if not bool(mobile_actions.get(key, false)):
		return false
	mobile_actions[key] = false
	return true

func pulse_touch_action(action: StringName) -> void:
	mobile_actions[StringName("just_" + str(action))] = true

func _emit_mission() -> void:
	var mission: Dictionary = MISSIONS[mission_index]
	mission_changed.emit(str(mission["title"]), str(mission["detail"]), mission_index + 1, MISSIONS.size())
	toast_requested.emit(str(mission["title"]), str(mission["detail"]))

func _create_input_actions() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("interact", [KEY_E])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("primary", [KEY_F])
	_bind_keys("winch_front", [KEY_Q])
	_bind_keys("winch_rear", [KEY_R])
	_bind_keys("shift_up", [KEY_X])
	_bind_keys("shift_down", [KEY_Z])
	_bind_keys("toggle_view", [KEY_C])
	# Radio: hold V (or right-stick click) to talk, M to mute the whole radio.
	_bind_keys("voice", [KEY_V])
	_bind_keys("toggle_voice", [KEY_M])
	_bind_keys("handbrake", [KEY_SPACE])
	_bind_keys("pause", [KEY_ESCAPE])
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	# Complete controller parity: face buttons cover locomotion/interaction and
	# shoulders/D-pad handle the RV without requiring keyboard or touch fallback.
	_bind_joy_button("jump", JOY_BUTTON_A)
	_bind_joy_button("interact", JOY_BUTTON_X)
	_bind_joy_button("toggle_view", JOY_BUTTON_Y)
	_bind_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_bind_joy_button("handbrake", JOY_BUTTON_B)
	_bind_joy_button("shift_up", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_joy_button("shift_down", JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button("winch_front", JOY_BUTTON_DPAD_UP)
	_bind_joy_button("winch_rear", JOY_BUTTON_DPAD_DOWN)
	_bind_joy_button("pause", JOY_BUTTON_START)
	_bind_joy_button("voice", JOY_BUTTON_RIGHT_STICK)
	# No gamepad binding for deafen: START/BACK are already claimed by the pause
	# path on the Android and iOS controllers this project targets, and the HUD
	# chip covers touch play.

func _bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for key_code: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key_code
		InputMap.action_add_event(action, event)

func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _bind_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

class_name ProximityVoice
extends Node
## Proximity voice for the crew. 12 kHz mono, ~9 KB/s per talker.
##
## One node lives under each player. The local player's node owns the microphone
## and one positional speaker per remote talker, so a buddy behind the RV sounds
## like he is behind the RV. The host does the distance filtering (see
## NetworkManager), which is why a client never broadcasts to the whole session.

const MIX_RATE := 12000.0
const PACKET_SAMPLES := 240
const SEND_INTERVAL := 0.05
const SPEAKER_MAX_DISTANCE := 28.0

var owner_peer_id := 0
var capture: AudioEffectCapture
var microphone: AudioStreamPlayer
var speakers := {}
var send_accumulator := 0.0
var mic_ready := false
var speaking := false


func setup(peer_id: int) -> void:
	owner_peer_id = peer_id
	if peer_id == multiplayer.get_unique_id():
		_setup_microphone()


func _exit_tree() -> void:
	if microphone and is_instance_valid(microphone):
		microphone.stop()
	for peer_id: int in speakers.keys():
		var entry: Dictionary = speakers[peer_id]
		var player: AudioStreamPlayer3D = entry.get("player")
		if player and is_instance_valid(player):
			player.stop()
	speakers.clear()


func _process(delta: float) -> void:
	if owner_peer_id != multiplayer.get_unique_id():
		return
	send_accumulator += delta
	if send_accumulator < SEND_INTERVAL:
		return
	send_accumulator = 0.0
	var talking := _talk_requested()
	if not talking or not mic_ready or capture == null:
		if speaking:
			speaking = false
		# Drop whatever the mic heard while muted, otherwise releasing push-to-talk
		# plays the whole walkie-talkie backlog at once.
		if capture:
			capture.clear_buffer()
		return
	speaking = true
	var available := capture.get_frames_available()
	if available < PACKET_SAMPLES:
		return
	var frames := capture.get_buffer(PACKET_SAMPLES)
	var packet := PackedByteArray()
	packet.resize(frames.size() * 2)
	for index in frames.size():
		var sample := clampf(frames[index].x, -1.0, 1.0)
		packet.encode_s16(index * 2, int(sample * 32767.0))
	Net.voice_out(packet)


func _talk_requested() -> bool:
	if GameSession.voice_deafened or not GameSession.voice_enabled:
		return false
	if GameSession.voice_mode == GameSession.VoiceMode.OPEN_MIC:
		return true
	return GameSession.is_action_pressed("voice")


## Called by NetworkManager when the host relays packets to this client.
func push_samples(from_peer: int, packet: PackedByteArray) -> void:
	if from_peer == owner_peer_id or GameSession.voice_deafened or not GameSession.voice_enabled:
		return
	if packet.size() < 2:
		return
	var entry := _ensure_speaker(from_peer)
	if entry.is_empty():
		return
	var playback: AudioStreamGeneratorPlayback = entry["playback"]
	if playback == null:
		return
	var frame_count := int(packet.size() / 2)
	if playback.get_frames_available() < frame_count:
		# The talker outran the jitter buffer: skip rather than distort.
		return
	for index in frame_count:
		var sample := float(packet.decode_s16(index * 2)) / 32767.0
		playback.push_frame(Vector2(sample, sample))
	entry["last_heard"] = Time.get_ticks_msec()


func _ensure_speaker(from_peer: int) -> Dictionary:
	if speakers.has(from_peer):
		return speakers[from_peer]
	if Net.world == null or not is_instance_valid(Net.world):
		return {}
	var talker: Node = Net.world.get_player(from_peer)
	if talker == null:
		return {}
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.4
	var player := AudioStreamPlayer3D.new()
	player.name = "VoiceOf_%d" % from_peer
	player.stream = generator
	player.bus = _voice_bus()
	player.unit_size = 3.5
	player.max_distance = SPEAKER_MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# Parenting to the talker means the voice tracks them without extra sync.
	talker.add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return {}
	var entry := {"player": player, "playback": playback, "last_heard": Time.get_ticks_msec()}
	speakers[from_peer] = entry
	return entry


func _voice_bus() -> String:
	if AudioServer.get_bus_index("Voice") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "Voice")
	return "Voice"


func _setup_microphone() -> void:
	if not _input_device_ready():
		# A missing mic or a denied Android permission must never break the run:
		# crew keep playing, they just cannot radio each other.
		GameSession.toast_requested.emit("NO MICROPHONE", "Radio is off for you — gestures and winch buttons still work.")
		return
	var bus_index := AudioServer.get_bus_index("VoiceCapture")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "VoiceCapture")
	# The capture bus must never reach the speakers, or every talker hears
	# themselves through the room with a full buffer of delay.
	AudioServer.set_bus_mute(bus_index, true)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.35
	AudioServer.add_bus_effect(bus_index, capture, 0)
	microphone = AudioStreamPlayer.new()
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = "VoiceCapture"
	add_child(microphone)
	microphone.play()
	mic_ready = true


func _input_device_ready() -> bool:
	# An empty input list means no microphone (or no recorder permission yet).
	# Godot requests RECORD_AUDIO itself because the export preset declares it,
	# so this only has to decide whether to build the capture chain at all.
	return not AudioServer.get_input_device_list().is_empty()


func is_speaking() -> bool:
	return speaking


func is_recently_heard(peer_id: int) -> bool:
	var entry: Dictionary = speakers.get(peer_id, {})
	if entry.is_empty():
		return false
	return Time.get_ticks_msec() - int(entry["last_heard"]) < 420

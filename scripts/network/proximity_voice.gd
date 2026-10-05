class_name ProximityVoice
extends Node
## Lightweight 12 kHz mono proximity voice for four-player co-op.

const MIX_RATE := 12000.0
const PACKET_SAMPLES := 240

var owner_peer_id := 1
var capture: AudioEffectCapture
var microphone: AudioStreamPlayer
var speaker: AudioStreamPlayer3D
var playback: AudioStreamGeneratorPlayback
var send_accumulator := 0.0

func setup(peer_id: int) -> void:
	owner_peer_id = peer_id
	if peer_id == multiplayer.get_unique_id() and Net.is_online:
		_setup_microphone()
	else:
		_setup_speaker()

func _process(delta: float) -> void:
	if not capture or owner_peer_id != multiplayer.get_unique_id() or not Net.is_online:
		return
	send_accumulator += delta
	if send_accumulator < 0.055:
		return
	send_accumulator = 0.0
	var available := capture.get_frames_available()
	if available < 64:
		return
	var frames := capture.get_buffer(mini(available, 1024))
	var stride := maxi(1, frames.size() / PACKET_SAMPLES)
	var count := mini(PACKET_SAMPLES, int(frames.size() / stride))
	var packet := PackedByteArray()
	packet.resize(count * 2)
	for index in count:
		var sample := clampf(frames[index * stride].x, -1.0, 1.0)
		packet.encode_s16(index * 2, int(sample * 32767.0))
	_receive_voice.rpc(packet)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_voice(packet: PackedByteArray) -> void:
	if not playback or packet.size() < 2:
		return
	var frame_count := int(packet.size() / 2)
	if playback.get_frames_available() < frame_count:
		return
	for index in frame_count:
		var sample := float(packet.decode_s16(index * 2)) / 32767.0
		playback.push_frame(Vector2(sample, sample))

func _setup_microphone() -> void:
	var bus_index := AudioServer.get_bus_index("VoiceCapture")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "VoiceCapture")
		AudioServer.set_bus_mute(bus_index, true)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.35
	AudioServer.add_bus_effect(bus_index, capture)
	microphone = AudioStreamPlayer.new()
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = "VoiceCapture"
	add_child(microphone)
	microphone.play()

func _setup_speaker() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.35
	speaker = AudioStreamPlayer3D.new()
	speaker.stream = generator
	speaker.bus = "Voice"
	speaker.unit_size = 3.5
	speaker.max_distance = 28.0
	speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(speaker)
	speaker.play()
	playback = speaker.get_stream_playback() as AudioStreamGeneratorPlayback

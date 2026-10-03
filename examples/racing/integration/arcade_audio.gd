extends Node
## Six fixed voices. Presentation only: no storage, rules or vehicle writes.
const LOOPS := ["engine_idle_loop", "engine_drive_loop", "tire_skid_loop", "nitro_loop"]
const ONESHOTS := ["impact_soft", "countdown_beep"]
var voices: Dictionary = {}
var muted := false
var gain := 0.7
var loaded := true
var clock := 0.0
var last_impact := -10.0
var countdown_step := -1
var previous_phase := ""
var play_counts: Dictionary = {}
var levels: Dictionary = {}
var shutting_down := false

func _ready() -> void:
	for name in LOOPS + ONESHOTS:
		var voice := AudioStreamPlayer.new()
		voice.name = name
		var source = load("res://audio/" + name + ".wav")
		if not source is AudioStreamWAV:
			loaded = false
			voice.queue_free()
			continue
		var stream: AudioStreamWAV = source.duplicate()
		if name in LOOPS:
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		voice.stream = stream
		voice.volume_db = -80.0
		add_child(voice)
		voices[name] = voice
		levels[name] = 0.0
		play_counts[name] = 0
	reset()

func reset() -> void:
	if shutting_down: return
	clock = 0.0
	last_impact = -10.0
	countdown_step = -1
	previous_phase = ""
	for name in voices:
		var voice: AudioStreamPlayer = voices[name]
		voice.stop()
		voice.stream_paused = false
		voice.volume_db = -80.0
		levels[name] = 0.0
		if name in LOOPS:
			voice.play()

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for name in voices:
			voices[name].volume_db = -80.0
			levels[name] = 0.0

func shutdown() -> void:
	# Release active WAV playbacks before the audio server shuts down.
	shutting_down = true
	for voice in voices.values():
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	voices.clear()

func _exit_tree() -> void:
	shutdown()

func _loop(name: String, target: float, pitch: float, dt: float) -> void:
	if not voices.has(name): return
	var volume: float = lerpf(float(levels[name]), target * gain if not muted else 0.0, 1.0 - exp(-12.0 * dt))
	levels[name] = volume
	var voice: AudioStreamPlayer = voices[name]
	voice.volume_db = linear_to_db(maxf(volume, 0.0001))
	voice.pitch_scale = clampf(pitch, 0.6, 2.0)

func _one(name: String, volume: float, pitch := 1.0) -> void:
	if muted or not voices.has(name): return
	var voice: AudioStreamPlayer = voices[name]
	voice.pitch_scale = pitch
	voice.volume_db = linear_to_db(maxf(volume * gain, 0.0001))
	voice.play()
	play_counts[name] = int(play_counts[name]) + 1

func update_feedback(dt: float, data: Dictionary, practice: Dictionary, paused: bool, held: bool) -> void:
	if shutting_down: return
	if not is_finite(dt) or dt <= 0.0: return
	dt = minf(dt, 0.1)
	for voice in voices.values(): voice.stream_paused = paused
	if paused: return
	clock += dt
	var speed: float = clampf(float(data.get("speed", 0.0)), 0.0, 80.0)
	var forward: float = float(data.get("forward_speed", 0.0))
	var slip: float = absf(float(data.get("slip_degrees", 0.0)))
	var drive := clampf(speed / 35.0, 0.0, 1.0) if not held else 0.0
	var drift: bool = not held and forward >= 6.0 and slip >= 8.0 and slip <= 75.0 and data.get("mode", "forward") != "reverse"
	_loop("engine_idle_loop", 0.12 * (1.0 - drive * 0.7), 0.9 + drive * 0.3, dt)
	_loop("engine_drive_loop", drive * 0.15, 0.75 + drive * 0.85, dt)
	_loop("tire_skid_loop", clampf(slip / 45.0, 0.0, 1.0) * 0.16 if drift else 0.0, 0.9 + drive * 0.15, dt)
	_loop("nitro_loop", 0.18 if bool(data.get("boost_active", false)) and not held else 0.0, 1.0, dt)
	if float(data.get("wall_impact_speed", 0.0)) >= 2.0 and clock - last_impact >= 0.18 and not held:
		last_impact = clock
		_one("impact_soft", minf(0.35, float(data.wall_impact_speed) * 0.02))
	var phase := str(practice.get("phase", ""))
	if phase == "countdown":
		var step := ceili(float(practice.get("countdown_remaining_ms", 0)) / 1000.0)
		if step > 0 and step != countdown_step:
			countdown_step = step
			_one("countdown_beep", 0.22)
	elif phase == "ready" and previous_phase == "countdown":
		_one("countdown_beep", 0.28, 1.4)
	previous_phase = phase

func snapshot() -> Dictionary:
	var loops: Dictionary = {}
	for name in LOOPS:
		if voices.has(name): loops[name] = {"mode": voices[name].stream.loop_mode, "pitch": voices[name].pitch_scale, "paused": voices[name].stream_paused, "playing": voices[name].playing, "level": levels[name]}
	return {"loaded": loaded, "voices": voices.size(), "muted": muted, "gain": gain, "loops": loops, "one_shots": play_counts.duplicate(), "clock": clock}

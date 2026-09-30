extends Node
## Client-only sound board for the example shell. Every cue is synthesized here at
## startup (no audio files, no licences to track); the numbers below are the
## source. The room server never loads this script. Settings live in user://
## (outside the generated client folder, so regenerating PlayerClient keeps them).
const RATE := 22050
const MAX_VOICES := 8
## Concurrent voices per cue and minimum spacing: rapid fire restarts the oldest
## voice instead of stacking, and one click never produces two sounds.
const PER_CUE := {"fire": 3, "hit": 2, "death": 2, "purchase": 1, "click": 1}
const MIN_GAP_MS := {"fire": 40, "hit": 50, "death": 0, "purchase": 150, "click": 60}
const GAIN := {"fire": 0.55, "hit": 0.6, "death": 0.75, "purchase": 0.7, "click": 0.4}
const DEFAULT_VOLUME := 0.7

var settings_path := "user://audio_settings.json"
var volume := DEFAULT_VOLUME
var muted := false
var settings_error := ""
## Real AudioStreamPlayer nodes are only created with a display; a headless client
## keeps the same bookkeeping (limits, counters) without audio nodes.
var create_players := DisplayServer.get_name() != "headless"
var streams: Dictionary = {}
var voices: Array = []
var last_played: Dictionary = {}
var played: Dictionary = {}
var suppressed := 0
var throttled := 0
var stolen := 0
var peak_voices := 0

func _ready() -> void:
	streams = {
		"fire": _render([[0.09, 190.0, 55.0, 0.75, 38.0]]),
		"hit": _render([[0.07, 1500.0, 1100.0, 0.05, 45.0]]),
		"death": _render([[0.42, 420.0, 105.0, 0.15, 6.0]]),
		"purchase": _render([[0.1, 880.0, 880.0, 0.0, 14.0], [0.17, 1320.0, 1320.0, 0.0, 12.0]]),
		"click": _render([[0.035, 2200.0, 1800.0, 0.1, 90.0]]),
	}
	for index in MAX_VOICES:
		var voice := {"cue": "", "ends": 0, "started": 0, "player": null}
		if create_players:
			var player := AudioStreamPlayer.new()
			player.name = "Voice%d" % index
			add_child(player)
			voice.player = player
		voices.append(voice)
	load_settings()

## Segments: [seconds, start Hz, end Hz, noise share, decay]. Deterministic noise.
static func _render(segments: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	var state := 22695477
	for segment in segments:
		var seconds: float = segment[0]
		var f0: float = segment[1]
		var f1: float = segment[2]
		var noise_share: float = segment[3]
		var decay: float = segment[4]
		var count := int(seconds * RATE)
		var offset := data.size()
		data.resize(offset + count * 2)
		var phase := 0.0
		for i in count:
			var t := float(i) / RATE
			phase += TAU * lerpf(f0, f1, t / seconds) / RATE
			state = (state * 1103515245 + 12345) & 0x7fffffff
			var noise := float(state) / float(0x3fffffff) - 1.0
			var sample := sin(phase) * (1.0 - noise_share) + noise * noise_share
			var envelope := exp(-decay * t) * minf(1.0, t * 400.0) * minf(1.0, (seconds - t) * 200.0)
			data.encode_s16(offset + i * 2, int(clampf(sample * envelope * 0.8, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream

func play(cue: String, pitch := 1.0) -> bool:
	if not streams.has(cue):
		return false
	if muted or volume <= 0.0:
		suppressed += 1
		return false
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(cue, -1000000)) < int(MIN_GAP_MS[cue]):
		throttled += 1
		return false
	var same: Array = voices.filter(func(v): return v.cue == cue and int(v.ends) > now)
	var voice: Dictionary
	if same.size() >= int(PER_CUE[cue]):
		voice = _oldest(same)
		stolen += 1
	else:
		var free: Array = voices.filter(func(v): return int(v.ends) <= now)
		if free.is_empty():
			voice = _oldest(voices)
			stolen += 1
		else:
			voice = free[0]
	var length: float = streams[cue].get_length() / maxf(pitch, 0.1)
	voice.cue = cue
	voice.started = now
	voice.ends = now + int(ceil(length * 1000.0))
	last_played[cue] = now
	played[cue] = int(played.get(cue, 0)) + 1
	peak_voices = maxi(peak_voices, active_voices())
	if voice.player != null:
		var player: AudioStreamPlayer = voice.player
		player.stream = streams[cue]
		player.pitch_scale = pitch
		player.volume_db = linear_to_db(volume * float(GAIN[cue]))
		player.play()
	return true

static func _oldest(list: Array) -> Dictionary:
	var best: Dictionary = list[0]
	for voice in list:
		if int(voice.started) < int(best.started):
			best = voice
	return best

func active_voices() -> int:
	var now := Time.get_ticks_msec()
	return voices.filter(func(v): return int(v.ends) > now).size()

func set_volume(value: float, save := true) -> void:
	volume = clampf(value, 0.0, 1.0)
	for voice in voices:
		if voice.player != null and voice.player.playing:
			voice.player.volume_db = linear_to_db(volume * float(GAIN.get(voice.cue, 1.0)))
	if save:
		save_settings()

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for voice in voices:
			voice.ends = 0
			if voice.player != null:
				voice.player.stop()
	save_settings()

func load_settings() -> void:
	settings_error = ""
	if not FileAccess.file_exists(settings_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not data is Dictionary or not (data.get("volume") is float or data.get("volume") is int) or not data.get("muted") is bool:
		settings_error = "invalid"
		return
	volume = clampf(float(data.volume), 0.0, 1.0)
	muted = data.muted

func save_settings() -> bool:
	var path := ProjectSettings.globalize_path(settings_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		settings_error = "write"
		return false
	file.store_string(JSON.stringify({"format": 1, "volume": snappedf(volume, 0.01), "muted": muted}))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		settings_error = "write"
		return false
	settings_error = ""
	return true

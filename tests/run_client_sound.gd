extends "res://examples/framework/client.gd"
## Client sound regression without a window: settings persistence, mute, voice
## limits, cue derivation from real authoritative shooter snapshots, and purchase
## success only on confirmed, non-repeated responses. It proves triggering and
## limits, not how the sounds are heard.
## Usage: --headless --script res://tests/run_client_sound.gd -- --work=<empty dir>
const ShooterWorld = preload("res://examples/shooter/game.gd")
var passed := 0
var failed := 0
var work := ""
var responses: Array = []

class FakeClient extends Node:
	var state := "LOBBY"
	var identity := {"user_id": "sound_player"}
	var last_error := ""
	var queue: Array = []
	func purchase(_item: String, _operation: String) -> Dictionary:
		return queue.pop_front()
	func select_item(_slot: String, _item: String, _operation: String) -> Dictionary:
		return queue.pop_front()

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work="):
			work = argument.trim_prefix("--work=")
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _save_pending() -> bool:
	return true

func _read_assets() -> bool:
	return true

func _verify() -> void:
	if work == "" or not DirAccess.dir_exists_absolute(work):
		printerr("FAIL --work must name an existing directory")
		quit(2)
		return
	await _settings()
	await _limits()
	await _players()
	_cues()
	await _purchases()
	print("CLIENT_SOUND_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _board(path: String):
	var board = Sound.new()
	board.settings_path = path
	root.add_child(board)
	return board

func _settings() -> void:
	var path := work.path_join("audio_settings.json")
	var first = _board(path)
	_check(is_equal_approx(first.volume, 0.7) and not first.muted and first.settings_error == "", "missing settings use defaults (volume 70%, sound on)")
	_check(not FileAccess.file_exists(path), "loading never creates a settings file")
	_check(first.create_players == false and first.get_child_count() == 0, "headless client creates no audio player nodes")
	for cue in ["fire", "hit", "death", "purchase", "click"]:
		var length: float = first.streams[cue].get_length()
		_check(length > 0.02 and length < 0.5, "synthesized %s cue is short (%.3f s)" % [cue, length])
		# Audition copies for a listening check outside the game.
		first.streams[cue].save_to_wav(work.path_join("cue-" + cue + ".wav"))
	first.set_volume(0.35)
	first.set_muted(true)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(saved is Dictionary and is_equal_approx(float(saved.volume), 0.35) and saved.muted == true, "volume and mute are written to the settings file")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temporary settings file remains")
	var second = _board(path)
	_check(is_equal_approx(second.volume, 0.35) and second.muted, "a new client reads saved volume and mute")
	_check(second.play("fire") == false and second.suppressed == 1 and second.active_voices() == 0, "muted client plays nothing")
	second.set_muted(false)
	_check(second.play("fire") == true, "unmuted client plays again")
	second.set_volume(0.0)
	_check(second.play("hit") == false, "zero volume plays nothing")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"volume\": \"loud\", \"muted\": 1}")
	file.close()
	var third = _board(path)
	_check(third.settings_error == "invalid" and is_equal_approx(third.volume, 0.7) and not third.muted, "invalid settings file falls back to defaults")
	for board in [first, second, third]:
		board.queue_free()
	await process_frame

func _limits() -> void:
	var board = _board(work.path_join("limits.json"))
	var worst_fire := 0
	var worst_total := 0
	var attempts := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1000:
		board.play("fire")
		board.play("hit")
		board.play("death")
		attempts += 1
		var now := Time.get_ticks_msec()
		worst_fire = maxi(worst_fire, board.voices.filter(func(v): return v.cue == "fire" and int(v.ends) > now).size())
		worst_total = maxi(worst_total, board.active_voices())
		await create_timer(0.005).timeout
	var fired := int(board.played.get("fire", 0))
	_check(worst_fire <= 3, "sustained fire never exceeds 3 fire voices (max %d)" % worst_fire)
	_check(worst_total <= Sound.MAX_VOICES and board.peak_voices <= Sound.MAX_VOICES, "total voices stay within %d (max %d)" % [Sound.MAX_VOICES, worst_total])
	_check(fired > 5 and fired <= 26 and board.throttled > 0, "fire is spaced at least 40 ms (%d played of %d attempts)" % [fired, attempts])
	_check(board.stolen > 0, "full cue slots restart the oldest voice instead of stacking")
	board.last_played.erase("click")
	var clicks := [board.play("click"), board.play("click")]
	_check(clicks == [true, false], "an immediate second click is not played twice")
	_check(board.play("unknown") == false, "unknown cue names are ignored")
	board.queue_free()
	await process_frame

func _players() -> void:
	var board = Sound.new()
	board.create_players = true
	board.settings_path = work.path_join("players.json")
	root.add_child(board)
	var nodes: Array = board.get_children().filter(func(n): return n is AudioStreamPlayer)
	_check(nodes.size() == Sound.MAX_VOICES, "with a display the pool has exactly %d audio players" % Sound.MAX_VOICES)
	board.play("purchase")
	var used: Array = nodes.filter(func(n): return n.stream != null)
	_check(used.size() == 1 and used[0].stream == board.streams["purchase"] and used[0].volume_db < 0.0, "a cue plays through one pooled player at reduced volume")
	board.set_muted(true)
	_check(nodes.all(func(n): return not n.playing), "muting stops every pooled player")
	# Let the audio server drop the stopped playback before freeing its player.
	await create_timer(0.3).timeout
	board.queue_free()
	await process_frame

func _cues() -> void:
	var authority = ShooterWorld.new()
	var world = ShooterWorld.new()
	var heard: Array = []
	world.presentation_cue.connect(func(cue, detail): heard.append({"cue": cue, "user": str(detail.get("user_id", ""))}))
	authority.server = true
	authority.admit({"user_id": "u1", "display_name": "射手"}, 2)
	authority.admit({"user_id": "u2", "display_name": "目标"}, 3)
	authority.players.u1.position = Vector2(300, 478)
	authority.players.u2.position = Vector2(420, 478)
	authority.players.u1.aim = Vector2.RIGHT
	authority.advance(0)
	var send := func():
		authority.tick += 1
		var snapshot: Dictionary = authority.state_snapshot()
		world.world_state(snapshot)
		return snapshot
	send.call()
	_check(heard.is_empty(), "first snapshot after joining plays nothing")
	authority._fire(authority.players.u1, 1000)
	var hit_snapshot: Dictionary = send.call()
	_check(_count(heard, "fire") == 1 and _count(heard, "hit") == 1 and heard.any(func(h): return h.cue == "hit" and h.user == "u2"), "one confirmed shot gives one fire and one hit on the target")
	heard.clear()
	world.world_state(hit_snapshot)
	_check(heard.is_empty(), "a repeated snapshot plays nothing again")
	var stale: Dictionary = hit_snapshot.duplicate(true)
	stale.tick = int(hit_snapshot.tick) - 1
	world.world_state(stale)
	_check(heard.is_empty(), "an older snapshot is rejected silently")
	send.call()
	_check(heard.is_empty(), "a snapshot with the same shots and hp plays nothing")
	for step in 3:
		authority._fire(authority.players.u1, 2000 + step * 300)
		send.call()
	_check(_count(heard, "death") == 1 and _count(heard, "hit") == 2 and _count(heard, "fire") == 3, "the lethal shot plays death once, not hit (hits %d, deaths %d)" % [_count(heard, "hit"), _count(heard, "death")])
	heard.clear()
	for step in 3:
		send.call()
	_check(heard.is_empty(), "staying dead plays no further death")
	authority.players.u2.dead_at = -10000
	authority.request_respawn("u2")
	authority.complete_respawn("u2", {})
	send.call()
	_check(heard.is_empty(), "respawn plays nothing")
	heard.clear()
	authority.players.u1.weapon = "shotgun"
	authority.players.u1.position = Vector2(300, 478)
	authority.players.u2.position = Vector2(340, 478)
	authority._fire(authority.players.u1, 5000)
	send.call()
	_check(_count(heard, "fire") == 1, "a shotgun pull of six pellets plays one fire cue")
	authority.free()
	world.free()

func _count(list: Array, cue: String) -> int:
	return list.filter(func(h): return h.cue == cue).size()

func _purchases() -> void:
	sound = _board(work.path_join("purchase.json"))
	var fake := FakeClient.new()
	root.add_child(fake)
	client = fake
	authenticated = true
	var valid := {"state": {"revision": 2, "credits": 40, "experience": 0, "owned": ["rifle", "smg"], "profiles": {"shooter": {"primary": "rifle"}}}, "level": 1}
	var purchases := func(): return int(sound.played.get("purchase", 0))
	pending_asset = {"kind": "purchase", "item_id": "smg", "slot": "", "operation_id": "a".repeat(32)}
	fake.queue = [{"ok": false, "code": "INSUFFICIENT_CREDITS"}]
	await retry_asset()
	_check(purchases.call() == 0 and pending_asset.is_empty(), "rejected purchase plays no success sound")
	pending_asset = {"kind": "purchase", "item_id": "smg", "slot": "", "operation_id": "b".repeat(32)}
	fake.queue = [{"ok": false, "code": "TIMEOUT"}]
	await retry_asset()
	_check(purchases.call() == 0 and not pending_asset.is_empty(), "unconfirmed (timed out) purchase plays nothing and stays pending")
	fake.queue = [{"ok": true, "payload": valid}]
	await retry_asset()
	_check(purchases.call() == 1 and pending_asset.is_empty(), "the confirmed retry plays the success sound once")
	sound.last_played.erase("purchase")
	pending_asset = {"kind": "purchase", "item_id": "smg", "slot": "", "operation_id": "b".repeat(32)}
	fake.queue = [{"ok": true, "payload": valid}]
	await retry_asset()
	_check(purchases.call() == 1, "a repeated confirmation of the same operation is not played again")
	pending_asset = {"kind": "purchase", "item_id": "smg", "slot": "", "operation_id": "c".repeat(32)}
	fake.queue = [{"ok": true, "payload": {"state": {"credits": -1}}}]
	await retry_asset()
	_check(purchases.call() == 1, "a malformed success response plays nothing")
	pending_asset = {"kind": "select", "item_id": "smg", "slot": "primary", "operation_id": "d".repeat(32)}
	fake.queue = [{"ok": true, "payload": valid}]
	await retry_asset()
	_check(purchases.call() == 1, "saving a default loadout is not a purchase sound")
	fake.state = "IN_ROOM"
	world = ShooterWorld.new()
	_on_presentation_cue("hit", {"user_id": "sound_player"})
	var own_voice: Array = sound.voices.filter(func(v): return v.cue == "hit")
	_check(own_voice.size() == 1, "an in-room cue reaches the sound board")
	fake.state = "LOBBY"
	sound.last_played.clear()
	_on_presentation_cue("fire", {})
	_check(int(sound.played.get("fire", 0)) == 0, "cues arriving outside a room are ignored")
	world.free()
	sound.queue_free()
	fake.queue_free()
	await process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

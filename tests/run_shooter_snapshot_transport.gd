extends "res://examples/framework/client.gd"
## Application lifecycle regression. The companion network test covers real RPC.
const Shooter = preload("res://examples/shooter/game.gd")
const Codec = preload("res://examples/shooter/snapshot_codec.gd")
const Fixtures = preload("res://tests/test_shooter_snapshot_codec.gd")
var passed := 0
var failed := 0
var cues: Array = []

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _verify() -> void:
	client = AccountClient.new()
	world = Shooter.new()
	world.presentation_cue.connect(func(cue: String, _detail: Dictionary): cues.append(cue))
	var snapshot: Dictionary = Fixtures.new()._snapshot(8, 96)
	snapshot.tick = 30
	var packets := Codec.encode(snapshot, 1, 70)
	_check(packets.size() > 1, "fixture exercises fragmented semantic application")
	for index in packets.size() - 1:
		world.world_chunk(packets[index])
	_check(world.latest.is_empty() and cues.is_empty(), "partial frame changes neither world nor sound")
	world.world_chunk(packets[-1])
	_check(world.latest == snapshot, "complete frame atomically applies all players and fields")
	_check(cues.is_empty(), "initial snapshot does not replay historical sound")
	var changed: Dictionary = snapshot.duplicate(true)
	changed.players[0].hp = 60
	var newer := Codec.encode(changed, 2, 70)
	for packet in newer:
		world.world_chunk(packet)
	_check(world.latest == changed, "new serial can update an unchanged game tick")
	_check(cues.count("hit") == 1, "one confirmed damage transition produces one cue")
	for packet in newer:
		world.world_chunk(packet)
	_check(cues.count("hit") == 1, "replayed complete fragments do not repeat sound")
	for packet in packets:
		world.world_chunk(packet)
	_check(world.latest == changed, "old serial never rolls the applied world backwards")
	var incomplete := Codec.encode(snapshot, 3, 70)
	world.world_chunk(incomplete[0])
	_room_joined({})
	_check(world.latest == changed and not world._snapshot_decoder._frames.is_empty(), "join confirmation preserves a legitimate early snapshot and partial frame")
	world.advance_visual(0.02)
	world.set_local_aim("fixture", Vector2.RIGHT, true)
	_room_left()
	_check(world.latest.is_empty() and world._snapshot_decoder._frames.is_empty(), "room-left path clears world and fragment cache")
	_check(world.render_tracks.is_empty() and world.aim_tracks.is_empty() and world.visual_shots.is_empty(), "room-left path clears presentation tracks and shots")
	_check(world._local_aim_user == "" and world._position_intervals.is_empty(), "room-left path clears local aim and cadence")
	_check(world.snapshot_diagnostics() == {"interval_ms": -1, "age_ms": -1}, "between rooms reception diagnostics are unknown")
	var next_room: Dictionary = snapshot.duplicate(true)
	next_room.tick = 1
	for packet in Codec.encode(next_room, 1, 80):
		world.world_chunk(packet)
	_check(world.latest == next_room, "new room can use lower tick and serial with new stream")
	world.world_chunk(Codec.encode(snapshot, 4, 70)[0])
	_check(world._snapshot_decoder._frames.is_empty(), "previous room stream cannot contaminate an established new room")
	_reset_session()
	_check(world.latest.is_empty() and world._snapshot_decoder._stream_id == 0, "session reset releases the previous stream binding")
	world.free()
	world = null
	_reset_world_network_state()
	_check(true, "reset before world creation is safe")
	client.free()
	print("SHOOTER_SNAPSHOT_TRANSPORT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

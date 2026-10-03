extends RefCounted

const Rules = preload("res://examples/racing/race_rules.gd")
var passed := 0
var failed := 0


func run() -> Dictionary:
	_isolation()
	_configuration()
	_practice_configuration()
	_practice_countdown()
	_practice_order_and_result()
	_practice_departures()
	_roster()
	_countdown()
	_order_and_laps()
	_ranking()
	_departures()
	_authority_and_copies()
	_eight_player_race()
	return {"passed": passed, "failed": failed}


func _isolation() -> void:
	var isolated_root := OS.get_environment("RACING_RULES_ISOLATION").replace("\\", "/").trim_suffix("/")
	check(not isolated_root.is_empty() and isolated_root.begins_with("F:/"), "test isolation is explicitly on F drive")
	check(ProjectSettings.globalize_path("res://").replace("\\", "/").begins_with(isolated_root + "/project/"), "only the staged minimal project is loaded")
	check(OS.get_user_data_dir().replace("\\", "/").begins_with(isolated_root + "/"), "Godot user data resolves inside isolation")
	for name in ["HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"]:
		check(OS.get_environment(name).replace("\\", "/").begins_with(isolated_root + "/"), "isolated child environment " + name)
	check(not FileAccess.file_exists("res://host/main.gd") and not DirAccess.dir_exists_absolute("res://sdk"), "no host or SDK exists in the test project")


func _configuration() -> void:
	var race = Rules.new()
	check(race.snapshot().config == {"mode": "race", "checkpoint_count": 3, "laps": 3, "countdown_ms": 3000}, "bounded defaults")
	check(race.snapshot().min_players == 2 and race.snapshot().max_players == 8, "default race retains two-to-eight roster")
	for options in [null, [], {"laps": 0}, {"laps": 100}, {"laps": 1.0}, {"laps": true}, {"laps": "1"}, {"checkpoint_count": 1}, {"checkpoint_count": 65}, {"countdown_ms": 0}, {"countdown_ms": 60001}, {"countdown_ms": NAN}, {"countdown_ms": INF}, {"max_players": 9}, {"finish_time_ms": 1}, {"laps": 2, "rank": 1}]:
		var before: Dictionary = race.snapshot()
		expect(race.configure(options), "INVALID_CONFIG", "invalid config rejected")
		check(race.snapshot() == before, "invalid config leaves state unchanged")
	expect(race.configure({"checkpoint_count": 64, "laps": 99, "countdown_ms": 60000}), "OK", "upper config boundaries accepted")
	expect(race.configure({"checkpoint_count": 2, "laps": 1, "countdown_ms": 1}), "OK", "lower config boundaries accepted")
	race.admit("account-a")
	expect(race.configure({"laps": 2}), "CONFIG_LOCKED", "configuration freezes on admission")


func _practice_configuration() -> void:
	var race = Rules.new()
	for mode in [null, 0, 1.0, true, [], {}, &"practice", "", "Practice", " practice", "practice ", "solo"]:
		var before: Dictionary = race.snapshot()
		expect(race.configure({"mode": mode}), "INVALID_CONFIG", "mode accepts only exact legal Strings")
		check(race.snapshot() == before, "invalid mode leaves default race intact")
	expect(race.configure({"mode": "practice", "laps": 1.0}), "INVALID_CONFIG", "practice retains integer-only lap rule")
	check(race.snapshot().config.mode == "race", "mixed invalid config cannot partially opt into practice")
	expect(race.configure({"mode": "practice"}), "OK", "explicit practice mode accepted")
	check(race.snapshot().min_players == 1 and race.snapshot().max_players == 1, "practice exposes exactly one seat")
	check(race.snapshot().config.laps == 3 and race.snapshot().config.checkpoint_count == 3, "mode alone preserves existing lap and checkpoint defaults")
	for options in [{"laps": true}, {"checkpoint_count": "3"}, {"countdown_ms": 1.0}, {"mode": "race", "countdown_ms": 0}, {"min_players": 0}]:
		var before: Dictionary = race.snapshot()
		expect(race.configure(options), "INVALID_CONFIG", "practice keeps strict numeric and unknown-key validation")
		check(race.snapshot() == before, "invalid mixed config cannot switch mode or change limits")
	expect(race.configure({"mode": "race"}), "OK", "explicit race mode accepted before admission")
	check(race.snapshot().min_players == 2 and race.snapshot().max_players == 8, "switching back restores race roster limits")
	race.admit("solo")
	expect(race.start_countdown(), "NOT_ENOUGH_PLAYERS", "explicit race still needs two entrants")
	expect(race.configure({"mode": "practice"}), "CONFIG_LOCKED", "admission prevents lowering race threshold")
	var practice = _solo(1, 3, 3000, false)
	expect(practice.admit("solo"), "ALREADY_JOINED", "practice duplicate identity cannot replace sole seat")
	expect(practice.admit("second"), "RACE_FULL", "practice rejects second entrant")
	check(practice.snapshot().players.size() == 1, "second entrant rejection preserves sole player")
	expect(practice.configure({"mode": "race"}), "CONFIG_LOCKED", "practice mode freezes on admission")
	var copy: Dictionary = practice.snapshot()
	copy.config.mode = "race"
	check(practice.snapshot().max_players == 1 and practice.snapshot().config.mode == "practice", "snapshot mutation cannot expand practice capacity")


func _practice_countdown() -> void:
	var empty = Rules.new()
	empty.configure({"mode": "practice"})
	expect(empty.start_countdown(), "NOT_ENOUGH_PLAYERS", "empty practice cannot start")
	var practice = _solo(1, 3, 3000, false)
	expect(practice.start_countdown(), "OK", "one real practice entrant starts countdown")
	expect(practice.admit("late"), "ROSTER_LOCKED", "practice countdown locks roster")
	expect(practice.observe_checkpoint("solo", 0, 1), "BAD_PHASE", "practice cannot progress before start")
	practice.advance(2999)
	check(practice.snapshot().phase == "countdown" and practice.snapshot().countdown_remaining_ms == 1, "practice retains exact countdown boundary")
	check(practice.snapshot().race_elapsed_ms == 0 and practice.snapshot().players.solo.next_checkpoint == 0, "countdown earns neither racing time nor progress")
	practice.advance(1)
	check(practice.snapshot().phase == "racing" and practice.snapshot().race_elapsed_ms == 0, "practice clock starts at countdown end")
	expect(practice.observe_checkpoint("solo", 0, 1), "OK", "practice first gate accepted at exact start")
	var overshoot = _solo(1, 3, 3000, false)
	overshoot.start_countdown()
	overshoot.advance(3123)
	check(overshoot.snapshot().race_elapsed_ms == 123, "practice preserves countdown overshoot")
	var cancelled = _solo(1, 3, 3000, false)
	cancelled.start_countdown()
	cancelled.advance(2500)
	expect(cancelled.leave("solo"), "OK", "sole practice entrant may leave countdown")
	check(cancelled.snapshot().phase == "waiting" and cancelled.snapshot().players.is_empty() and cancelled.snapshot().race_elapsed_ms == 0, "empty practice cancels countdown and clears clock")
	expect(cancelled.advance(500), "BAD_PHASE", "cancelled practice cannot reach start on old clock")
	expect(cancelled.start_countdown(), "NOT_ENOUGH_PLAYERS", "cancelled empty practice still needs entrant")
	expect(cancelled.admit("replacement"), "OK", "cancelled practice seat can be refilled")
	expect(cancelled.start_countdown(), "OK", "replacement explicitly starts fresh countdown")
	check(cancelled.snapshot().countdown_remaining_ms == 3000, "practice replacement gets full countdown")
	cancelled.advance(3000)
	check(cancelled.snapshot().race_elapsed_ms == 0 and cancelled.snapshot().players.replacement.status == "racing", "replacement starts with clean racing time")


func _practice_order_and_result() -> void:
	var practice = _solo(1, 3, 1)
	expect(practice.observe_checkpoint("solo", 2, 1), "WRONG_CHECKPOINT", "practice cannot skip straight to finish")
	expect(practice.observe_checkpoint("solo", 0, 2), "OK", "practice first gate")
	expect(practice.observe_checkpoint("solo", 2, 3), "WRONG_CHECKPOINT", "practice cannot skip middle gate")
	check(practice.snapshot().players.solo.completed_laps == 0 and practice.results().is_empty(), "wrong order earns no practice lap or result")
	practice.advance(125)
	expect(practice.observe_checkpoint("solo", 1, 4), "OK", "practice middle gate")
	expect(practice.observe_checkpoint("solo", 2, 3), "STALE_EVENT", "practice cannot replay earlier rejected finish observation")
	practice.advance(331)
	expect(practice.observe_checkpoint("solo", 2, 5), "OK", "practice ordered final gate")
	check(practice.snapshot().phase == "finished", "sole practice finisher resolves session")
	check(practice.results() == [{"user_id": "solo", "rank": 1, "completed_laps": 1, "finish_time_ms": 456}], "practice result uses real identity and elapsed racing time")
	var finished: Dictionary = practice.snapshot()
	expect(practice.observe_checkpoint("solo", 0, 6), "BAD_PHASE", "practice cannot score duplicate completion")
	expect(practice.advance(100), "BAD_PHASE", "practice result time freezes after finish")
	check(practice.snapshot() == finished, "practice terminal rejection preserves result")
	var laps = _solo(2, 2, 1)
	_lap(laps, "solo", 2, 1)
	check(laps.snapshot().phase == "racing" and laps.snapshot().players.solo.completed_laps == 1 and laps.results().is_empty(), "practice respects configured multiple laps")
	laps.advance(99)
	_lap(laps, "solo", 2, 3)
	check(laps.results() == [{"user_id": "solo", "rank": 1, "completed_laps": 2, "finish_time_ms": 99}], "practice completes only required ordered laps")


func _practice_departures() -> void:
	var practice = _solo(1, 3, 1)
	practice.observe_checkpoint("solo", 0, 1)
	expect(practice.leave("solo"), "OK", "practice racer can withdraw")
	check(practice.snapshot().phase == "finished" and practice.results().is_empty(), "practice withdrawal closes without invented winner")
	var player: Dictionary = practice.snapshot().players.solo
	check(player.status == "dnf" and not player.connected and player.rank == 0 and player.finish_time_ms == -1 and player.next_checkpoint == 1, "practice DNF retains partial progress without finish")
	expect(practice.leave("solo"), "ALREADY_LEFT", "practice withdrawal cannot apply twice")
	var winner = _solo(1, 2, 1)
	winner.advance(42)
	_lap(winner, "solo", 2, 1)
	var result: Array = winner.results()
	expect(winner.leave("solo"), "OK", "practice winner can leave finished session")
	check(winner.results() == result and winner.snapshot().players.solo.status == "finished", "practice winner departure retains exact result")
	var fresh = _solo(1, 2, 1)
	check(fresh.snapshot().race_elapsed_ms == 0 and fresh.snapshot().players.solo.completed_laps == 0 and fresh.results().is_empty(), "new practice instance restarts with no carried progress or result")


func _roster() -> void:
	var race = Rules.new()
	for identity in [null, 1, true, "", " ", " a", "a ", "x".repeat(129), {"user_id": "a", "rank": 1}]:
		expect(race.admit(identity), "INVALID_PLAYER", "malformed stable identity rejected")
	check(race.snapshot().players.is_empty(), "invalid admissions cannot reserve seats")
	expect(race.start_countdown(), "NOT_ENOUGH_PLAYERS", "zero players cannot start")
	race.admit("account-0")
	expect(race.start_countdown(), "NOT_ENOUGH_PLAYERS", "one player cannot start")
	for index in range(1, 8):
		expect(race.admit("account-" + str(index)), "OK", "admit within eight-player capacity")
	expect(race.admit("account-0"), "ALREADY_JOINED", "duplicate cannot replace occupied seat")
	expect(race.admit("ninth"), "RACE_FULL", "ninth player rejected")
	check(race.snapshot().players.size() == 8, "capacity remains eight")
	expect(race.leave("account-3"), "OK", "waiting departure releases seat")
	expect(race.admit("replacement"), "OK", "waiting seat can be refilled")
	race.start_countdown()
	expect(race.admit("late"), "ROSTER_LOCKED", "countdown locks roster")
	expect(race.leave("replacement"), "OK", "countdown departure removes not-started entrant")
	check(race.snapshot().phase == "countdown" and race.snapshot().players.size() == 7, "countdown continues with at least two")
	expect(race.admit("replacement"), "ROSTER_LOCKED", "cannot fill vacant countdown seat")
	race.advance(3000)
	expect(race.admit("late"), "ROSTER_LOCKED", "race locks roster")
	expect(race.configure({}), "CONFIG_LOCKED", "running race cannot reconfigure")


func _countdown() -> void:
	var race = _pair(1, 3, 3000, false)
	expect(race.observe_checkpoint("a", 0, 1), "BAD_PHASE", "waiting checkpoint rejected")
	expect(race.advance(1), "BAD_PHASE", "waiting clock cannot advance")
	expect(race.start_countdown(), "OK", "explicit start")
	expect(race.start_countdown(), "BAD_PHASE", "cannot restart live countdown")
	race.advance(2999)
	check(race.snapshot().phase == "countdown" and race.snapshot().countdown_remaining_ms == 1, "one millisecond before start")
	expect(race.observe_checkpoint("a", 0, 1), "BAD_PHASE", "early crossing gives no progress")
	check(race.snapshot().players.a.next_checkpoint == 0, "countdown never advances a lap")
	for delta in [-1, 0.5, "1", true, NAN, INF, 2147483648]:
		var before: Dictionary = race.snapshot()
		expect(race.advance(delta), "INVALID_TIME", "invalid server time refused")
		check(race.snapshot() == before, "invalid time cannot move start")
	expect(race.advance(0), "OK", "zero step is a no-op")
	race.advance(1)
	check(race.snapshot().phase == "racing" and race.snapshot().race_elapsed_ms == 0, "exact start boundary")
	expect(race.observe_checkpoint("a", 0, 1), "OK", "crossing allowed at start boundary")
	var overshoot = _pair(1, 3, 3000, false)
	overshoot.start_countdown()
	overshoot.advance(3123)
	check(overshoot.snapshot().race_elapsed_ms == 123, "large step preserves remainder after countdown")
	var boundary = _pair(1, 2, 1)
	boundary.advance(2147483646)
	check(boundary.snapshot().race_elapsed_ms == 2147483646, "largest cumulative clock is bounded without overflow")
	var saved: Dictionary = boundary.snapshot()
	expect(boundary.advance(1), "INVALID_TIME", "cumulative clock overflow rejected")
	check(boundary.snapshot() == saved, "overflow rejection leaves state unchanged")


func _order_and_laps() -> void:
	var race = _pair(2)
	for checkpoint in [-1, 3, 0.0, "0", true, NAN, INF]:
		expect(race.observe_checkpoint("a", checkpoint, 1), "INVALID_CHECKPOINT", "invalid checkpoint rejected")
	for sequence in [0, -1, 1.0, "1", true, NAN, 2147483648]:
		expect(race.observe_checkpoint("a", 0, sequence), "INVALID_SEQUENCE", "invalid server event sequence rejected")
	expect(race.observe_checkpoint("stranger", 0, 1), "UNKNOWN_PLAYER", "unknown player cannot progress")
	check(race.snapshot().players.a.last_event_sequence == 0, "malformed observations leave watermark intact")
	expect(race.observe_checkpoint("a", 1, 1), "WRONG_CHECKPOINT", "skip first checkpoint rejected")
	expect(race.observe_checkpoint("a", 0, 2), "OK", "first expected crossing accepted")
	expect(race.observe_checkpoint("a", 1, 1), "STALE_EVENT", "earlier rejected crossing cannot be replayed when expected")
	expect(race.observe_checkpoint("a", 0, 3), "WRONG_CHECKPOINT", "repeated physical checkpoint does not advance")
	expect(race.observe_checkpoint("a", 2, 4), "WRONG_CHECKPOINT", "skip intermediate checkpoint rejected")
	check(race.snapshot().players.a.completed_laps == 0 and race.snapshot().players.a.next_checkpoint == 1, "invalid order never awards a lap")
	expect(race.observe_checkpoint("a", 1, 5), "OK", "expected middle checkpoint")
	expect(race.observe_checkpoint("a", 2, 6), "OK", "last checkpoint completes first lap")
	check(race.snapshot().players.a.completed_laps == 1 and race.snapshot().players.a.next_checkpoint == 0 and race.results().is_empty(), "full lap resets order but not finish")
	expect(race.observe_checkpoint("a", 0, 2), "STALE_EVENT", "previous lap observation cannot start next lap")
	expect(race.observe_checkpoint("a", 2, 7), "WRONG_CHECKPOINT", "repeated finish line cannot award another lap")
	race.advance(456)
	for checkpoint in range(3):
		expect(race.observe_checkpoint("a", checkpoint, 8 + checkpoint), "OK", "second lap complete sequence")
	check(race.results() == [{"user_id": "a", "rank": 1, "completed_laps": 2, "finish_time_ms": 456}], "finish computed from exact required laps and server clock")
	var finished: Dictionary = race.snapshot()
	expect(race.observe_checkpoint("a", 0, 11), "PLAYER_INACTIVE", "finished player cannot score twice")
	check(race.snapshot() == finished, "duplicate completion leaves result immutable")
	check(race.snapshot().phase == "racing", "other racer keeps match active")


func _ranking() -> void:
	var race = _pair(1, 2)
	race.advance(250)
	_lap(race, "b", 2, 1)
	_lap(race, "a", 2, 1)
	check(race.results() == [
		{"user_id": "b", "rank": 1, "completed_laps": 1, "finish_time_ms": 250},
		{"user_id": "a", "rank": 2, "completed_laps": 1, "finish_time_ms": 250},
	], "same-millisecond finish uses serialized server crossing order, not admission order")
	check(race.snapshot().phase == "finished", "all finished closes race")
	var before: Dictionary = race.snapshot()
	expect(race.advance(100), "BAD_PHASE", "closed race clock freezes")
	expect(race.observe_checkpoint("b", 1, 3), "BAD_PHASE", "closed race cannot finish twice")
	expect(race.start_countdown(), "BAD_PHASE", "same race object cannot restart")
	expect(race.admit("c"), "ROSTER_LOCKED", "finished race cannot accept player")
	check(race.snapshot() == before, "terminal rejection is inert")
	race.leave("b")
	check(race.results() == before.finishers and not race.snapshot().players.b.connected, "winner leaving retains rank and time")
	var staggered = _pair(1, 2)
	staggered.advance(100)
	_lap(staggered, "a", 2, 1)
	staggered.advance(99)
	_lap(staggered, "b", 2, 1)
	check(staggered.results()[0].finish_time_ms == 100 and staggered.results()[1].finish_time_ms == 199, "separate finishes retain their own clock sample")


func _departures() -> void:
	var race = _pair(1, 3, 3000, false)
	expect(race.leave("stranger"), "UNKNOWN_PLAYER", "unknown leave rejected")
	race.start_countdown()
	race.advance(2500)
	race.leave("b")
	check(race.snapshot().phase == "waiting" and race.snapshot().players.size() == 1, "countdown cancels below minimum")
	expect(race.advance(1000), "BAD_PHASE", "cancelled countdown cannot start alone")
	race.admit("c")
	race.start_countdown()
	check(race.snapshot().countdown_remaining_ms == 3000, "replacement start requires full fresh countdown")
	race.advance(3000)
	race.observe_checkpoint("a", 0, 1)
	expect(race.leave("a"), "OK", "racer withdraws after partial progress")
	var dnf: Dictionary = race.snapshot().players.a
	check(dnf.status == "dnf" and dnf.rank == 0 and dnf.finish_time_ms == -1 and dnf.next_checkpoint == 1, "DNF preserves progress without invented finish or rank")
	expect(race.leave("a"), "ALREADY_LEFT", "withdrawal is not applied twice")
	expect(race.observe_checkpoint("a", 1, 2), "PLAYER_INACTIVE", "withdrawn player cannot progress")
	expect(race.admit("a"), "ALREADY_JOINED", "DNF cannot rejoin this race")
	expect(race.admit("d"), "ROSTER_LOCKED", "no replacement during race")
	check(race.snapshot().phase == "racing", "one active player may continue after start")
	race.advance(123)
	_lap(race, "c", 3, 1)
	check(race.snapshot().phase == "finished" and race.results().size() == 1 and race.results()[0].rank == 1, "DNF plus finisher closes without ranking DNF")
	var all_left = _pair(1)
	all_left.leave("a")
	all_left.leave("b")
	check(all_left.snapshot().phase == "finished" and all_left.results().is_empty(), "all DNF closes without phantom winner")
	var winner_left = _pair(1, 2)
	_lap(winner_left, "a", 2, 1)
	var winner_result: Array = winner_left.results()
	winner_left.leave("a")
	check(winner_left.snapshot().phase == "racing" and winner_left.snapshot().players.a.status == "finished", "winner exit during race never becomes DNF")
	winner_left.leave("b")
	check(winner_left.snapshot().phase == "finished" and winner_left.results() == winner_result, "last unfinished departure preserves winner")
	var empty = _pair(1, 2, 1, false)
	empty.start_countdown()
	empty.leave("a")
	empty.leave("b")
	check(empty.snapshot().phase == "waiting" and empty.snapshot().players.is_empty(), "empty pre-start room is waiting with no result")


func _authority_and_copies() -> void:
	var options := {"laps": 1, "checkpoint_count": 2, "countdown_ms": 1}
	var race = Rules.new()
	race.configure(options)
	options.laps = 0
	check(race.snapshot().config.laps == 1, "caller cannot mutate stored configuration")
	race.admit("a")
	race.admit("b")
	race.start_countdown()
	race.advance(1)
	var forged := {"user_id": "a", "rank": 1, "completed_laps": 99, "finish_time_ms": 0}
	var before: Dictionary = race.snapshot()
	expect(race.observe_checkpoint("a", forged, 1), "INVALID_CHECKPOINT", "client result dictionary cannot serve as checkpoint")
	expect(race.observe_checkpoint(forged, 0, 1), "UNKNOWN_PLAYER", "result cannot serve as authenticated identity")
	check(race.snapshot() == before, "injected result never enters state")
	var copy: Dictionary = race.snapshot()
	copy.players.a.completed_laps = 99
	copy.players.a.rank = 1
	copy.config.laps = 0
	copy.finishers.append(forged)
	check(race.snapshot() == before, "snapshot nested collections cannot mutate authoritative state")
	check(not race.has_method("submit_result") and not race.has_method("set_result"), "no direct result submission or setter")
	_lap(race, "a", 2, 1)
	var result_copy: Array = race.results()
	result_copy[0].rank = 8
	result_copy[0].finish_time_ms = -100
	result_copy.append(forged)
	check(race.results().size() == 1 and race.results()[0].rank == 1 and race.results()[0].finish_time_ms == 0, "result rows are deep copies")


func _eight_player_race() -> void:
	var race = Rules.new()
	race.configure({"laps": 3, "checkpoint_count": 4, "countdown_ms": 10})
	for index in range(8):
		race.admit("p" + str(index))
	race.start_countdown()
	race.advance(10)
	# Interleaved progress, two withdrawals, six finishes in reverse roster order.
	for lap_index in range(3):
		for checkpoint in range(4):
			race.advance(10)
			for index in range(7, -1, -1):
				if index == 2 or index == 5:
					if lap_index == 0 and checkpoint == 0:
						race.leave("p" + str(index))
					continue
				expect(race.observe_checkpoint("p" + str(index), checkpoint, lap_index * 4 + checkpoint + 1), "OK", "interleaved eight-player race observation")
	var expected_ids := ["p7", "p6", "p4", "p3", "p1", "p0"]
	var finishers: Array = race.results()
	check(race.snapshot().phase == "finished" and finishers.size() == 6, "all eight entrants resolve as six finishes and two DNF")
	for index in range(finishers.size()):
		check(finishers[index] == {"user_id": expected_ids[index], "rank": index + 1, "completed_laps": 3, "finish_time_ms": 120}, "contiguous final ranking from complete server event trace")


func _solo(laps := 1, checkpoints := 3, countdown_ms := 3000, start := true):
	var practice = Rules.new()
	practice.configure({"mode": "practice", "laps": laps, "checkpoint_count": checkpoints, "countdown_ms": countdown_ms})
	practice.admit("solo")
	if start:
		practice.start_countdown()
		practice.advance(countdown_ms)
	return practice


func _pair(laps := 1, checkpoints := 3, countdown_ms := 3000, start := true):
	var race = Rules.new()
	race.configure({"laps": laps, "checkpoint_count": checkpoints, "countdown_ms": countdown_ms})
	race.admit("a")
	race.admit("b")
	if start:
		race.start_countdown()
		race.advance(countdown_ms)
	return race


func _lap(race, user_id: String, checkpoints: int, sequence_start: int) -> void:
	for checkpoint in range(checkpoints):
		expect(race.observe_checkpoint(user_id, checkpoint, sequence_start + checkpoint), "OK", "ordered lap for " + user_id)


func expect(result: Dictionary, code: String, label: String) -> void:
	check(result == {"ok": code == "OK", "code": code}, label + " [" + code + "]")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("RACING_RULES_FAIL: " + label)

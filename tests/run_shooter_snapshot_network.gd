extends SceneTree
## Real loopback ENet/RPC regression, optionally with actual ENet DTLS.
## One process with independent multiplayer branches; no account/public-network claim.
const Shooter = preload("res://examples/shooter/game.gd")
const Codec = preload("res://examples/shooter/snapshot_codec.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
const Sender = preload("res://examples/shooter/snapshot_sender.gd")
const CLIENTS := 8
var passed := 0
var failed := 0
var endpoints: Array = []
var clients: Array = []
var authority
var listening_port := 0
var checks: Array = []
var evidence := ""
var observed: Array = []
var reception: Array = []
var progress: Array = []
var transport_samples: Array = []
var stage_name := ""
var issued: Dictionary = {}
var ordinary_players: Dictionary = {}
var final_large: Dictionary = {}
var stage_started := 0
var stage_published := 0
var stage_duration := 0
var stage_convergence := 0
var stage_publication_ms: Array = []
var stage_minimum_tick := 0
var capacity_only := false
var process_reception: Array = []
var dtls := false
var dtls_evidence := {"server_setup": null, "client_setup": [], "handshakes": [], "certificate_sha256": ""}
var poll_timing: Dictionary = {}
var slow_polls: Array = []
var decoder_samples: Array = []
var next_decoder_sample := 0
var poll_cursor := 0
var fixed_poll_order := false

func _initialize() -> void:
	multiplayer_poll = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			evidence = argument.trim_prefix("--evidence=")
		if argument == "--capacity-only":
			capacity_only = true
		if argument == "--dtls":
			dtls = true
		if argument == "--fixed-poll-order":
			fixed_poll_order = true
	_run.call_deferred()

func _run() -> void:
	var dependency = Shooter.new()
	var ready: bool = dependency.has_method("world_chunk") and dependency.has_method("flush_snapshot_transport")
	dependency.free()
	if not _require(ready, "production world_chunk and explicit paced flush dependencies are present"):
		_finish()
		return
	if not await _open_network():
		await _close_network()
		_finish()
		return
	ordinary_players = authority.players.duplicate(true)
	await _production_process_frames()
	await _eight_player_frames()
	await _worst_legal_snapshot()
	if not capacity_only:
		await _loss_and_bad_packet_recovery()
		await _slow_scheduler_recovery()
	await _close_network()
	_finish()

func _add_endpoint(label: String, peer: ENetMultiplayerPeer, is_server: bool) -> Dictionary:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	# Production room_runtime disables relay; clients communicate with the
	# authority, rather than adding relayed peers to this capacity fixture.
	if is_server:
		api.server_relay = false
	set_multiplayer(api, branch.get_path())
	api.multiplayer_peer = peer
	var world = Shooter.new()
	world.name = "GameWorld"
	world.server = is_server
	world.set_process(false)
	branch.add_child(world)
	world.set_process(false)
	var endpoint := {"branch": branch, "api": api, "peer": peer, "world": world}
	endpoints.append(endpoint)
	return endpoint

func _open_network() -> bool:
	var server_peer := ENetMultiplayerPeer.new()
	server_peer.set_bind_ip("127.0.0.1")
	if not _require(server_peer.create_server(0, CLIENTS, 2) == OK, "bind loopback-only real ENet server on an ephemeral UDP port"):
		return false
	listening_port = server_peer.host.get_local_port()
	_check(listening_port > 0, "ephemeral UDP port was assigned")
	var security: Dictionary = {}
	if dtls:
		# Driver supplies a new private evidence folder. Never use an installed CA,
		# shared host certificate, account fixture, or a flag as handshake evidence.
		if not _require(evidence != "", "DTLS mode has an isolated evidence directory"):
			server_peer.close()
			return false
		security = Secure.create_local_certificate(evidence.get_base_dir().path_join("dtls-security"))
		if not _require(not security.is_empty(), "DTLS generates its own local certificate and private key"):
			server_peer.close()
			return false
		dtls_evidence.certificate_sha256 = FileAccess.get_sha256(security.certificate)
		var server_tls := Secure.server_options(security)
		if not _require(server_tls != null, "DTLS server loads actual certificate and private key"):
			server_peer.close()
			return false
		var setup: int = server_peer.host.dtls_server_setup(server_tls)
		dtls_evidence.server_setup = setup
		if not _require(setup == OK, "actual ENet DTLS server setup returns OK"):
			server_peer.close()
			return false
	var endpoint := _add_endpoint("SnapshotServer", server_peer, true)
	authority = endpoint.world
	for index in CLIENTS:
		var client_peer := ENetMultiplayerPeer.new()
		if not _require(client_peer.create_client("127.0.0.1", listening_port, 2) == OK, "create real ENet client %d" % index):
			client_peer.close()
			return false
		if dtls:
			var client_tls := Secure.client_options(security.certificate)
			if not _require(client_tls != null, "DTLS client %d loads the test certificate as its trust anchor" % index):
				client_peer.close()
				return false
			var setup: int = client_peer.host.dtls_client_setup(security.hostname, client_tls)
			dtls_evidence.client_setup.append({"client": index, "code": setup})
			if not _require(setup == OK, "actual ENet DTLS client %d setup returns OK" % index):
				client_peer.close()
				return false
		clients.append(_add_endpoint("SnapshotClient%d" % index, client_peer, false))
	var handshake_started := Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_poll_all()
		if _connected_count() == CLIENTS and endpoint.api.get_peers().size() == CLIENTS:
			break
		await process_frame
	if not _require(_connected_count() == CLIENTS and endpoint.api.get_peers().size() == CLIENTS, "all eight actual %s handshakes reach the authority" % ("ENet DTLS" if dtls else "ENet")):
		return false
	for index in CLIENTS:
		var peer_id: int = clients[index].api.get_unique_id()
		_check(peer_id > 1, "client %d has its actual ENet peer ID" % index)
		if dtls:
			dtls_evidence.handshakes.append({"client": index, "peer_id": peer_id, "status": clients[index].peer.get_connection_status(), "authority_observed": peer_id in endpoint.api.get_peers(), "observed_after_ms": Time.get_ticks_msec() - handshake_started})
		authority.admit({"user_id": "net-player-%02d" % index, "display_name": "Net %d" % index}, peer_id)
	var actual_peers: Array = []
	for endpoint_row in clients:
		actual_peers.append(endpoint_row.api.get_unique_id())
	var admitted_peers: Array = authority.peers.keys()
	actual_peers.sort()
	admitted_peers.sort()
	return _require(authority.players.size() == CLIENTS and admitted_peers == actual_peers, "authority admits exactly the eight actual peers and synthetic identities")

func _connected_count() -> int:
	var count := 0
	for endpoint in clients:
		if endpoint.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			count += 1
	return count

func _poll_all(flush: bool = true) -> void:
	# The test disables GameWorld._process; every network cycle explicitly advances
	# the production sender, including during a held, repeatedly published state.
	if flush and authority != null and authority.has_method("flush_snapshot_transport"):
		var before := Time.get_ticks_usec()
		authority.flush_snapshot_transport(Time.get_ticks_msec())
		transport_samples.append(Time.get_ticks_usec() - before)
	# Nine branches share this process. A maximal state's schema validation can
	# take tens of ms per receiving branch. Rotate client priority so the same
	# endpoint is not always last behind all seven other validators. Packet
	# budgets, decoder TTL, duration, client count and convergence gates stay put.
	for offset in endpoints.size():
		var endpoint: Dictionary = endpoints[0] if offset == 0 else endpoints[1 + ((offset - 1 + poll_cursor) % clients.size())]
		if endpoint.api.has_multiplayer_peer():
			var before := Time.get_ticks_usec()
			var error: int = endpoint.api.poll()
			var elapsed := Time.get_ticks_usec() - before
			var label: String = endpoint.branch.name
			if not poll_timing.has(label):
				poll_timing[label] = {"calls": 0, "total_us": 0, "max_us": 0}
			var timing: Dictionary = poll_timing[label]
			timing.calls += 1
			timing.total_us += elapsed
			timing.max_us = maxi(timing.max_us, elapsed)
			if elapsed >= 20000 and slow_polls.size() < 256:
				slow_polls.append({"endpoint": label, "group": stage_name, "at_ms": Time.get_ticks_msec(), "duration_us": elapsed})
			if error != OK:
				_check(false, "real SceneMultiplayer poll returns OK")
	if not fixed_poll_order and not clients.is_empty():
		poll_cursor = (poll_cursor + 1) % clients.size()
	_sample_progress()
	_sample_decoders()

func _sample_decoders() -> void:
	var now := Time.get_ticks_msec()
	if stage_name == "" or now < next_decoder_sample or decoder_samples.size() >= 1600:
		return
	next_decoder_sample = now + 250
	for index in clients.size():
		var decoder = clients[index].world.get("_snapshot_decoder")
		var partial: Array = []
		for serial in decoder.get("_frames"):
			var frame: Dictionary = decoder.get("_frames")[serial]
			partial.append({"serial": serial, "received": frame.parts.size(), "expected": frame.header.count, "age_ms": now - int(frame.born), "ttl_ms": Codec.frame_ttl_ms(int(frame.header.count))})
		decoder_samples.append({"group": stage_name, "client": index, "at_ms": now, "accepted_serial": decoder.get("_accepted_serial"), "retired_serial": decoder.get("_retired_serial"), "partial": partial})

func _sample_progress() -> void:
	while progress.size() < clients.size():
		progress.append({"ticks": [], "serials": [], "arrival_ms": [], "valid": true, "windows": []})
	for index in clients.size():
		var latest: Dictionary = clients[index].world.latest
		if latest.is_empty():
			continue
		var row: Dictionary = progress[index]
		var tick := int(latest.get("tick", -1))
		var serial := int(clients[index].world.get("_snapshot_decoder").get("_accepted_serial"))
		# Ignore already-complete frames from before this stage's first publication.
		if stage_name == "" or tick < stage_minimum_tick:
			continue
		if not issued.has(tick):
			row.valid = false
			continue
		if not row.ticks.is_empty() and tick < int(row.ticks[-1]):
			row.valid = false
		if not row.serials.is_empty() and serial < int(row.serials[-1]):
			row.valid = false
		if tick > authority.tick:
			row.valid = false
		if not row.serials.is_empty() and serial == int(row.serials[-1]):
			continue
		if latest != issued[tick] or _ids(latest) != _ids(issued[tick]):
			row.valid = false
		if row.ticks.is_empty() or tick != int(row.ticks[-1]):
			row.ticks.append(tick)
		if row.serials.is_empty() or serial != int(row.serials[-1]):
			row.serials.append(serial)
			row.arrival_ms.append(Time.get_ticks_msec())

func _publish_for(milliseconds: int, advance: bool, windows: bool = false) -> Dictionary:
	var started := Time.get_ticks_msec()
	var until := started + milliseconds
	var next := started
	var window_until := started + 1000
	var window_counts: Array = []
	for index in CLIENTS:
		window_counts.append(progress[index].ticks.size())
	var value: Dictionary = {}
	while Time.get_ticks_msec() < until:
		if Time.get_ticks_msec() >= next:
			if advance:
				authority.advance(Time.get_ticks_msec())
			else:
				# Keep all 192 legal shots; advance() would expire them and silently
				# lower the maximum business state that this capacity gate tests.
				authority.tick += 1
			value = authority.state_snapshot()
			issued[authority.tick] = value
			authority._publish()
			stage_published += 1
			stage_publication_ms.append(Time.get_ticks_msec())
			next += 50
		_poll_all()
		if windows and Time.get_ticks_msec() >= window_until:
			_check_window(window_counts)
			window_until += 1000
		await process_frame
	if windows and window_until <= until:
		_check_window(window_counts)
	stage_duration = Time.get_ticks_msec() - started
	return value

func _check_window(counts: Array) -> void:
	for index in CLIENTS:
		var advanced: bool = progress[index].ticks.size() > int(counts[index])
		progress[index].windows.append(advanced)
		_check(advanced, "client %d progresses in ordinary one-second window %d" % [index, progress[index].windows.size()])
		counts[index] = progress[index].ticks.size()

func _ids(value: Dictionary) -> Array:
	var result: Array = []
	for player in value.get("players", []):
		result.append(player.get("user_id", ""))
	result.sort()
	return result

func _begin_stage(label: String) -> void:
	stage_name = label
	stage_minimum_tick = authority.tick + 1
	stage_started = Time.get_ticks_msec()
	stage_published = 0
	stage_duration = 0
	stage_convergence = 0
	stage_publication_ms.clear()
	issued.clear()
	progress.clear()
	for index in CLIENTS:
		progress.append({"ticks": [], "serials": [], "arrival_ms": [], "valid": true, "windows": []})

func _finish_stage(value: Dictionary, extra: Dictionary = {}) -> void:
	var summary := {"group": stage_name, "duration_ms": stage_duration, "period_ms": 50, "published": stage_published, "publication_ms": stage_publication_ms.duplicate(), "convergence_ms": stage_convergence}
	summary.network_statistics = _network_statistics()
	for key in extra:
		summary[key] = extra[key]
	for index in CLIENTS:
		var row: Dictionary = progress[index].duplicate(true)
		row.group = stage_name
		row.client = index
		row.complete = clients[index].world.latest == value
		row.identity_set = _ids(clients[index].world.latest)
		row.final_tick = int(clients[index].world.latest.get("tick", -1))
		_check(row.valid and row.complete and not row.serials.is_empty(), "client %d accepts only complete monotonic %s states with exact fields and identities" % [index, stage_name])
		reception.append(row)
		print("INFO group=", stage_name, " client=", index, " complete_frames=", row.serials.size(), " final_tick=", row.final_tick, " complete=", row.complete)
	observed.append(summary)
	stage_name = ""

func _network_statistics() -> Array:
	var rows: Array = []
	for endpoint in endpoints:
		var peers: Array = []
		# SceneMultiplayer's peer list can include relayed peers in older runs;
		# only physical ENet peers own channel/throttle/RTT statistics.
		for peer in endpoint.peer.host.get_peers():
			peers.append({"remote_port": peer.get_remote_port(), "channels": peer.get_channels(), "state": peer.get_state(), "throttle": peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), "throttle_limit": peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT), "rtt_ms": peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)})
		rows.append({"endpoint": str(endpoint.branch.name), "peers": peers, "sent_udp_packets": endpoint.peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS), "received_udp_packets": endpoint.peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)})
	return rows

func _converge(value: Dictionary) -> bool:
	# Unreliable delivery never promises a particular final serial. Keep publishing
	# the same terminal state with new serials within the original five-second gate.
	var started := Time.get_ticks_msec()
	var deadline := started + 5000
	var next := started
	var seen: Array = []
	for index in CLIENTS:
		seen.append(false)
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next:
			authority._publish()
			stage_published += 1
			next += 50
		_poll_all()
		var complete := Time.get_ticks_msec() - started >= 150
		for index in CLIENTS:
			# Full fields are checked on every newly accepted serial. Cache a
			# terminal comparison after arrival so observer work cannot revalidate
			# eight 157KiB dictionaries on every idle network poll.
			if not seen[index] and int(clients[index].world.latest.get("tick", -1)) == int(value.tick):
				seen[index] = clients[index].world.latest == value
			if not seen[index] or not progress[index].valid:
				complete = false
		if complete:
			stage_convergence = Time.get_ticks_msec() - started
			return true
		await process_frame
	stage_convergence = Time.get_ticks_msec() - started
	return false

func _pump_until_snapshot(value: Dictionary, seconds: int = 5) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while Time.get_ticks_msec() < deadline:
		_poll_all()
		var complete := true
		for endpoint in clients:
			if endpoint.world.latest != value:
				complete = false
		if complete:
			return true
		await process_frame
	return false

func _eight_player_frames() -> void:
	_begin_stage("eight_players")
	var expected: Dictionary = await _publish_for(3000, true, true)
	_check(stage_duration >= 3000 and stage_published >= 40, "eight-player snapshots publish continuously at nominal 50ms for at least three seconds")
	_check(await _converge(expected), "all eight clients converge during continued ordinary terminal-state publication")
	for index in CLIENTS:
		_check(progress[index].ticks.size() >= 3 and progress[index].windows.size() == 3, "client %d continuously observes advancing ordinary ticks" % index)
	_finish_stage(expected, {"players": CLIENTS, "raw_json_bytes": JSON.stringify(expected).to_utf8_buffer().size()})

func _production_process_frames() -> void:
	var ids: Array = authority.players.keys()
	ids.sort()
	var baseline_tick: int = authority.tick
	for index in CLIENTS:
		process_reception.append({"client": index, "ticks": [], "valid": true})
	authority.set_process(true)
	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		# No manual _publish, advance or flush: only the production _process
		# advances authoritative state and serves its paced sender.
		_poll_all(false)
		for index in CLIENTS:
			var latest: Dictionary = clients[index].world.latest
			var tick := int(latest.get("tick", -1))
			if tick <= baseline_tick:
				continue
			var row: Dictionary = process_reception[index]
			row.valid = row.valid and _ids(latest) == ids and tick <= authority.tick
			if not row.ticks.is_empty() and tick < int(row.ticks[-1]):
				row.valid = false
			if row.ticks.is_empty() or tick != int(row.ticks[-1]):
				row.ticks.append(tick)
		await process_frame
	authority.set_process(false)
	for index in CLIENTS:
		_check(process_reception[index].valid and process_reception[index].ticks.size() >= 2, "client %d progresses through actual production _process without manual sender flush" % index)

func _worst_legal_snapshot() -> void:
	# Fill the schema's actual array/string bounds through authoritative game state.
	# Only the eight real peers are targeted. Extra legal player rows are synthetic
	# game state, not phantom network admissions or additional live clients.
	var prototype: Dictionary = authority.players.values()[0].duplicate(true)
	var random := RandomNumberGenerator.new()
	random.seed = 2841392
	authority.players.clear()
	for index in 16:
		var user := "%03d" % index + _noise(125, random)
		var player: Dictionary = prototype.duplicate(true)
		player.user_id = user
		player.display_name = _noise(32, random)
		player.notice = _noise(128, random)
		player.kills = 100000
		player.deaths = 100000
		player.position = Vector2(946, 478)
		player.aim = Vector2(-1, 1)
		authority.players[user] = player
	authority.shots.clear()
	for index in 192:
		authority.shots.append({"id": index + 1, "at": 9007199254740991, "x": -1500.0, "y": -1500.0, "end_x": 2460.0, "end_y": 2040.0, "weapon": "shotgun"})
	authority.last_results.clear()
	for index in 256:
		authority.last_results.append({"user_id": "%03d" % index + _noise(125, random), "kills": 100000, "deaths": 100000, "participation_ms": 3600000, "credits": 1000000})
	authority.tick += 1
	var expected: Dictionary = authority.state_snapshot()
	if not _require(Validator.validate_file(expected, "res://schemas/shooter_state.schema.json") == "", "max-count/max-string snapshot is legal under the real schema"):
		return
	var raw_bytes := JSON.stringify(expected).to_utf8_buffer().size()
	var packets: Array[PackedByteArray] = Codec.encode(expected, 1, 1)
	var largest_packet := 0
	for packet in packets:
		largest_packet = maxi(largest_packet, packet.size())
	_check(raw_bytes > 1392 * 8 and packets.size() > 8, "large legal snapshot actually encodes to many wire fragments even after compression")
	_check(largest_packet <= Codec.MAX_PACKET_BYTES, "every encoded RPC argument remains within the production packet budget")
	print("INFO max_snapshot raw_json_bytes=", raw_bytes, " codec_fragments=", packets.size(), " max_rpc_payload_bytes=", largest_packet)
	_check(packets.size() >= 87, "unchanged maximal high-entropy fixture retains at least the original 87 fragments")
	var large_ttl: int = Codec.frame_ttl_ms(packets.size())
	_check(Codec.frame_ttl_ms(1) == 250, "small-frame reassembly TTL remains the original 250ms")
	if not capacity_only:
		_check(Codec.frame_ttl_ms(87) == 490 and Codec.frame_ttl_ms(544) == 2428, "final bounded TTL contract is 87 fragments 490ms and 544 fragments 2428ms")
	_begin_stage("maximal_legal")
	final_large = await _publish_for(5000, false)
	var sustained: Array = []
	_check(stage_duration >= 5000 and stage_published >= 50, "16-player/192-shot/256-result maximal states publish continuously for at least five seconds")
	for index in CLIENTS:
		sustained.append(progress[index].serials.size())
		_check(progress[index].serials.size() > 0, "client %d completes a full maximal frame during the five-second load" % index)
	_check(await _converge(final_large), "all eight clients converge during continued maximal terminal-state publication")
	_finish_stage(final_large, {"players": 16, "shots": 192, "last_results": 256, "raw_json_bytes": raw_bytes, "codec_fragments": packets.size(), "frame_ttl_ms": large_ttl, "small_frame_ttl_ms": Codec.frame_ttl_ms(1), "maximum_frame_ttl_ms": Codec.frame_ttl_ms(544), "max_rpc_payload_bytes": largest_packet, "sustained_complete_frames": sustained})

func _pump_ms(milliseconds: int, flush: bool = true) -> void:
	var until := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < until:
		_poll_all(flush)
		await process_frame

func _loss_and_bad_packet_recovery() -> void:
	await _pump_ms(300)
	var baseline: Array = []
	for endpoint in clients:
		baseline.append(endpoint.world.latest.duplicate(true))
	var malformed: Dictionary = authority.state_snapshot()
	malformed.tick = authority.tick + 1
	var bad_serial: int = authority.get("_snapshot_serial") + 1
	var stream: int = authority.get("_snapshot_stream")
	var packets: Array[PackedByteArray] = Codec.encode(malformed, bad_serial, stream)
	if not _require(packets.size() > 1, "fault injection retains the full multi-fragment maximal business state"):
		return
	var bad: PackedByteArray = packets[0].duplicate()
	bad.encode_u32(0, 0)
	var incomplete: Array[PackedByteArray] = Codec.encode(malformed, bad_serial + 1, stream)
	# Reserve injected serials so subsequent production publication is newer.
	authority.set("_snapshot_serial", bad_serial + 1)
	var saw_partial: Array = []
	for index in CLIENTS:
		saw_partial.append(false)
	for repetition in 5:
		for index in CLIENTS:
			var peer_id: int = clients[index].api.get_unique_id()
			authority.world_chunk.rpc_id(peer_id, bad)
			authority.world_chunk.rpc_id(peer_id, incomplete[0])
		await _pump_ms(20)
		for index in CLIENTS:
			var decoder = clients[index].world.get("_snapshot_decoder")
			saw_partial[index] = saw_partial[index] or decoder.get("_frames").has(bad_serial + 1)
	for index in CLIENTS:
		_check(saw_partial[index], "client %d actually receives an intentionally incomplete frame" % index)
		_check(clients[index].world.latest == baseline[index], "client %d retains its complete state after bad-header and missing-fragment injection" % index)
	await _pump_ms(600)
	authority.players = ordinary_players.duplicate(true)
	authority.shots.clear()
	authority.last_results.clear()
	_begin_stage("fault_recovery")
	var value: Dictionary = await _publish_for(1500, true)
	_check(await _converge(value), "normal continued publication restores all eight clients after malformed/incomplete RPCs")
	_finish_stage(value, {"players": CLIENTS, "injected_missing_serial": bad_serial + 1, "saw_partial": saw_partial})

func _slow_scheduler_recovery() -> void:
	# Recreate the exact saved large state instead of lowering business payload.
	# _worst_legal_snapshot populated authority state; retain a saved copy before
	# restoring the ordinary fixture in fault recovery.
	var prototype: Dictionary = authority.players.values()[0].duplicate(true)
	authority.players.clear()
	for row in final_large.players:
		var player: Dictionary = prototype.duplicate(true)
		player.user_id = row.user_id
		player.display_name = row.display_name
		player.notice = row.notice
		player.kills = row.kills
		player.deaths = row.deaths
		player.position = Vector2(row.x, row.y)
		player.aim = Vector2(row.aim_x, row.aim_y)
		authority.players[player.user_id] = player
	authority.shots = final_large.shots.duplicate(true)
	authority.last_results = final_large.last_results.duplicate(true)
	_begin_stage("slow_scheduler_recovery")
	# Publish without flushing, then begin an actual incomplete active frame.
	authority.tick += 1
	issued[authority.tick] = authority.state_snapshot()
	authority._publish()
	stage_published += 1
	_poll_all()
	var sender = authority.get("_snapshot_sender")
	var active_fragments: int = sender.active.size()
	var sent_some := false
	var incomplete := false
	for offset in sender.offsets.values():
		sent_some = sent_some or int(offset) > 0
		incomplete = incomplete or int(offset) < active_fragments
	_check(active_fragments >= 87 and sent_some and incomplete, "pause begins after real partial transmission of an active maximal frame")
	# Add latest pending work without flush; this must survive abandonment of the
	# stale active frame and provide fresh state after scheduler resumption.
	authority.tick += 1
	issued[authority.tick] = authority.state_snapshot()
	authority._publish()
	stage_published += 1
	_check(not sender.pending.is_empty(), "a latest pending maximal frame exists before the scheduler pause")
	var paused := Time.get_ticks_msec()
	await _pump_ms(600, false)
	var pause_ms := Time.get_ticks_msec() - paused
	_check(pause_ms >= 600, "flush pauses at least 600ms while actual ENet continues polling")
	var value: Dictionary = await _publish_for(1500, false)
	_check(await _converge(value), "all eight full maximal states converge after slow scheduler resumption")
	_finish_stage(value, {"players": 16, "shots": 192, "last_results": 256, "flush_pause_ms": pause_ms, "active_fragments_before_pause": active_fragments})

func _noise(length: int, random: RandomNumberGenerator) -> String:
	var value := ""
	for index in length:
		value += String.chr(random.randi_range(0x4e00, 0x9c20))
	return value

func _close_network() -> void:
	if authority != null:
		_check(_connected_count() == CLIENTS, "all eight real peers stay connected through capacity and recovery gates")
		authority._publish()
		var sender = authority.get("_snapshot_sender")
		_check(not sender.pending.is_empty(), "real connected authority queues a publication before shutdown")
		authority.stop_snapshot_transport()
		for user in authority.peers.values().duplicate():
			authority.remove_player(user)
		authority._publish()
		authority.flush_snapshot_transport(Time.get_ticks_msec())
		_check(sender.active.is_empty() and sender.pending.is_empty() and sender.offsets.is_empty() and sender.recipients.is_empty(), "stop then member cleanup and republish keep the real connected authority outbox empty")
	# Keep the UDP authority alive while clients send their DTLS close_notify.
	# Closing the server socket first gives Linux clients ECONNREFUSED; Windows
	# ignores that datagram error, hiding this shared-process fixture mistake.
	for endpoint in clients:
		endpoint.peer.close()
		endpoint.api.multiplayer_peer = null
	if not endpoints.is_empty():
		var server_api: SceneMultiplayer = endpoints[0].api
		var close_deadline := Time.get_ticks_msec() + 1000
		while not server_api.get_peers().is_empty() and Time.get_ticks_msec() < close_deadline:
			server_api.poll()
			await process_frame
	for endpoint in endpoints:
		endpoint.peer.close()
		endpoint.api.multiplayer_peer = null
		set_multiplayer(null, endpoint.branch.get_path())
		if endpoint.world.has_method("reset_network_state"):
			endpoint.world.reset_network_state()
		endpoint.branch.free()
	endpoints.clear()
	clients.clear()
	authority = null
	await process_frame
	_check(endpoints.is_empty() and clients.is_empty(), "all owned ENet peers, SceneMultiplayer branches and worlds close")
	if listening_port > 0:
		var probe := ENetMultiplayerPeer.new()
		probe.set_bind_ip("127.0.0.1")
		_check(probe.create_server(listening_port, CLIENTS, 2) == OK, "the owned ephemeral UDP port can be rebound after close")
		probe.close()

func _check(condition: bool, label: String) -> void:
	checks.append({"name": label, "ok": condition})
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func _require(condition: bool, label: String) -> bool:
	_check(condition, label)
	return condition

func _finish() -> void:
	if evidence != "":
		var file := FileAccess.open(evidence, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"passed": passed, "failed": failed, "clients": CLIENTS, "platform": OS.get_name(), "engine_version": Engine.get_version_info().string, "transport": "loopback ENet DTLS" if dtls else "loopback ENet, no DTLS", "dtls": dtls, "dtls_evidence": dtls_evidence, "capacity_only": capacity_only, "fixed_poll_order": fixed_poll_order, "server_relay": false, "period_ms": 50, "terminal_timeout_ms": 5000, "sender_limits": {"per_peer_burst": Sender.PER_PEER_BURST, "total_burst": Sender.TOTAL_BURST, "minimum_flush_ms": Sender.MIN_FLUSH_MS, "max_rpc_payload_bytes": Codec.MAX_PACKET_BYTES}, "poll_timing": poll_timing, "slow_polls": slow_polls, "decoder_samples": decoder_samples, "process_reception": process_reception, "checks": checks, "observed": observed, "reception": reception, "flush_us": transport_samples}))
			file.close()
		else:
			_check(false, "test evidence file can be written")
	print("SHOOTER_SNAPSHOT_NETWORK_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

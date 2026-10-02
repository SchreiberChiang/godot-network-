extends SceneTree
## Real loopback ENet/RPC regression. No account, storage, DTLS or public-network claim.
const Shooter = preload("res://examples/shooter/game.gd")
const Codec = preload("res://examples/shooter/snapshot_codec.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
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

func _initialize() -> void:
	multiplayer_poll = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			evidence = argument.trim_prefix("--evidence=")
	_run.call_deferred()

func _run() -> void:
	var dependency = Shooter.new()
	var ready: bool = dependency.has_method("world_chunk")
	dependency.free()
	if not _require(ready, "production world_chunk dependency is present"):
		_finish()
		return
	if not await _open_network():
		await _close_network()
		_finish()
		return
	await _eight_player_frames()
	await _worst_legal_snapshot()
	await _close_network()
	_finish()

func _add_endpoint(label: String, peer: ENetMultiplayerPeer, is_server: bool) -> Dictionary:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	var api := SceneMultiplayer.new()
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
	var endpoint := _add_endpoint("SnapshotServer", server_peer, true)
	authority = endpoint.world
	for index in CLIENTS:
		var client_peer := ENetMultiplayerPeer.new()
		if not _require(client_peer.create_client("127.0.0.1", listening_port, 2) == OK, "create real ENet client %d" % index):
			client_peer.close()
			return false
		clients.append(_add_endpoint("SnapshotClient%d" % index, client_peer, false))
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_poll_all()
		if _connected_count() == CLIENTS and endpoint.api.get_peers().size() == CLIENTS:
			break
		await process_frame
	if not _require(_connected_count() == CLIENTS and endpoint.api.get_peers().size() == CLIENTS, "all eight actual ENet handshakes reach the authority"):
		return false
	for index in CLIENTS:
		var peer_id: int = clients[index].api.get_unique_id()
		_check(peer_id > 1, "client %d has its actual ENet peer ID" % index)
		authority.admit({"user_id": "net-player-%02d" % index, "display_name": "Net %d" % index}, peer_id)
	return _require(authority.players.size() == CLIENTS, "authority admits exactly eight synthetic players")

func _connected_count() -> int:
	var count := 0
	for endpoint in clients:
		if endpoint.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			count += 1
	return count

func _poll_all() -> void:
	for endpoint in endpoints:
		if endpoint.api.has_multiplayer_peer():
			var error: int = endpoint.api.poll()
			if error != OK:
				_check(false, "real SceneMultiplayer poll returns OK")

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
	var ticks: Array = []
	for index in CLIENTS:
		ticks.append([])
	var expected: Dictionary = {}
	for frame in 6:
		authority.advance((frame + 1) * 50)
		authority._publish()
		expected = authority.state_snapshot()
		# Production snapshots are unreliable. Do not require every intermediate
		# frame to arrive; allow observed gaps while requiring monotonic progress.
		var until := Time.get_ticks_msec() + 80
		while Time.get_ticks_msec() < until:
			_poll_all()
			await process_frame
		for index in CLIENTS:
			var latest: Dictionary = clients[index].world.latest
			var received_tick := int(latest.get("tick", -1))
			var prior_tick: int = ticks[index][-1] if not ticks[index].is_empty() else -1
			_check(received_tick >= prior_tick and received_tick <= int(expected.tick), "client %d accepted tick never rolls back or advances past the authority" % index)
			if received_tick != prior_tick:
				ticks[index].append(received_tick)
			var ids: Array = []
			for player in latest.get("players", []):
				ids.append(player.user_id)
			ids.sort()
			var expected_ids: Array = authority.players.keys()
			expected_ids.sort()
			_check(ids == expected_ids and ids.size() == CLIENTS, "client %d always has the complete eight-identity snapshot" % index)
		observed.append({"group": "eight_players", "tick": expected.tick, "players": expected.players.size(), "raw_json_bytes": JSON.stringify(expected).to_utf8_buffer().size()})
	_check(await _pump_until_snapshot(expected), "all eight clients receive the final authority tick without a resend")
	for index in CLIENTS:
		_check(ticks[index].size() >= 2 and clients[index].world.latest == expected, "client %d observes multiple advancing frames and the complete latest tick" % index)
		var row := {"group": "eight_players", "client": index, "observed_ticks": ticks[index], "unobserved_published_ticks": 6 - ticks[index].size(), "final_tick": int(clients[index].world.latest.get("tick", -1))}
		reception.append(row)
		print("INFO snapshot_client=", index, " observed_ticks=", ticks[index], " unobserved_published_ticks=", row.unobserved_published_ticks)

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
	authority._publish()
	_check(await _pump_until_snapshot(expected), "maximal legal snapshot arrives completely through actual world_chunk RPC on all eight clients")
	for index in CLIENTS:
		var actual: Dictionary = clients[index].world.latest
		_check(actual == expected and actual.players.size() == 16 and actual.shots.size() == 192 and actual.last_results.size() == 256, "client %d reconstructs every field in the maximal legal snapshot" % index)
		var decoder = clients[index].world.get("_snapshot_decoder")
		var partial: Array = []
		for serial in decoder._frames:
			var frame: Dictionary = decoder._frames[serial]
			partial.append({"serial": serial, "received_fragments": frame.parts.size(), "declared_fragments": frame.header.count})
		reception.append({"group": "maximal_legal", "client": index, "complete": actual == expected, "partial_frames": partial})
		print("INFO maximal_client=", index, " complete=", actual == expected, " partial_frames=", partial)
	observed.append({"group": "maximal_legal", "tick": expected.tick, "players": 16, "shots": 192, "last_results": 256, "raw_json_bytes": raw_bytes, "codec_fragments": packets.size(), "max_rpc_payload_bytes": largest_packet})

func _noise(length: int, random: RandomNumberGenerator) -> String:
	var value := ""
	for index in length:
		value += String.chr(random.randi_range(0x4e00, 0x9c20))
	return value

func _close_network() -> void:
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
			file.store_string(JSON.stringify({"passed": passed, "failed": failed, "clients": CLIENTS, "transport": "loopback ENet, no DTLS", "checks": checks, "observed": observed, "reception": reception}))
			file.close()
		else:
			_check(false, "test evidence file can be written")
	print("SHOOTER_SNAPSHOT_NETWORK_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

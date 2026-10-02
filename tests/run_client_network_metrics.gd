extends SceneTree
## N1 deterministic reducer + a short real loopback ENet check.
## No induced loss, public-network, DTLS, latency, or performance acceptance.
const RoomClient = preload("res://sdk/roomkit/client/room_client.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_reducer_checks()
	_error_whitelist_checks()
	_single_consumer_source_check()
	await _real_enet()
	print("CLIENT_NETWORK_METRICS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _reducer_checks() -> void:
	var client = RoomClient.new()
	var empty: Dictionary = client.diagnostics_snapshot()
	for field in ["rtt_ms", "rtt_variance_ms", "reliable_loss_percent", "tx_bytes_per_sec", "rx_bytes_per_sec", "rtt_p50_ms", "rtt_p95_ms"]:
		_check(float(empty[field]) == -1.0, "empty metric is unknown: " + field)
	_check(empty.phase == "CLOSED" and empty.error == "NONE", "empty snapshot has fixed phase and error")
	_check(empty.sample_count == 0 and empty.loss_sample_count == 0, "no sample counts before collection")
	client._accept_network_observation(1000, 0.0, 9.0, 0.0, 0, 5000.0, 3000.0)
	var first: Dictionary = client._diagnostic_cache.duplicate(true)
	_check(first.rtt_ms == 0.0 and first.rtt_variance_ms == 9.0, "genuine zero RTT remains measured; variance stays milliseconds without sqrt")
	_check(first.tx_bytes_per_sec == -1.0 and first.rx_bytes_per_sec == -1.0, "first byte counter observation establishes baseline without invented rate")
	_check(first.reliable_loss_percent == -1.0 and first.loss_state == "collecting", "initial zero loss and zero epoch remain collecting")
	client._accept_network_observation(1500, 999.0, 99.0, 65536.0, 500, 9999.0, 9999.0)
	_check(client._diagnostic_cache == first, "sampling cadence refuses extra half-second observations")
	client._accept_network_observation(2000, 25.0, 16.0, 0.0, 123456, 2000.0, 3000.0)
	_check(client._diagnostic_cache.reliable_loss_percent == -1.0 and client._diagnostic_cache.loss_sample_count == 0, "first nonzero opaque epoch is not a completed window")
	_check(client._diagnostic_cache.tx_bytes_per_sec == 2000.0 and client._diagnostic_cache.rx_bytes_per_sec == 3000.0, "rates divide bytes by actual elapsed monotonic interval")
	client._accept_network_observation(122000, 40.0, 20.0, 0.0, 123456, 12000.0, 6000.0)
	_check(client._diagnostic_cache.reliable_loss_percent == -1.0, "elapsed wall time without epoch transition cannot prove zero loss")
	_check(client._diagnostic_cache.tx_bytes_per_sec == 100.0 and client._diagnostic_cache.rx_bytes_per_sec == 50.0, "long callback gap does not pretend the rate interval was one second")
	_check(client._diagnostic_cache.rtt_sample_count == 1, "expired RTT observations leave bounded rolling window")
	client._accept_network_observation(123000, 41.0, 21.0, 0.0, 133456, 0.0, 0.0)
	_check(client._diagnostic_cache.reliable_loss_percent == 0.0 and client._diagnostic_cache.loss_sample_count == 1 and client._diagnostic_cache.loss_state == "available", "completed ten-second epoch permits measured reliable-send zero")
	client._accept_network_observation(124000, 42.0, 22.0, 16384.0, 143456, 100.0, 200.0)
	_check(client._diagnostic_cache.reliable_loss_percent == 25.0, "fixed ENet packet-loss scale65536 converts raw16384 to25percent")
	_check(client._diagnostic_cache.loss_sample_count == 2, "loss sample count tracks completed epoch observations")
	client._accept_network_observation(125000, 43.0, 23.0, 32768.0, 143456, 0.0, 0.0)
	_check(client._diagnostic_cache.reliable_loss_percent == 25.0 and client._diagnostic_cache.loss_sample_count == 2, "same epoch cannot manufacture additional loss samples")
	client._accept_network_observation(126000, 44.0, 24.0, 32768.0, 143457, 0.0, 0.0)
	_check(client._diagnostic_cache.reliable_loss_percent == -1.0 and client._diagnostic_cache.loss_state == "collecting", "sub-epoch reset drops old reliable loss")
	client._accept_network_observation(127000, 45.0, 25.0, 0.0, 0, 0.0, 0.0)
	_check(client._diagnostic_loss_epoch == -1 and client._diagnostic_cache.loss_sample_count == 0, "zero epoch removes old readiness")
	client._reset_network_diagnostics()
	client._accept_network_observation(1000, 1.0, 1.0, 0.0, 0xfffffff0, 0.0, 0.0)
	client._accept_network_observation(2000, 2.0, 2.0, 32768.0, (0xfffffff0 + 10000) & 0xffffffff, 0.0, 0.0)
	_check(client._diagnostic_cache.reliable_loss_percent == 50.0, "uint32 epoch wrap preserves a proven complete window")
	client._accept_network_observation(3000, 3.0, 3.0, 0.0, 5000, 0.0, 0.0)
	_check(client._diagnostic_cache.reliable_loss_percent == -1.0, "backward epoch invalidates the earlier connection estimate")
	client._reset_network_diagnostics()
	for index in range(9):
		client._accept_network_observation(index * 1000, float(index + 1), 4.0, 0.0, 100, 100.0, 100.0)
	_check(client._diagnostic_cache.rtt_p50_ms == -1.0 and client._diagnostic_cache.rtt_p95_ms == -1.0, "fewer than ten RTT observations has no percentiles")
	client._accept_network_observation(9000, 10.0, 4.0, 0.0, 100, 100.0, 100.0)
	_check(client._diagnostic_cache.rtt_p50_ms == 5.0 and client._diagnostic_cache.rtt_p95_ms == 10.0, "ten sorted observations use documented nearest-rank percentiles")
	for index in range(10, 100):
		client._accept_network_observation(index * 1000, float(index + 1), 4.0, 0.0, 100, 100.0, 100.0)
	_check(client._diagnostic_rtt_samples.size() <= RoomClient.DIAGNOSTIC_MAX_RTT_SAMPLES and client._diagnostic_cache.rtt_sample_count == 30, "long sessions retain only the bounded thirty-second RTT window")
	client._accept_network_observation(130000, NAN, INF, 0.0, 100, -1.0, INF)
	_check(client._diagnostic_cache.rtt_ms == -1.0 and client._diagnostic_cache.rtt_variance_ms == -1.0 and client._diagnostic_cache.tx_bytes_per_sec == -1.0, "nonfinite or invalid numeric observations never escape")
	_check(client._diagnostic_cache.rtt_sample_count == 0 and client._diagnostic_cache.rtt_p50_ms == -1.0, "empty expired RTT window returns to unknown")
	client._reset_network_diagnostics()
	_check(client._diagnostic_cache == RoomClient._empty_network_diagnostics() and client._diagnostic_loss_epoch == -1, "reset clears samples, rate baseline, epochs and cached values")
	client._accept_network_observation(1000, 5.0, 4.0, 0.0, 100, 0.0, 0.0)
	client._connection_lost("DISCONNECTED")
	_check(client._diagnostic_cache.sample_count == 0 and client.diagnostics_snapshot().error == "DISCONNECTED", "disconnect immediately resets metrics while preserving fixed error")
	client.close()
	_check(client.diagnostics_snapshot().error == "NONE" and client.diagnostics_snapshot().phase == "CLOSED", "explicit close clears old diagnostics and error")
	client.free()

func _error_whitelist_checks() -> void:
	var sensitive := "password_synthetic_token_credential_ticket_invite_123"
	_check(RoomClient.diagnostic_error_category(sensitive) == "OTHER", "arbitrary safe-looking alphanumeric secret cannot become error category")
	_check(RoomClient.diagnostic_phase_category(sensitive) == "OTHER", "arbitrary phase cannot enter diagnostic record")
	_check(RoomClient._lobby_close_category(1008) == "POLICY_VIOLATION" and RoomClient._lobby_close_category(4999) == "OTHER", "close classification uses numeric allowlist, never remote text")
	_check(RoomClient.diagnostic_error_category("AUTH_FAILED") == "AUTH_FAILED", "known fixed errors remain useful")
	_check(RoomClient.diagnostic_error_category("BUILD_MISMATCH") == "BUILD_MISMATCH" and RoomClient.diagnostic_error_category("AUTH_REQUIRED") == "AUTH_REQUIRED", "managed fixed error classifications remain useful")
	_check(RoomClient.diagnostic_phase_category("AUTHENTICATING_ACCOUNT") == "AUTHENTICATING_ACCOUNT", "inherited managed account phase remains visible")
	var client = RoomClient.new()
	client._failure(sensitive)
	_check(client.diagnostics_snapshot().error == "OTHER", "local failure records only its fixed error category")
	client.free()

func _single_consumer_source_check() -> void:
	var source := FileAccess.get_file_as_string("res://sdk/roomkit/client/room_client.gd")
	_check(source.count(".pop_statistic(") == 2, "only one collector reads exactly the TX and RX host counters")
	_check(not source.contains("get_close_reason(") and not source.contains("JSON.parse_string(bytes"), "SDK logs never parse arbitrary reply type or close reason for output")
	_check(not source.contains(".reset(") and not source.contains(".ping(") and not source.contains(".ping_interval("), "collector does not reset a peer or introduce probes and frequency changes")

func _real_enet() -> void:
	var client = RoomClient.new()
	client.state = "IN_ROOM"
	var server := ENetMultiplayerPeer.new()
	server.set_bind_ip("127.0.0.1")
	var server_error := server.create_server(0, 1)
	_check(server_error == OK, "bind real loopback-only ephemeral ENet server")
	if server_error != OK:
		client.free()
		return
	client.enet = ENetMultiplayerPeer.new()
	var opened: int = client.enet.create_client("127.0.0.1", server.host.get_local_port())
	_check(opened == OK, "create real loopback ENet client")
	if opened != OK:
		client.close()
		client.free()
		server.close()
		return
	_check(client.diagnostics_snapshot().rtt_ms == -1.0, "connecting real ENet has no cached RTT")
	var deadline := Time.get_ticks_msec() + 3000
	while client.enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() < deadline:
		server.poll()
		client.enet.poll()
		await process_frame
	_check(client.enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "real ENet loopback handshake completes")
	if client.enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_check(client.room_round_trip_ms() < 0.0, "readers do not force collection before first collector observation")
		var at_ms := Time.get_ticks_msec()
		client._collect_network_diagnostics(at_ms)
		var first: Dictionary = client.diagnostics_snapshot()
		_check(first.sample_count == 1 and first.rtt_ms >= 0.0 and first.rtt_ms == client.enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), "real collector caches actual ENet RTT")
		_check(first.reliable_loss_percent == -1.0 and first.loss_state == "collecting", "short loopback cannot claim a measured loss percentage")
		_check(first.tx_bytes_per_sec < 0 and first.rx_bytes_per_sec < 0, "real first observation discards pre-baseline handshake counters")
		var changed: Dictionary = client.diagnostics_snapshot()
		changed.rtt_ms = 999999.0
		_check(client.diagnostics_snapshot().rtt_ms == first.rtt_ms, "snapshot callers cannot mutate shared cache")
		for index in range(100):
			client.diagnostics_snapshot()
			client.room_round_trip_ms()
		_check(client.diagnostics_snapshot() == first, "HUD and journal reads neither consume counters nor add samples")
		while Time.get_ticks_msec() - at_ms < 1100:
			server.poll()
			client.enet.poll()
			await process_frame
		client._collect_network_diagnostics(Time.get_ticks_msec())
		var second: Dictionary = client.diagnostics_snapshot()
		_check(second.sample_count == 2 and second.transport_sample_count == 1, "second real observation creates exactly one interval rate")
		_check(is_finite(second.tx_bytes_per_sec) and second.tx_bytes_per_sec >= 0.0 and is_finite(second.rx_bytes_per_sec) and second.rx_bytes_per_sec >= 0.0, "real loopback host byte rates are finite")
		client._connection_lost("DISCONNECTED")
		_check(client.diagnostics_snapshot().rtt_ms < 0.0 and client.diagnostics_snapshot().sample_count == 0, "disconnect hides cached values before transport closes")
		client._disconnect_pending = false
		client._collect_network_diagnostics(Time.get_ticks_msec())
		_check(client.diagnostics_snapshot().sample_count == 1 and client.diagnostics_snapshot().transport_sample_count == 0, "new baseline cannot inherit earlier byte-rate sample")
		client.state = "LOBBY"
		_check(client.room_round_trip_ms() < 0.0, "lobby phase cannot display old room transport values")
	client.close()
	_check(client.diagnostics_snapshot().sample_count == 0 and client.diagnostics_snapshot().reliable_loss_percent < 0.0, "real close clears all old metrics")
	client.free()
	server.close()

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

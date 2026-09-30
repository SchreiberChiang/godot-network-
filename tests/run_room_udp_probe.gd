extends SceneTree
## Diagnostic traffic against one room's UDP port, as a forwarded public port may
## receive it: random datagrams, a plain ENet connect without DTLS, and DTLS
## handshakes the client aborts (wrong server name / untrusted certificate).
## It never completes admission and carries no credentials.
## Usage: --headless --script res://tests/run_room_udp_probe.gd -- --host=127.0.0.1
##        --port=<udp> --mode=garbage|enet_plain|dtls_wrong_name|dtls_untrusted
##        [--certificate=<public server.crt>] [--repeat=N]

func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0].trim_prefix("--")] = pair[1]
	_run.call_deferred(args)

func _run(args: Dictionary) -> void:
	var host := str(args.get("host", "127.0.0.1"))
	var port := int(args.get("port", "0"))
	var mode := str(args.get("mode", ""))
	var repeat := int(args.get("repeat", "1"))
	if port <= 0:
		printerr("PROBE_FAILED missing port")
		quit(2)
		return
	var outcomes: Array = []
	for index in repeat:
		match mode:
			"garbage":
				var udp := PacketPeerUDP.new()
				udp.connect_to_host(host, port)
				var crypto := Crypto.new()
				for packet in 200:
					udp.put_packet(crypto.generate_random_bytes(1 + packet * 3 % 600))
				udp.close()
				outcomes.append("sent_200")
			"enet_plain":
				outcomes.append(await _enet(host, port, null, ""))
			"dtls_wrong_name":
				var certificate := X509Certificate.new()
				if certificate.load(str(args.get("certificate", ""))) != OK:
					printerr("PROBE_FAILED certificate")
					quit(2)
					return
				outcomes.append(await _enet(host, port, TLSOptions.client(certificate), "wrong-name.invalid"))
			"dtls_untrusted":
				outcomes.append(await _enet(host, port, TLSOptions.client(), "localhost"))
			_:
				printerr("PROBE_FAILED unknown mode")
				quit(2)
				return
	print("PROBE_DONE mode=", mode, " outcomes=", ",".join(outcomes))
	quit(0)

func _enet(host: String, port: int, tls: TLSOptions, name: String) -> String:
	var connection := ENetConnection.new()
	if connection.create_host(1) != OK:
		return "host_failed"
	if tls != null and connection.dtls_client_setup(name, tls) != OK:
		connection.destroy()
		return "dtls_setup_failed"
	var peer := connection.connect_to_host(host, port)
	if peer == null:
		connection.destroy()
		return "connect_failed"
	var outcome := "timeout"
	var until := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < until:
		var event: Array = connection.service(20)
		if event[0] == ENetConnection.EVENT_CONNECT:
			outcome = "connected"
			peer.peer_disconnect()
		elif event[0] == ENetConnection.EVENT_DISCONNECT:
			outcome = "disconnected" if outcome == "timeout" else outcome
			break
		elif event[0] == ENetConnection.EVENT_ERROR:
			outcome = "error"
			break
		await process_frame
	connection.destroy()
	return outcome

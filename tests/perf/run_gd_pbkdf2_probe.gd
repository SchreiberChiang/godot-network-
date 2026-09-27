extends SceneTree
## Evaluation only: can PBKDF2-HMAC-SHA256 at the production 600000 iterations
## run inside Godot without .NET (relevant if storage moved to a native Godot
## database extension)? Checks a published test vector, then times iterations.
const VECTOR_ITERATIONS := 4096
const VECTOR := "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"
const PRODUCTION_ITERATIONS := 600000

func _initialize() -> void:
	var crypto := Crypto.new()
	var started := Time.get_ticks_usec()
	var derived := pbkdf2_block(crypto, "password".to_utf8_buffer(), "salt".to_utf8_buffer(), VECTOR_ITERATIONS)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	var correct := derived.hex_encode() == VECTOR
	started = Time.get_ticks_usec()
	pbkdf2_block(crypto, "storage-probe".to_utf8_buffer(), crypto.generate_random_bytes(32), 20000)
	var sample_ms := (Time.get_ticks_usec() - started) / 1000.0
	var projected_ms := sample_ms / 20000.0 * PRODUCTION_ITERATIONS
	var report := {"vector_correct": correct, "vector_4096_ms": snappedf(elapsed_ms, 0.1), "iterations_20000_ms": snappedf(sample_ms, 0.1), "projected_600000_ms": snappedf(projected_ms, 1.0)}
	# Optional cross-check against the .NET Rfc2898DeriveBytes used by account_store.ps1:
	# --dotnet=<base64 derived>,<base64 salt>,<iterations> for password "compat-password".
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dotnet="):
			var parts := argument.trim_prefix("--dotnet=").split(",")
			var mine := pbkdf2_block(crypto, "compat-password".to_utf8_buffer(), Marshalls.base64_to_raw(parts[1]), int(parts[2]))
			report.dotnet_iterations = int(parts[2])
			report.dotnet_match = Marshalls.raw_to_base64(mine) == parts[0]
			correct = correct and report.dotnet_match
	var file := FileAccess.open(ProjectSettings.globalize_path("res://logs/gd-pbkdf2-probe.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print(JSON.stringify(report))
	print("GD_PBKDF2_PROBE_RESULT correct=", correct)
	quit(0 if correct else 1)

static func pbkdf2_block(crypto: Crypto, password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	# Single 32-byte block (dkLen = hash length), as the account helper derives.
	var first := salt.duplicate()
	first.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, first)
	var result := u.duplicate()
	for iteration in iterations - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for index in 32:
			result[index] = result[index] ^ u[index]
	return result

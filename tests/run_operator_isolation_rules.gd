extends SceneTree
## Pure checks of tests/support/operator_isolation.gd: no Operator, no process,
## no service. Folders and (on Linux) symbolic links are created only inside a
## new folder under res://data and removed at the end.
## Usage: --headless --script res://tests/run_operator_isolation_rules.gd
const Isolation = preload("res://tests/support/operator_isolation.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
var passed := 0
var failed := 0
var not_run := 0

func _initialize() -> void:
	var data := Paths.absolute("res://data").simplify_path()
	var iso := data.path_join("isolation-rules-" + Crypto.new().generate_random_bytes(6).hex_encode())
	DirAccess.make_dir_recursive_absolute(iso.path_join("data"))
	var good := ["--isolation=" + iso, "--data-root=" + iso.path_join("data"), "--games=" + iso.path_join("games.json"), "--public-client-dir=" + iso.path_join("public"), "--panel-port=28391"]
	check(_refusal(good, data) == "", "a complete isolated argument set is accepted")
	# Duplicates: the first --games shared, the second isolated.
	check(_refusal(["--games=" + data.path_join("../artifacts/framework-games.json").simplify_path()] + good, data).contains("more than once"), "a shared --games followed by an isolated --games is refused")
	check(_refusal(good + ["--panel-port=28392"], data).contains("more than once"), "a repeated non-path argument is refused")
	# Name-based path checks.
	check(_refusal(_with(good, "--games", ""), data).contains("empty"), "an empty --games is refused")
	check(_refusal(_with(good, "--games", "games.json"), data).contains("absolute or res://"), "a bare file name for --games is refused")
	check(_refusal(_with(good, "--data-root", "data"), data).contains("absolute or res://"), "a relative --data-root is refused")
	check(_refusal(_with(good, "--public-client-dir", iso + "/../public"), data).contains("'..'"), "a public folder that climbs out with .. is refused")
	check(_refusal(_with(good, "--games", "res://artifacts/framework-games.json"), data).contains("outside the isolation"), "a shared game index is refused")
	check(_refusal(_with(good, "--data-root", data.path_join("framework")), data).contains("outside the isolation"), "the real data root is refused")
	check(_refusal(_with(good, "--isolation", data.path_join("framework/x")), data).contains("not data/framework"), "an isolation folder inside data/framework is refused")
	check(_refusal(good + ["--operator-log-path=" + data.path_join("elsewhere.log")], data).contains("outside the isolation"), "an Operator log outside the isolation folder is refused")
	check(_refusal(good + ["--operator-log-path=" + iso.path_join("operator.log")], data) == "", "an Operator log inside the isolation folder is accepted")
	check(_refusal(_with(good, "--panel-port", "28291"), data).contains("panel-port"), "the production panel port is refused")
	check(_refusal(good.slice(0, 4), data).contains("panel-port"), "a missing panel port is refused")
	check(_refusal(good.slice(1), data).contains("--isolation is required"), "a missing isolation folder is refused")
	# Game index target.
	check(Isolation.index_target_refusal(iso.path_join("games.json"), iso) == "", "a new game index file inside the isolation folder may be written")
	var existing := iso.path_join("existing.json")
	var file := FileAccess.open(existing, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	check(Isolation.index_target_refusal(existing, iso).contains("already exists"), "an existing file is never overwritten as the game index")
	check(Isolation.index_target_refusal(iso.path_join("missing/games.json"), iso).contains("does not exist"), "a game index in a folder that does not exist is refused")
	check(Isolation.index_target_refusal(data.path_join("games.json"), iso).contains("outside"), "a game index outside the isolation folder is refused")
	# Links anywhere on the full target path (Linux: real symbolic links).
	if OS.get_name() == "Linux":
		var outside := data.path_join("isolation-rules-outside-" + Crypto.new().generate_random_bytes(6).hex_encode())
		DirAccess.make_dir_absolute(outside)
		var linked_dir := iso.path_join("linked")
		var made_dir := DirAccess.open(iso).create_link(outside, linked_dir) == OK
		check(made_dir and _refusal(_with(good, "--games", linked_dir.path_join("games.json")), data).contains("symbolic link"), "a --games path whose sub-folder is a link is refused (the full path is checked, not only the root)")
		check(made_dir and Isolation.index_target_refusal(linked_dir.path_join("games.json"), iso).contains("symbolic link") and not FileAccess.file_exists(outside.path_join("games.json")), "the game index is not written through a linked sub-folder")
		var linked_file := iso.path_join("games-link.json")
		var made_file := DirAccess.open(iso).create_link(outside.path_join("target.json"), linked_file) == OK
		check(made_file and Isolation.index_target_refusal(linked_file, iso).contains("symbolic link") and not FileAccess.file_exists(outside.path_join("target.json")), "a game index name that is itself a (dangling) link is refused and nothing is created behind it")
		check(made_dir and _refusal(_with(good, "--data-root", linked_dir.path_join("data")), data).contains("symbolic link"), "a --data-root below a linked sub-folder is refused")
		var linked_root := data.path_join("isolation-rules-root-link-" + Crypto.new().generate_random_bytes(6).hex_encode())
		var made_root := DirAccess.open(data).create_link(iso, linked_root) == OK
		var through := ["--isolation=" + linked_root, "--data-root=" + linked_root.path_join("data"), "--games=" + linked_root.path_join("games.json"), "--public-client-dir=" + linked_root.path_join("public"), "--panel-port=28391"]
		check(made_root and _refusal(through, data).contains("symbolic link"), "an isolation folder that is itself a link is refused")
		for path in [linked_dir, linked_file, linked_root]:
			DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(outside)
	else:
		not_run += 1
		print("NOT RUN symbolic link cases (Linux only; this is ", OS.get_name(), ")")
	for name in ["existing.json"]:
		DirAccess.remove_absolute(iso.path_join(name))
	DirAccess.remove_absolute(iso.path_join("data"))
	DirAccess.remove_absolute(iso)
	check(not DirAccess.dir_exists_absolute(iso), "the test's own folders are removed")
	print("OPERATOR_ISOLATION_RULES_RESULT passed=", passed, " failed=", failed, " not_run=", not_run)
	quit(0 if failed == 0 else 1)

func _refusal(args: Array, data: String) -> String:
	return str(Isolation.check(PackedStringArray(args), data).refusal)

func _with(args: Array, key: String, value: String) -> Array:
	var copy: Array = []
	for argument in args:
		copy.append(key + "=" + value if str(argument).begins_with(key + "=") else argument)
	return copy

func check(value: bool, text: String) -> void:
	if value:
		passed += 1
		print("PASS ", text)
	else:
		failed += 1
		print("FAIL ", text)

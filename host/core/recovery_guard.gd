extends RefCounted
## Persist reserved ports before spawning. Never adopt or kill previous-run PIDs.
## A previous run's entry keeps its port quarantined until a read-only check
## (ProcessLauncher.inspect_previous) reports the recorded process gone AND the
## port can be bound again. Entries without a usable identity (a crash before
## identity capture) stay quarantined. Linux: the journal folder is 700 and the
## journal 600 (posix_data_root.gd); the check reads /proc and the boot id only.
const DataRoot = preload("res://host/platform/posix_data_root.gd")
const PrivatePath = preload("res://host/platform/posix_private_path.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
var path := ""
var entries: Dictionary = {}
var orphans: Dictionary = {}
var ports
var worker: Thread
var checking := ""
var next_check := 0
var healthy := true
var cursor := 0
var exit_handler: Callable
var confirmed_exits: Dictionary = {}

func initialize(journal: String, allocator) -> bool:
	path = preload("res://sdk/roomkit/shared/paths.gd").absolute(journal)
	ports = allocator
	var output: Array = []
	if OS.get_name() == "Linux":
		if not DataRoot.prepare(path.get_base_dir()):
			return false
	elif OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/protect_data.ps1"), "-ProjectRoot", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://"), "-DataRoot", path.get_base_dir()], output) != 0:
		return false
	if FileAccess.file_exists(path):
		var record := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/process_journal.schema.json", 65536)
		if record.is_empty():
			return false
		entries = record.entries
		for id in entries:
			var entry: Dictionary = entries[id]
			if not entry.owned.is_empty() and entry.owned.get("launch_id", "") != id:
				return false
			if int(entry.port) < ports.first_port or int(entry.port) > ports.last_port:
				return false
			orphans[id] = entry
			ports.leases["orphan:" + id] = int(entry.port)
	return save()

func reserve(launch_id: String, port: int) -> bool:
	entries[launch_id] = {"port": port, "owned": {}}
	return save()

func confirm(launch_id: String, owned: Dictionary) -> bool:
	if not entries.has(launch_id):
		return false
	entries[launch_id].owned = owned.duplicate(true)
	return save()

func release(launch_id: String) -> void:
	entries.erase(launch_id)
	save()

func mark_exited(launch_id: String, observed_at: int) -> bool:
	if not entries.has(launch_id):
		return true
	if entries[launch_id].has("exit_confirmed_at") and healthy:
		return true
	if not entries[launch_id].has("exit_confirmed_at"):
		entries[launch_id].exit_confirmed_at = observed_at
	return save()

func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		healthy = false
		return false
	file.store_string(JSON.stringify({"version": 1, "entries": entries}))
	file.flush()
	file.close()
	if OS.get_name() == "Linux" and not PrivatePath.protect_file(path + ".tmp", path.get_base_dir()).ok:
		DirAccess.remove_absolute(path + ".tmp")
		healthy = false
		return false
	healthy = DirAccess.rename_absolute(path + ".tmp", path) == OK
	return healthy

func poll() -> void:
	if worker != null and not worker.is_alive():
		var inspected: Dictionary = worker.wait_to_finish()
		worker = null
		if inspected.get("state", "unknown") == "exited":
			confirmed_exits[checking] = true
		checking = ""
	for launch in confirmed_exits.keys():
		if not mark_exited(launch, int(entries[launch].get("exit_confirmed_at", Time.get_unix_time_from_system()))):
			continue
		if exit_handler.is_valid() and not exit_handler.call({"launch_id": launch, "exit_observed_at": entries[launch].exit_confirmed_at}):
			continue
		if ports.release("orphan:" + launch, true):
			confirmed_exits.erase(launch)
			orphans.erase(launch)
			entries.erase(launch)
			save()
	if worker != null or Time.get_ticks_msec() < next_check:
		return
	next_check = Time.get_ticks_msec() + 1000
	var ids: Array = orphans.keys()
	for offset in range(ids.size()):
		var id: String = ids[(cursor + offset) % ids.size()]
		if not confirmed_exits.has(id) and Launcher.inspectable(orphans[id].owned):
			cursor = (cursor + offset + 1) % ids.size()
			checking = id
			worker = Thread.new()
			if worker.start(_inspect.bind(orphans[id].owned.duplicate(true))) != OK:
				worker = null
			return

static func _inspect(owned: Dictionary) -> Dictionary:
	return Launcher.inspect_previous(owned)

func idle() -> bool:
	return worker == null and confirmed_exits.is_empty()

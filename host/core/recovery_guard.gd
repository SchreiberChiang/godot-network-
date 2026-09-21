extends RefCounted
## Persist reserved ports before spawning. Never adopt or kill previous-run PIDs.
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

func initialize(journal: String, allocator) -> bool:
	path = preload("res://sdk/roomkit/shared/paths.gd").absolute(journal)
	ports = allocator
	var output: Array = []
	if OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/protect_data.ps1"), "-ProjectRoot", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://"), "-DataRoot", path.get_base_dir()], output) != 0:
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

func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		healthy = false
		return false
	file.store_string(JSON.stringify({"version": 1, "entries": entries}))
	file.flush()
	file.close()
	healthy = DirAccess.rename_absolute(path + ".tmp", path) == OK
	return healthy

func poll() -> void:
	if worker != null and not worker.is_alive():
		var inspected: Dictionary = worker.wait_to_finish()
		worker = null
		if inspected.get("state", "unknown") == "exited" and ports.release("orphan:" + checking, true):
			orphans.erase(checking)
			entries.erase(checking)
			save()
		checking = ""
	if worker != null or Time.get_ticks_msec() < next_check:
		return
	next_check = Time.get_ticks_msec() + 1000
	var ids: Array = orphans.keys()
	for offset in range(ids.size()):
		var id: String = ids[(cursor + offset) % ids.size()]
		if orphans[id].owned.get("verified", false):
			cursor = (cursor + offset + 1) % ids.size()
			checking = id
			worker = Thread.new()
			if worker.start(_inspect.bind(orphans[id].owned.duplicate(true))) != OK:
				worker = null
			return

static func _inspect(owned: Dictionary) -> Dictionary:
	return Launcher.new()._inspect("inspect", owned)

func idle() -> bool:
	return worker == null

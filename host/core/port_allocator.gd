extends RefCounted
## Leases stay quarantined until process exit AND a fresh UDP bind succeeds.
## Probing cannot prevent another process taking the port before child startup;
## the child is responsible for binding its assigned port before reporting READY.

var leases: Dictionary = {}
var first_port: int
var last_port: int


func _init(range_first: int = 28100, range_last: int = 28131) -> void:
	first_port = range_first
	last_port = range_last


func acquire(launch_id: String) -> int:
	if launch_id.is_empty():
		return 0
	if leases.has(launch_id):
		return int(leases[launch_id])
	if first_port < 1 or last_port > 65535 or first_port > last_port:
		return 0
	for port: int in range(first_port, last_port + 1):
		if port in leases.values():
			continue
		if can_bind(port):
			leases[launch_id] = port
			return port
	return 0


func release(launch_id: String, process_exited: bool) -> bool:
	if not leases.has(launch_id):
		return false
	if not process_exited or not can_bind(int(leases[launch_id])):
		return false
	leases.erase(launch_id)
	return true


func can_bind(port: int) -> bool:
	if port < 1 or port > 65535:
		return false
	var probe := PacketPeerUDP.new()
	var result: int = probe.bind(port, "127.0.0.1")
	probe.close()
	return result == OK

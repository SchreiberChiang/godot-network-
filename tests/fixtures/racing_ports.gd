extends "res://host/core/port_allocator.gd"
## Simulate allocation/bind race; the competing UDP holder is a real process.
var raced_port := 0

func acquire(launch_id: String) -> int:
	leases[launch_id] = raced_port
	return raced_port

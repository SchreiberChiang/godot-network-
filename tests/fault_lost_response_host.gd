extends "res://host/managed_host.gd"
## All real host lifecycle, WSS/TLS, authentication, policy and RPC stay intact.
## Only the test's final WSS response boundary is substituted.
func _initialize() -> void:
	lobby = preload("res://tests/fault_lost_response_lobby.gd").new()
	super._initialize()
	lobby.evidence_path = str(bootstrap.result_root).path_join("lost-response.json")

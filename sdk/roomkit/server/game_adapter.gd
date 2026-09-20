extends RefCounted
## Games override these callbacks. No actor or scene base class is required.
func configure_room(_context: Dictionary) -> bool:
	return true

func on_player_admitted(_identity: Dictionary) -> void:
	pass

func on_player_left(_identity: Dictionary, _reason: String) -> void:
	pass

func on_shutdown_requested(_reason: String) -> void:
	pass

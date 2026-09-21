extends RefCounted
## Games override these callbacks. No actor or scene base class is required.
signal result_requested(match_key: String, status: String, payload: Dictionary)
signal asset_refresh_requested(user_id: String, operation: String)

func asset_context(_user_id: String) -> Dictionary:
	return {"location": "room"}

func on_asset_state(_user_id: String, _state: Dictionary) -> void:
	pass

func set_asset_busy(_user_id: String, _busy: bool) -> void:
	pass

func complete_asset_refresh(_user_id: String, _operation: String, _state: Dictionary) -> void:
	pass

func cancel_asset_refresh(_user_id: String, _operation: String) -> void:
	pass

func configure_room(_context: Dictionary) -> bool:
	return true

func on_player_admitted(_identity: Dictionary) -> void:
	pass

func on_player_left(_identity: Dictionary, _reason: String) -> void:
	pass

func on_shutdown_requested(_reason: String) -> void:
	pass

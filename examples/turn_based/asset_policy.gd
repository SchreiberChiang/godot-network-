extends "res://sdk/roomkit/server/asset_policy.gd"
## This game has no actor/death/weapon state. Theme changes are lobby-only.
func authorize(_identity: Dictionary, context: Dictionary, command: Dictionary) -> String:
	if command.get("kind", "") in ["read", "purchase", "select"] and context.get("location", "") == "lobby":
		return ""
	return "ASSET_OPERATION_DENIED"

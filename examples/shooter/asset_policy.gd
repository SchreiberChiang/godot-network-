extends "res://sdk/roomkit/server/asset_policy.gd"
## Called with trusted server context. The network/room gate is implemented separately.
func authorize(_identity: Dictionary, context: Dictionary, command: Dictionary) -> String:
	if command.get("kind", "") not in ["purchase", "select"]:
		return "ASSET_OPERATION_DENIED"
	if context.get("location", "") == "lobby":
		return ""
	if context.get("location", "") == "room" and context.get("life_state", "") == "dead":
		return ""
	return "ASSET_OPERATION_DENIED"

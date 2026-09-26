extends "res://sdk/roomkit/server/asset_policy.gd"
## This project's rules are replaceable without changing the host or SDK.
func authorize(_identity: Dictionary, context: Dictionary, command: Dictionary) -> String:
	if command.get("kind", "") == "read":
		return ""
	if context.get("location", "") == "lobby" and command.get("kind", "") in ["purchase", "select"]:
		return ""
	return "ASSET_OPERATION_DENIED"

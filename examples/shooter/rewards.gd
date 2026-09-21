extends RefCounted
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")

# Runs only in the trusted host after result provenance/schema validation.
# The room's claimed credits are informational, never an input to a wallet write.
static func calculate(record: Dictionary) -> Array:
	if record.get("game_id", "") != "shooter" or record.get("status", "") != "completed":
		return []
	var payload: Variant = record.get("payload", {})
	if Validator.validate_file(payload, "res://schemas/shooter_result.schema.json") != "":
		return []
	var duration := int(payload.duration_ms)
	if duration < 60000:
		return []
	var rewards: Array = []
	var seen: Dictionary = {}
	for player in payload.players:
		if seen.has(player.user_id) or int(player.participation_ms) > duration:
			return []
		seen[player.user_id] = true
		if int(player.participation_ms) >= 60000:
			rewards.append({"user_id": player.user_id, "credits": 20 + int(player.kills) * 5, "experience": 0})
	return rewards

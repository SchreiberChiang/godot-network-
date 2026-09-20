extends "res://host/core/result_service.gd"
var lose_first_ack := true
var block_before_commit := false
var received := 0

func handle(row: Dictionary, message: Dictionary) -> bool:
	received += 1
	if block_before_commit:
		return true
	return super.handle(row, message)

func _send_ack(room_id: String, payload: Dictionary) -> void:
	if lose_first_ack:
		lose_first_ack = false
		return
	super._send_ack(room_id, payload)

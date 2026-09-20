extends RefCounted
const Blocks = preload("res://examples/blocks/game.gd")
const Turns = preload("res://examples/turn_based/game.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0

func run() -> Dictionary:
	var blocks = Blocks.new()
	check(not blocks.handle_input(2, {"sequence": 1, "x": 1, "y": 0}, 0), "unauthorized peer cannot move")
	blocks.admit({"user_id": "alice", "display_name": "Alice"}, 2)
	blocks.admit({"user_id": "bob", "display_name": "Bob"}, 3)
	check(not blocks.handle_input(2, {"sequence": 1, "x": NAN, "y": 0}, 1), "non-finite movement refused")
	check(not blocks.handle_input(2, {"sequence": 1, "x": 2, "y": 0}, 1), "oversized movement refused")
	check(not blocks.handle_input(2, {"sequence": 1, "x": 1, "y": 0, "user_id": "bob"}, 1), "identity injection refused")
	check(blocks.handle_input(2, {"sequence": 1, "x": 1, "y": 1}, 1), "valid input accepted")
	var before: Vector2 = blocks.players.alice.position
	blocks.advance(51)
	check(is_equal_approx(before.distance_to(blocks.players.alice.position), 9.0), "diagonal speed normalized to fixed server step")
	check(not blocks.handle_input(2, {"sequence": 1, "x": -1, "y": 0}, 52), "stale sequence cannot reverse direction")
	before = blocks.players.alice.position
	blocks.advance(300)
	check(before == blocks.players.alice.position, "missing input stops after deadline")
	check(blocks.players.bob.position == Vector2(152, 180), "input cannot move another identity")
	for index in 80:
		blocks.handle_input(2, {"sequence": 2 + index, "x": 1, "y": 0}, 1000)
	check(blocks.players.alice.received > 60 and blocks.players.alice.sequence <= 61, "input flood bounded per player")
	blocks.players.alice.position = Vector2(695, 335)
	blocks.handle_input(2, {"sequence": 100, "x": 1, "y": 1}, 2000)
	blocks.advance(2000)
	check(blocks.players.alice.position.x <= 696 and blocks.players.alice.position.y <= 336, "server clamps arena bounds")
	check(Validator.validate_file(blocks.state_snapshot(), "res://schemas/blocks_state.schema.json") == "", "block snapshot matches contract")
	blocks.remove_player("alice")
	check(not blocks.handle_input(2, {"sequence": 101, "x": 1, "y": 0}, 3000), "departed identity loses input authority")
	blocks.free()
	var turns = Turns.new()
	turns.admit({"user_id": "alice", "display_name": "Alice"}, 2)
	check(not turns.handle_input(2, {"turn": 1, "take": 2}), "single player waits for opponent")
	turns.admit({"user_id": "bob", "display_name": "Bob"}, 3)
	check(not turns.handle_input(9, {"turn": 1, "take": 1}), "unknown peer cannot choose")
	check(not turns.handle_input(3, {"turn": 1, "take": 1}), "out-of-turn choice refused")
	check(not turns.handle_input(2, {"turn": 1, "take": 99}), "invalid take count refused")
	check(turns.handle_input(2, {"turn": 1, "take": 2}), "active player takes two")
	check(not turns.handle_input(2, {"turn": 1, "take": 2}) and turns.stones == 10, "duplicate command cannot apply twice")
	for i in range(2, 7):
		turns.handle_input(3 if i % 2 == 0 else 2, {"turn": i, "take": 2})
	check(turns.round_number == 2 and turns.stones == 12 and turns.players.bob.score == 1, "last stone scores once and starts next round")
	turns.remove_player("alice")
	check(turns.active_user == "bob" and turns.order.size() == 1, "active player departure advances ownership")
	check(not turns.handle_input(2, {"turn": turns.turn, "take": 1}), "departed player cannot act")
	check(Validator.validate_file(turns.state_snapshot(), "res://schemas/turns_state.schema.json") == "", "turn snapshot matches contract")
	turns.free()
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://examples/gameplay_messages.example.json"))
	for example in examples:
		check(Validator.validate_file(example.message, "res://schemas/" + example.schema + ".schema.json") == "", "documented gameplay example " + example.schema)
	check(Validator.validate_file({"turn": 1, "take": 1.5}, "res://schemas/turns_input.schema.json") != "", "fractional take count refused")
	return {"passed": passed, "failed": failed}

func check(value: bool, description: String) -> void:
	if value:
		passed += 1
		print("PASS gameplay: ", description)
	else:
		failed += 1
		printerr("FAIL gameplay: ", description)

extends RefCounted
## Godot JSON accepts trailing commas; check strict wire grammar before parsing.
static func valid(text: String, max_depth: int = 16) -> bool:
	var end := _value(text, _space(text, 0), 0, max_depth)
	return end >= 0 and _space(text, end) == text.length()

static func _space(text: String, index: int) -> int:
	while index < text.length() and text[index] in " \t\r\n":
		index += 1
	return index

static func _string(text: String, index: int) -> int:
	index += 1
	while index < text.length():
		var character := text[index]
		if character == "\"":
			return index + 1
		if text.unicode_at(index) < 32:
			return -1
		if character == "\\":
			index += 1
			if index >= text.length():
				return -1
			if text[index] == "u":
				for offset in range(1, 5):
					if index + offset >= text.length() or not text[index + offset] in "0123456789abcdefABCDEF":
						return -1
				index += 4
			elif not text[index] in "\"\\/bfnrt":
				return -1
		index += 1
	return -1

static func _value(text: String, index: int, depth: int, limit: int) -> int:
	index = _space(text, index)
	if index >= text.length() or depth > limit:
		return -1
	var character := text[index]
	if character == "\"":
		return _string(text, index)
	if character == "{" or character == "[":
		if depth >= limit:
			return -1
		var close := "}" if character == "{" else "]"
		var object := character == "{"
		index = _space(text, index + 1)
		if index < text.length() and text[index] == close:
			return index + 1
		while index < text.length():
			if object:
				if text[index] != "\"":
					return -1
				index = _string(text, index)
				if index < 0:
					return -1
				index = _space(text, index)
				if index >= text.length() or text[index] != ":":
					return -1
				index += 1
			index = _value(text, index, depth + 1, limit)
			if index < 0:
				return -1
			index = _space(text, index)
			if index >= text.length():
				return -1
			if text[index] == close:
				return index + 1
			if text[index] != ",":
				return -1
			index = _space(text, index + 1)
			if index >= text.length() or text[index] == close:
				return -1
		return -1
	for literal in ["true", "false", "null"]:
		if text.substr(index, literal.length()) == literal:
			return index + literal.length()
	var expression := RegEx.new()
	expression.compile("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
	var found := expression.search(text.substr(index))
	return index + found.get_string().length() if found != null else -1

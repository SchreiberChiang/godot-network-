extends RefCounted
## JSON Schema subset used by this repository; schemas/ remains authoritative.
static var _cache: Dictionary = {}

static func validate_file(value: Variant, path: String) -> String:
	if not _cache.has(path):
		if not FileAccess.file_exists(path):
			return "SCHEMA_MISSING"
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			return "SCHEMA_INVALID"
		_cache[path] = parsed
	return _validate(value, _cache[path], _cache[path], path, 0)

static func validate(value: Variant, schema: Dictionary) -> String:
	return _validate(value, schema, schema, "res://schemas/envelope.schema.json", 0)

static func _validate(value: Variant, schema: Variant, root: Dictionary, path: String, depth: int) -> String:
	if depth > 96:
		return "SCHEMA_DEPTH"
	if schema is bool:
		return "" if schema else "SCHEMA_REJECTED"
	if not schema is Dictionary:
		return "SCHEMA_INVALID"
	if schema.has("$ref"):
		var ref: String = schema["$ref"]
		var pieces := ref.split("#", true, 1)
		var ref_root: Dictionary = root
		var ref_path := path
		if pieces[0] != "":
			ref_path = path.get_base_dir().path_join(pieces[0])
			if not _cache.has(ref_path):
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ref_path))
				if not parsed is Dictionary:
					return "SCHEMA_INVALID_REF"
				_cache[ref_path] = parsed
			ref_root = _cache[ref_path]
		var target: Variant = ref_root
		if pieces.size() == 2 and pieces[1] != "":
			for part in pieces[1].trim_prefix("/").split("/"):
				var key := part.replace("~1", "/").replace("~0", "~")
				if not target is Dictionary or not target.has(key):
					return "SCHEMA_INVALID_REF"
				target = target[key]
		var ref_error := _validate(value, target, ref_root, ref_path, depth + 1)
		if ref_error != "":
			return ref_error
	if schema.has("type") and not _type_matches(value, schema.type):
		return "INVALID_TYPE"
	if schema.has("const") and value != schema["const"]:
		return "INVALID_CONST"
	if schema.has("enum") and not value in schema["enum"]:
		return "INVALID_ENUM"
	for branch in schema.get("allOf", []):
		var error := _validate(value, branch, root, path, depth + 1)
		if error != "":
			return error
	for keyword in ["anyOf", "oneOf"]:
		if schema.has(keyword):
			var count := 0
			for branch in schema[keyword]:
				if _validate(value, branch, root, path, depth + 1) == "":
					count += 1
			if count == 0 or (keyword == "oneOf" and count != 1):
				return "INVALID_ALTERNATIVE"
	if schema.has("not") and _validate(value, schema["not"], root, path, depth + 1) == "":
		return "FORBIDDEN_FIELD"
	if schema.has("if"):
		var branch: String = "then" if _validate(value, schema["if"], root, path, depth + 1) == "" else "else"
		if schema.has(branch):
			var error := _validate(value, schema[branch], root, path, depth + 1)
			if error != "":
				return error
	if value is Dictionary:
		for key in schema.get("required", []):
			if not value.has(key):
				return "MISSING_FIELD"
		if value.size() < int(schema.get("minProperties", 0)) or value.size() > int(schema.get("maxProperties", 2147483647)):
			return "PROPERTY_COUNT"
		var properties: Dictionary = schema.get("properties", {})
		for key in value:
			if not key is String and not key is StringName:
				return "INVALID_PROPERTY"
			if schema.has("propertyNames") and _validate(str(key), schema.propertyNames, root, path, depth + 1) != "":
				return "INVALID_PROPERTY"
			var child: Variant = properties.get(key, schema.get("additionalProperties", true))
			var error := _validate(value[key], child, root, path, depth + 1)
			if error != "":
				return error
	if value is Array:
		if value.size() < int(schema.get("minItems", 0)) or value.size() > int(schema.get("maxItems", 2147483647)):
			return "ITEM_COUNT"
		for index in range(value.size()):
			if schema.get("uniqueItems", false) and value.find(value[index]) != index:
				return "DUPLICATE_ITEM"
			var error := _validate(value[index], schema.get("items", true), root, path, depth + 1)
			if error != "":
				return error
	if value is String:
		if value.length() < int(schema.get("minLength", 0)) or value.length() > int(schema.get("maxLength", 2147483647)):
			return "STRING_LENGTH"
		if schema.has("pattern"):
			var regex := RegEx.new()
			if regex.compile(schema.pattern) != OK or regex.search(value) == null:
				return "STRING_PATTERN"
	if value is int or value is float:
		if not is_finite(float(value)):
			return "NON_FINITE"
		if value < schema.get("minimum", -INF) or value > schema.get("maximum", INF):
			return "NUMBER_RANGE"
	return ""

static func _type_matches(value: Variant, type: Variant) -> bool:
	if type is Array:
		for item in type:
			if _type_matches(value, item):
				return true
		return false
	match type:
		"object": return value is Dictionary
		"array": return value is Array
		"string": return value is String
		"boolean": return value is bool
		"null": return value == null
		"number": return (value is int or value is float) and is_finite(float(value))
		"integer": return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
	return false

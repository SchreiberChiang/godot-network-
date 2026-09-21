extends RefCounted
## Override on the server. Context comes from server-owned state, not request JSON.
## Deny by default. A successful policy check is not a durable transaction receipt.
func authorize(_identity: Dictionary, _context: Dictionary, _command: Dictionary) -> String:
	return "ASSET_OPERATION_DENIED"

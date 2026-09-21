extends RefCounted

static func server_options(settings: Dictionary) -> TLSOptions:
	var key := CryptoKey.new()
	var certificate := X509Certificate.new()
	if key.load(settings.get("key", "")) != OK or certificate.load(settings.get("certificate", "")) != OK:
		return null
	return TLSOptions.server(key, certificate)

static func client_options(ca_path: String, server_name: String = "") -> TLSOptions:
	var certificate := X509Certificate.new()
	if ca_path.is_empty() or certificate.load(ca_path) != OK:
		return null
	return TLSOptions.client(certificate, server_name)

static func create_local_certificate(directory: String) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {}
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var certificate := crypto.generate_self_signed_certificate(key, "CN=localhost,O=RoomKit Local", "20200101000000", "20300101000000")
	var result := {"key": directory.path_join("server.key"), "certificate": directory.path_join("server.crt"), "hostname": "localhost"}
	if key.save(result.key) != OK or certificate.save(result.certificate) != OK:
		return {}
	return result

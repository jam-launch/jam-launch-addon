class_name JamJwt
extends RefCounted

signal token_changed(jwt_token: String)

var username: String:
	get:
		return claims.get("username", "")

var jwt_token: String = ""
var claims: Dictionary = {}

func set_token(jwt: String) -> TokenParseResult:
	var result: TokenParseResult = JamJwt.parse_token(jwt)
	if result.errored:
		return result
	jwt_token = jwt
	claims = result.data.claims
	token_changed.emit(jwt_token)
	return result


func get_token() -> String:
	return jwt_token


func clear() -> void:
	jwt_token = ""
	token_changed.emit("")


func has_token() -> bool:
	return len(jwt_token) > 0


static func b64url_to_b64(b64_url: String) -> String:
	var b64: String = b64_url
	b64 = b64.replace("-", "+")
	b64 = b64.replace("_", "/")
	var overhang: int = len(b64) % 4
	if not overhang == 0:
		for i: int in range(4 - overhang):
			b64 += "="
	return b64


static func parse_token(token: String) -> TokenParseResult:
	var result: TokenParseResult = TokenParseResult.new()
	var parts: PackedStringArray = token.split(".")
	if not len(parts) == 3:
		result.errored = true
		result.error = "Invalid JWT token format"
		return result
	
	var tkn: TokenData = TokenData.new()
	var header_b64: String = b64url_to_b64(parts[0])
	var header_json: String = Marshalls.base64_to_utf8(header_b64)
	var header: Dictionary = JSON.parse_string(header_json)
	if header == null:
		result.errored = true
		result.error = "Failed to parse JWT header"
		return result

	tkn.header = header
	var claims_b64: String = b64url_to_b64(parts[1])
	var claims_json: String = Marshalls.base64_to_utf8(claims_b64)
	var jwt_claims: Variant = JSON.parse_string(claims_json)
	if jwt_claims == null:
		result.errored = true
		result.error = "Failed to parse JWT claims"
		return result

	tkn.claims = jwt_claims
	var sig_b64: String = b64url_to_b64(parts[2])
	var raw_sig: PackedByteArray = Marshalls.base64_to_raw(sig_b64)
	if not raw_sig or raw_sig.is_empty():
		result.errored = true
		result.error = "Failed to parse JWT signature"
		return result
		
	tkn.signature = parts[2]
	result.data = tkn
	return result


class TokenData:
	extends RefCounted
	var header: Dictionary
	var claims: Dictionary
	var signature: String


class TokenParseResult:
	extends RefCounted
	var error: String = ""
	var errored: bool = false
	var data: TokenData

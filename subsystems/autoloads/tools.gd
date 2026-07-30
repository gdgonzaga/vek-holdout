extends Node
## General utility functions and helper methods shared across subsystems.

var _crypto := Crypto.new()

## Generates a cryptographically random RFC 4122 compliant UUID v4 string.
## Example output: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
func generate_uuid() -> String:
	var bytes := _crypto.generate_random_bytes(16)
	
	# Set UUID v4 version (bits 4-7 of byte 6 set to 0100)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	# Set RFC 4122 variant (bits 6-7 of byte 8 set to 10)
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		bytes[0], bytes[1], bytes[2], bytes[3],
		bytes[4], bytes[5],
		bytes[6], bytes[7],
		bytes[8], bytes[9],
		bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
	]

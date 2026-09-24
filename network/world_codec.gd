extends RefCounted
const CHUNK_SIZE := 700
var assemblies: Dictionary = {}

func receive(packet: Dictionary) -> String:
	if not packet.has("chunk"): return str(packet.get("world",""))
	var tick := int(packet.get("tick",-1))
	var index := int(packet.get("chunk",-1))
	var count := int(packet.get("chunks",0))
	var data := str(packet.get("data",""))
	if tick<0 or count<1 or count>86 or index<0 or index>=count or data.length()>CHUNK_SIZE: return ""
	if not assemblies.has(tick): assemblies[tick] = {"count":count,"parts":{}}
	while assemblies.size()>8: assemblies.erase(assemblies.keys()[0])
	if not assemblies.has(tick) or int(assemblies[tick].count)!=count: return ""
	var parts: Dictionary = assemblies[tick].parts
	parts[index] = data
	if parts.size()!=count: return ""
	var encoded := ""
	for i in count: encoded += str(parts[i])
	assemblies.erase(tick)
	return encoded

static func fragments(encoded: String) -> Array:
	var result: Array = []
	var count := int(ceil(float(encoded.length())/CHUNK_SIZE))
	for i in count: result.append({"chunk":i,"chunks":count,"data":encoded.substr(i*CHUNK_SIZE,CHUNK_SIZE)})
	return result
## Never decode objects; cap decompressed size before parsing Variant data.
static func pack(world: Dictionary) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(world).compress(FileAccess.COMPRESSION_DEFLATE))

static func unpack(encoded: String) -> Dictionary:
	if encoded.length()>60000: return {}
	var bytes := Marshalls.base64_to_raw(encoded).decompress_dynamic(1048576,FileAccess.COMPRESSION_DEFLATE)
	if bytes.is_empty(): return {}
	var value = bytes_to_var(bytes)
	return value if value is Dictionary else {}

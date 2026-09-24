extends RefCounted

## Bounded reliable ordered lane over the room's UDP socket.
## Client commands and server-critical results use it. Snapshots and combat presentation bypass it.
const WINDOW := 64
const RETRY_MS := 120
var next_send := 1
var next_receive := 1
var pending: Dictionary = {}
var waiting: Dictionary = {}

func queue(payload: Dictionary) -> bool:
	if pending.size() >= WINDOW:
		return false
	pending[next_send] = {"payload": payload.duplicate(true), "sent": -RETRY_MS}
	next_send += 1
	return true

func outgoing(now: int) -> Array:
	var result: Array = []
	for id in pending:
		if now - int(pending[id].sent) >= RETRY_MS:
			pending[id].sent = now
			result.append({"reliable": id, "payload": pending[id].payload})
	return result

func acknowledge(id: int) -> void:
	pending.erase(id)

func receive(id: int, payload: Dictionary) -> Array:
	if id < next_receive or id >= next_receive + WINDOW:
		return []
	waiting[id] = payload
	var result: Array = []
	while waiting.has(next_receive):
		result.append(waiting[next_receive])
		waiting.erase(next_receive)
		next_receive += 1
	return result

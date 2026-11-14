extends Node
## Optional live request to NASA's DONKI flare API (last 30 days).
## Status is "pending", "live" or "unavailable". Live data is only reported
## as live after a successful, parsed response.

signal finished(status: String)

const ENDPOINT := "https://api.nasa.gov/DONKI/FLR?startDate=%s&endDate=%s&api_key=DEMO_KEY"
const TIMEOUT_SECONDS := 10.0

var status := "idle"
var flare_count := 0
var strongest := {}
var _request: HTTPRequest


func fetch() -> void:
	if status == "pending" or status == "live":
		return
	status = "pending"
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT_SECONDS
	add_child(_request)
	_request.request_completed.connect(_on_completed)
	var now := int(Time.get_unix_time_from_system())
	var start := Time.get_date_string_from_unix_time(now - 30 * 86400)
	var end := Time.get_date_string_from_unix_time(now)
	var error := _request.request(ENDPOINT % [start, end])
	if error != OK:
		_finish("unavailable")


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish("unavailable")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Array:
		_finish("unavailable")
		return
	flare_count = 0
	strongest = {}
	var best_score := -1.0
	for item: Variant in parsed:
		if not item is Dictionary:
			continue
		var class_type := str(item.get("classType", ""))
		if class_type.is_empty():
			continue
		flare_count += 1
		var score := class_score(class_type)
		if score > best_score:
			best_score = score
			strongest = {"class": class_type, "date": str(item.get("beginTime", "")).substr(0, 10), "id": str(item.get("flrID", ""))}
	_finish("live")


func _finish(new_status: String) -> void:
	status = new_status
	if _request != null:
		_request.queue_free()
		_request = null
	finished.emit(status)


static func class_score(class_type: String) -> float:
	var letter := class_type.substr(0, 1).to_upper()
	var magnitude := class_type.substr(1).to_float()
	var base := {"A": 0.0, "B": 10.0, "C": 20.0, "M": 30.0, "X": 40.0}
	return float(base.get(letter, 0.0)) + minf(magnitude, 9.99)


## A space-weather event built from the strongest live flare, or {}.
func live_event() -> Dictionary:
	if status != "live" or strongest.is_empty():
		return {}
	var class_type := str(strongest.get("class", ""))
	var letter := class_type.substr(0, 1).to_upper()
	if letter != "X" and letter != "M":
		return {}
	var power := 0
	var magnitude := class_type.substr(1).to_float()
	if letter == "X":
		power = clampi(20 + roundi(magnitude * 1.6), 20, 38)
	else:
		power = clampi(10 + roundi(magnitude), 10, 20)
	return {
		"id": str(strongest.get("id", "live")),
		"type": "FLR",
		"date": str(strongest.get("date", "")),
		"class": class_type,
		"headline": "%s solar flare (this month!)" % class_type,
		"detail": "This flare really happened on %s. NASA DONKI recorded %d flares in the last 30 days." % [str(strongest.get("date", "")), flare_count],
		"power": power,
		"live": true,
	}


func summary_text() -> String:
	match status:
		"pending":
			return "Checking today's Sun with NASA DONKI..."
		"live":
			if strongest.is_empty():
				return "LIVE from NASA DONKI: no solar flares in the last 30 days. A calm Sun!"
			return "LIVE from NASA DONKI: %d solar flares in the last 30 days. Strongest: %s on %s." % [flare_count, str(strongest.get("class", "")), str(strongest.get("date", ""))]
		"unavailable":
			return "Live NASA data unavailable right now. Using ARCHIVED real events from NASA DONKI."
		_:
			return "Space weather: ARCHIVED real events from NASA DONKI."

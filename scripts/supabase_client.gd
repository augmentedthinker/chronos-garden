class_name SupabaseClient
extends Node

## Lightweight HTTP REST client for Supabase PostgREST tables.
## Works universally on Native Desktop (Linux/macOS/Windows) and Web (HTML5/GitHub Pages).

signal connection_tested(is_connected: bool, status_message: String)

@export var supabase_url: String = ""
@export var supabase_anon_key: String = ""

func is_configured() -> bool:
	return supabase_url.strip_edges().length() > 0 and supabase_anon_key.strip_edges().length() > 0

func set_credentials(url: String, anon_key: String) -> void:
	supabase_url = url.strip_edges().rstrip("/")
	supabase_anon_key = anon_key.strip_edges()

func _get_headers() -> PackedStringArray:
	var headers = PackedStringArray()
	headers.append("apikey: " + supabase_anon_key)
	headers.append("Authorization: Bearer " + supabase_anon_key)
	headers.append("Content-Type: application/json")
	headers.append("Prefer: return=representation")
	return headers

func _send_request(endpoint: String, method: HTTPClient.Method, body: String = "", prefer_header: String = "return=representation") -> Dictionary:
	if not is_configured():
		return {
			"success": false,
			"status": 0,
			"data": null,
			"error": "Supabase credentials not configured."
		}

	var http = HTTPRequest.new()
	if OS.has_feature("web"):
		http.accept_gzip = false
	add_child(http)

	var req_headers = _get_headers()
	if prefer_header != "":
		req_headers.append("Prefer: " + prefer_header)

	var full_url = supabase_url + "/rest/v1/" + endpoint
	var err = http.request(full_url, req_headers, method, body)
	if err != OK:
		http.queue_free()
		return {
			"success": false,
			"status": 0,
			"data": null,
			"error": "HTTPRequest initiation failed with code: " + str(err)
		}

	var result = await http.request_completed
	http.queue_free()

	var res_code = result[1]
	var raw_body = result[3].get_string_from_utf8()
	var parsed_data = null

	if raw_body.length() > 0:
		var json = JSON.new()
		if json.parse(raw_body) == OK:
			parsed_data = json.get_data()

	var is_ok = (res_code >= 200 and res_code < 300)
	var err_msg = ""
	if not is_ok:
		if res_code == 401 or res_code == 403:
			err_msg = "Supabase Auth Error (HTTP %d). Check your publishable/anon key." % res_code
		elif res_code == 404:
			err_msg = "Table not found (HTTP 404). Ensure schema.sql has been run in Supabase SQL editor."
		else:
			err_msg = "HTTP %d: %s" % [res_code, raw_body]

	return {
		"success": is_ok,
		"status": res_code,
		"data": parsed_data,
		"raw": raw_body,
		"error": err_msg
	}

## Test credentials by pinging garden_state table
func test_connection() -> Dictionary:
	var res = await _send_request("garden_state?select=id&limit=1", HTTPClient.METHOD_GET)
	var connected = res.success
	var msg = "Connected to Supabase cloud database." if connected else ("Connection error: " + res.error)
	connection_tested.emit(connected, msg)
	return res

## Fetch the singleton world state record
func get_garden_state(world_id: String = "main_garden") -> Dictionary:
	var res = await _send_request("garden_state?id=eq." + world_id + "&select=*", HTTPClient.METHOD_GET)
	if res.success and res.data is Array and res.data.size() > 0:
		return {"success": true, "data": res.data[0], "error": ""}
	elif res.success and res.data is Array and res.data.size() == 0:
		# Table exists but no row yet
		return {"success": true, "data": null, "error": "No world state found"}
	else:
		return {"success": false, "data": null, "error": res.error}

## Update world state
func update_garden_state(world_id: String, patch_data: Dictionary) -> Dictionary:
	patch_data["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"
	var body = JSON.stringify(patch_data)
	return await _send_request("garden_state?id=eq." + world_id, HTTPClient.METHOD_PATCH, body)

## Create initial world state if missing
func insert_garden_state(initial_state: Dictionary) -> Dictionary:
	var body = JSON.stringify(initial_state)
	return await _send_request("garden_state", HTTPClient.METHOD_POST, body, "resolution=merge-duplicates")

## Fetch chronological event log
func get_events(world_id: String = "main_garden", limit: int = 50) -> Dictionary:
	var endpoint = "garden_events?world_id=eq.%s&order=id.asc&limit=%d" % [world_id, limit]
	var res = await _send_request(endpoint, HTTPClient.METHOD_GET)
	if res.success and res.data is Array:
		return {"success": true, "events": res.data, "error": ""}
	return {"success": false, "events": [], "error": res.error}

## Insert a single event
func insert_event(event_dict: Dictionary) -> Dictionary:
	var body = JSON.stringify(event_dict)
	return await _send_request("garden_events", HTTPClient.METHOD_POST, body)

## Clear all events and reset world state (for debug/testing)
func reset_cloud_world(world_id: String = "main_garden", max_plots: int = 12, interval_sec: int = 600) -> Dictionary:
	var del_res = await _send_request("garden_events?world_id=eq." + world_id, HTTPClient.METHOD_DELETE)
	var now_iso = Time.get_datetime_string_from_system(true) + "Z"
	var reset_state = {
		"id": world_id,
		"total_plants": 0,
		"last_planted_at": now_iso,
		"last_saved_at": now_iso,
		"planting_interval_seconds": interval_sec,
		"max_plots": max_plots,
		"active_plots": []
	}
	var update_res = await _send_request("garden_state?id=eq." + world_id, HTTPClient.METHOD_PATCH, JSON.stringify(reset_state))
	return {"success": update_res.success, "error": update_res.error}

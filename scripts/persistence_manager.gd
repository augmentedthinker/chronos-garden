class_name PersistenceManager
extends Node

## Unified persistence manager that bridges Godot simulation with Supabase Cloud
## and provides seamless local JSON fallback.

signal status_updated(connected: bool, provider: String, message: String)

const CONFIG_FILE = "user://supabase_config.json"
const LOCAL_STATE_FILE = "user://garden_state.json"
const LOCAL_EVENTS_FILE = "user://garden_events.json"

@onready var supabase: SupabaseClient = $SupabaseClient

var is_cloud_active: bool = false
var last_status_message: String = "Initializing..."

func _ready() -> void:
	load_and_apply_config()

## Load credentials from disk
func load_and_apply_config() -> Dictionary:
	var cfg = {
		"supabase_url": "https://egdxqmldflwgvasrabbx.supabase.co",
		"supabase_anon_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnZHhxbWxkZmx3Z3Zhc3JhYmJ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkwMTg1MzQsImV4cCI6MjEwNDU5NDUzNH0.1VC4pg42yul8EBjhB7-q5dBdfihrOxnZA5UuEAGGAlw"
	}
	if FileAccess.file_exists(CONFIG_FILE):
		var f = FileAccess.open(CONFIG_FILE, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			var json = JSON.new()
			if json.parse(txt) == OK and json.get_data() is Dictionary:
				cfg = json.get_data()
			f.close()

	if supabase:
		supabase.set_credentials(cfg.get("supabase_url", ""), cfg.get("supabase_anon_key", ""))
	return cfg

## Save credentials to disk
func save_config(url: String, anon_key: String) -> void:
	var cfg = {
		"supabase_url": url.strip_edges(),
		"supabase_anon_key": anon_key.strip_edges()
	}
	var f = FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "\t"))
		f.close()
	if supabase:
		supabase.set_credentials(cfg["supabase_url"], cfg["supabase_anon_key"])

## Load world state and event history
func load_world(world_id: String = "main_garden") -> Dictionary:
	# 1. Attempt Supabase Cloud load if configured
	if supabase and supabase.is_configured():
		var cloud_res = await supabase.get_garden_state(world_id)
		if cloud_res.success and cloud_res.data != null:
			var ev_res = await supabase.get_events(world_id, 100)
			is_cloud_active = true
			last_status_message = "Synced with Supabase Cloud"
			status_updated.emit(true, "Supabase", last_status_message)
			# Cache locally for resilience
			_save_local_state(cloud_res.data)
			_save_local_events(ev_res.events)
			return {
				"state": cloud_res.data,
				"events": ev_res.events,
				"source": "supabase"
			}
		elif cloud_res.success and cloud_res.data == null:
			# Table exists in Supabase but is empty; seed initial state
			var init_state = _create_default_state(world_id)
			await supabase.insert_garden_state(init_state)
			is_cloud_active = true
			last_status_message = "Initialized new Supabase Garden"
			status_updated.emit(true, "Supabase", last_status_message)
			return {
				"state": init_state,
				"events": [],
				"source": "supabase"
			}
		else:
			print("Supabase load failed: ", cloud_res.error, " Falling back to local storage.")
			is_cloud_active = false
			last_status_message = "Cloud error: " + cloud_res.error
			status_updated.emit(false, "Local", last_status_message)

	# 2. Local Fallback
	is_cloud_active = false
	last_status_message = "Operating in Local Sandbox Mode"
	status_updated.emit(false, "Local", last_status_message)
	var local_state = _load_local_state(world_id)
	var local_events = _load_local_events()
	return {
		"state": local_state,
		"events": local_events,
		"source": "local"
	}

## Save world state
func save_state(world_id: String, state_data: Dictionary) -> void:
	# Always save locally
	_save_local_state(state_data)
	
	# Sync to Supabase if active
	if is_cloud_active and supabase and supabase.is_configured():
		var patch = {
			"total_plants": state_data.get("total_plants", 0),
			"last_planted_at": state_data.get("last_planted_at", ""),
			"last_saved_at": Time.get_datetime_string_from_system(true) + "Z",
			"planting_interval_seconds": state_data.get("planting_interval_seconds", 600),
			"max_plots": state_data.get("max_plots", 12),
			"active_plots": state_data.get("active_plots", [])
		}
		supabase.update_garden_state(world_id, patch)

## Log an event
func record_event(event_data: Dictionary) -> void:
	# Append locally
	var events = _load_local_events()
	events.append(event_data)
	_save_local_events(events)

	# Insert to Supabase if active
	if is_cloud_active and supabase and supabase.is_configured():
		supabase.insert_event(event_data)

## Reset world state
func reset_world(world_id: String = "main_garden", interval_sec: int = 600, max_plots: int = 12) -> Dictionary:
	var init_state = _create_default_state(world_id, interval_sec, max_plots)
	_save_local_state(init_state)
	_save_local_events([])

	if is_cloud_active and supabase and supabase.is_configured():
		await supabase.reset_cloud_world(world_id, max_plots, interval_sec)

	return init_state

# --- Private Local Storage Helpers ---

func _create_default_state(world_id: String, interval_sec: int = 600, max_plots: int = 12) -> Dictionary:
	var now_iso = Time.get_datetime_string_from_system(true) + "Z"
	return {
		"id": world_id,
		"total_plants": 0,
		"last_planted_at": now_iso,
		"last_saved_at": now_iso,
		"planting_interval_seconds": interval_sec,
		"max_plots": max_plots,
		"active_plots": []
	}

func _load_local_state(world_id: String) -> Dictionary:
	if FileAccess.file_exists(LOCAL_STATE_FILE):
		var f = FileAccess.open(LOCAL_STATE_FILE, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			var json = JSON.new()
			if json.parse(txt) == OK and json.get_data() is Dictionary:
				f.close()
				return json.get_data()
			f.close()
	return _create_default_state(world_id)

func _save_local_state(state: Dictionary) -> void:
	var f = FileAccess.open(LOCAL_STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, "\t"))
		f.close()

func _load_local_events() -> Array:
	if FileAccess.file_exists(LOCAL_EVENTS_FILE):
		var f = FileAccess.open(LOCAL_EVENTS_FILE, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			var json = JSON.new()
			if json.parse(txt) == OK and json.get_data() is Array:
				f.close()
				return json.get_data()
			f.close()
	return []

func _save_local_events(events: Array) -> void:
	var f = FileAccess.open(LOCAL_EVENTS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(events, "\t"))
		f.close()

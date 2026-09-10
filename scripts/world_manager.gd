class_name WorldManager
extends Node2D

signal world_initialized()

## Primary simulation coordinator: orchestrates garden plots, character behavior,
## offline elapsed-time reconstruction, and persistent cloud/local syncing.

@export var planting_interval: float = 600.0 # 10 minutes in seconds
@export var max_plots: int = 12

@onready var character: CharacterController = $Character
@onready var plots_container: Node2D = $PlotsContainer
@onready var persistence: PersistenceManager = $PersistenceManager
@onready var hud: HUDController = $HUD

var plots: Array[PlantPlot] = []
var active_plants_data: Array = []
var current_plant_count: int = 0
var time_until_next_plant: float = 600.0
var last_planted_unix: int = 0
var is_character_busy: bool = false
var pending_live_plot_index: int = -1

var plant_scene: PackedScene = preload("res://scenes/plant_node.tscn")

func _ready() -> void:
	_gather_plots()
	_connect_signals()
	_initialize_world()

func _gather_plots() -> void:
	plots.clear()
	for child in plots_container.get_children():
		if child is PlantPlot:
			plots.append(child)
	max_plots = plots.size()

func _connect_signals() -> void:
	if character:
		character.planting_finished.connect(_on_character_planting_finished)
	if hud:
		hud.plant_now_requested.connect(_trigger_immediate_planting)
		hud.fast_forward_requested.connect(_simulate_offline_time)
		hud.reset_garden_requested.connect(_reset_garden)
		hud.credentials_submitted.connect(_on_credentials_submitted)
	if persistence:
		persistence.status_updated.connect(_on_persistence_status_updated)

func _on_persistence_status_updated(connected: bool, provider: String, msg: String) -> void:
	if hud:
		hud.update_backend_status(connected, provider, msg)

func _initialize_world() -> void:
	var cfg = persistence.load_and_apply_config()
	if hud:
		hud.populate_config_fields(cfg.get("supabase_url", ""), cfg.get("supabase_anon_key", ""))

	# Load state from Supabase or Local Fallback
	var world_data = await persistence.load_world("main_garden")
	var state = world_data.get("state", {})
	var events = world_data.get("events", [])

	planting_interval = float(state.get("planting_interval_seconds", 600.0))
	active_plants_data = state.get("active_plots", [])
	current_plant_count = state.get("total_plants", active_plants_data.size())

	# Format historical timestamps to user's local timezone
	for ev in events:
		var ev_iso = ev.get("event_time", "")
		if not ev_iso.is_empty():
			var u = _parse_iso_to_unix(ev_iso)
			if u > 0:
				ev["event_time_str"] = _format_local_time(u)

	for p in active_plants_data:
		var p_iso = p.get("planted_at", "")
		if not p_iso.is_empty():
			var u = _parse_iso_to_unix(p_iso)
			if u > 0:
				p["time_str"] = _format_local_time(u)

	# Parse last planting timestamp
	var last_iso = state.get("last_planted_at", "")
	last_planted_unix = _parse_iso_to_unix(last_iso)
	var now_unix = int(Time.get_unix_time_from_system())

	# If newly initialized garden or invalid timestamp
	if last_planted_unix <= 0:
		last_planted_unix = now_unix
		time_until_next_plant = planting_interval
	else:
		# Calculate offline elapsed time!
		var elapsed = now_unix - last_planted_unix
		if elapsed >= int(planting_interval):
			_reconstruct_offline_time(elapsed, now_unix)
		else:
			time_until_next_plant = max(1.0, planting_interval - float(elapsed))

	# Render visual plants
	_render_existing_plants()

	# Render HUD
	if hud:
		hud.set_events(events)
		hud.update_plant_count(current_plant_count, max_plots)
		var is_full = current_plant_count >= max_plots
		hud.update_countdown(time_until_next_plant, is_full)

	world_initialized.emit()

func _process(delta: float) -> void:
	if is_character_busy:
		return

	var is_full = current_plant_count >= max_plots
	if is_full:
		if hud:
			hud.update_countdown(0.0, true)
		return

	time_until_next_plant -= delta
	if hud:
		hud.update_countdown(time_until_next_plant, false)

	if time_until_next_plant <= 0.0:
		time_until_next_plant = planting_interval
		_trigger_scheduled_planting()

## Helper to format any UTC unix timestamp into the user's local 12-hour time (e.g. "8:25 AM")
func _format_local_time(unix_sec: int) -> String:
	var tz = Time.get_time_zone_from_system()
	var bias_minutes = tz.get("bias", 0)
	var local_unix = unix_sec + (bias_minutes * 60)
	var dt = Time.get_datetime_dict_from_unix_time(local_unix)
	var hour = dt.get("hour", 0)
	var minute = dt.get("minute", 0)
	var ampm = "AM"
	if hour >= 12:
		ampm = "PM"
	var hour12 = hour % 12
	if hour12 == 0:
		hour12 = 12
	return "%d:%02d %s" % [hour12, minute, ampm]

## Offline Time Simulation & Reconstruction Logic
func _reconstruct_offline_time(elapsed_seconds: int, _now_unix: int) -> void:
	var interval_int = int(planting_interval)
	var missed_intervals = int(floor(float(elapsed_seconds) / float(interval_int)))
	print("Offline elapsed: %d seconds. Missed intervals: %d" % [elapsed_seconds, missed_intervals])

	var added_plants_count = 0
	for i in range(1, missed_intervals + 1):
		var next_slot = _find_first_empty_plot_index()
		if next_slot == -1:
			print("Garden reached maximum capacity (%d plots). Halting offline reconstruction." % max_plots)
			var bloom_ev = {
				"world_id": "main_garden",
				"plant_number": current_plant_count,
				"plot_index": -1,
				"event_time": Time.get_datetime_string_from_unix_time(_now_unix, true) + "Z",
				"event_time_str": _format_local_time(_now_unix),
				"message": "🌸 Garden in Full Bloom (%d plots). Simulation resting." % max_plots,
				"is_offline": true
			}
			persistence.record_event(bloom_ev)
			if hud:
				hud.add_event(bloom_ev)
			break

		var sim_unix = last_planted_unix + (i * interval_int)
		var sim_time_str = _format_local_time(sim_unix)
		var sim_iso = Time.get_datetime_string_from_unix_time(sim_unix, true) + "Z"

		current_plant_count += 1
		added_plants_count += 1

		# Record plant data
		var p_data = {
			"plant_number": current_plant_count,
			"plot_index": next_slot,
			"planted_at": sim_iso,
			"time_str": sim_time_str,
			"is_offline": true,
			"stage": 2
		}
		active_plants_data.append(p_data)
		_spawn_plant_at_plot(next_slot, current_plant_count, true, sim_iso, sim_time_str)

		# Record chronological event
		var ev_data = {
			"world_id": "main_garden",
			"plant_number": current_plant_count,
			"plot_index": next_slot,
			"event_time": sim_iso,
			"event_time_str": sim_time_str,
			"message": "Plant #%d planted" % current_plant_count,
			"is_offline": true
		}
		persistence.record_event(ev_data)
		if hud:
			hud.add_event(ev_data)

	# Advance base timestamp
	if added_plants_count > 0:
		last_planted_unix += (added_plants_count * interval_int)

	# Calculate fractional remainder for seamless next live cycle
	var remaining_remainder = elapsed_seconds % interval_int
	time_until_next_plant = max(1.0, float(interval_int - remaining_remainder))

	if hud:
		hud.update_plant_count(current_plant_count, max_plots)
		hud.update_countdown(time_until_next_plant, current_plant_count >= max_plots)
	# Persist state
	_save_world_state()

func _trigger_scheduled_planting() -> void:
	if current_plant_count >= max_plots:
		print("Garden full! Cannot plant more.")
		return

	var target_plot = _find_first_empty_plot_index()
	if target_plot == -1:
		return

	pending_live_plot_index = target_plot
	is_character_busy = true
	var dest_pos = plots[target_plot].global_position
	character.walk_to_and_plant(target_plot, dest_pos)

func _on_character_planting_finished(plot_idx: int) -> void:
	is_character_busy = false
	current_plant_count += 1

	var now_unix = int(Time.get_unix_time_from_system())
	var time_str = _format_local_time(now_unix)
	var iso = Time.get_datetime_string_from_unix_time(now_unix, true) + "Z"

	last_planted_unix = now_unix

	# Instantiate Plant visually
	_spawn_plant_at_plot(plot_idx, current_plant_count, false, iso, time_str)

	# Save to state
	var p_data = {
		"plant_number": current_plant_count,
		"plot_index": plot_idx,
		"planted_at": iso,
		"time_str": time_str,
		"is_offline": false,
		"stage": 2
	}
	active_plants_data.append(p_data)

	# Record event
	var ev_data = {
		"world_id": "main_garden",
		"plant_number": current_plant_count,
		"plot_index": plot_idx,
		"event_time": iso,
		"event_time_str": time_str,
		"message": "Plant #%d planted" % current_plant_count,
		"is_offline": false
	}
	persistence.record_event(ev_data)
	if hud:
		hud.add_event(ev_data)

	if current_plant_count >= max_plots:
		var bloom_ev = {
			"world_id": "main_garden",
			"plant_number": current_plant_count,
			"plot_index": plot_idx,
			"event_time": iso,
			"event_time_str": time_str,
			"message": "🌸 Garden in Full Bloom! All %d plots thriving." % max_plots,
			"is_offline": false
		}
		persistence.record_event(bloom_ev)
		if hud:
			hud.add_event(bloom_ev)

	if hud:
		hud.update_plant_count(current_plant_count, max_plots)
		hud.update_countdown(time_until_next_plant, current_plant_count >= max_plots)

	_save_world_state()

func _spawn_plant_at_plot(plot_idx: int, p_num: int, is_off: bool, iso: String, t_str: String) -> void:
	if plot_idx < 0 or plot_idx >= plots.size():
		return
	var plot = plots[plot_idx]
	plot.remove_plant()

	var plant: PlantNode = plant_scene.instantiate()
	plant.setup(p_num, plot_idx, is_off, iso, t_str, 2)
	plot.set_plant(plant)

func _render_existing_plants() -> void:
	for p_data in active_plants_data:
		var p_idx = p_data.get("plot_index", 0)
		var p_num = p_data.get("plant_number", 1)
		var is_off = p_data.get("is_offline", false)
		var iso = p_data.get("planted_at", "")
		var t_str = p_data.get("time_str", "--:--")
		_spawn_plant_at_plot(p_idx, p_num, is_off, iso, t_str)

func _find_first_empty_plot_index() -> int:
	var occupied_indices = {}
	for p in active_plants_data:
		occupied_indices[p.get("plot_index", -1)] = true

	for i in range(plots.size()):
		if not occupied_indices.has(i) and not plots[i].is_occupied():
			return i
	return -1

func _save_world_state() -> void:
	var state = {
		"id": "main_garden",
		"total_plants": current_plant_count,
		"last_planted_at": Time.get_datetime_string_from_unix_time(last_planted_unix, true) + "Z",
		"planting_interval_seconds": int(planting_interval),
		"max_plots": max_plots,
		"active_plots": active_plants_data
	}
	persistence.save_state("main_garden", state)

# --- Test / Simulation Controls ---

func _trigger_immediate_planting() -> void:
	if is_character_busy:
		return
	time_until_next_plant = 0.1

func _simulate_offline_time(minutes: int) -> void:
	print("Simulating %d minutes of elapsed offline time..." % minutes)
	var seconds = minutes * 60
	last_planted_unix -= seconds
	var now_unix = int(Time.get_unix_time_from_system())
	var elapsed = now_unix - last_planted_unix
	_reconstruct_offline_time(elapsed, now_unix)
	if hud:
		hud.update_plant_count(current_plant_count, max_plots)

func _reset_garden() -> void:
	print("Resetting garden...")
	var harvest_count = current_plant_count
	for plot in plots:
		plot.remove_plant()
	active_plants_data.clear()
	current_plant_count = 0
	last_planted_unix = int(Time.get_unix_time_from_system())
	time_until_next_plant = planting_interval

	var _fresh_state = await persistence.reset_world("main_garden", int(planting_interval), max_plots)
	
	var initial_events: Array = []
	if harvest_count > 0:
		var now_unix = int(Time.get_unix_time_from_system())
		var harvest_ev = {
			"world_id": "main_garden",
			"plant_number": harvest_count,
			"plot_index": -1,
			"event_time": Time.get_datetime_string_from_unix_time(now_unix, true) + "Z",
			"event_time_str": _format_local_time(now_unix),
			"message": "🌾 Harvested %d mature plants! Soil cleared for new cycle." % harvest_count,
			"is_offline": false
		}
		persistence.record_event(harvest_ev)
		initial_events.append(harvest_ev)

	if hud:
		hud.set_events(initial_events)
		hud.update_plant_count(0, max_plots)
		hud.update_countdown(time_until_next_plant, false)

func _on_credentials_submitted(url: String, key: String) -> void:
	if hud:
		hud.set_config_status("Testing connection to Supabase...")
	persistence.save_config(url, key)
	var res = await persistence.supabase.test_connection()
	if res.success:
		if hud:
			hud.set_config_status("Success! Connected to Supabase.", false)
		_initialize_world()
	else:
		if hud:
			hud.set_config_status("Error: " + res.error, true)

func _parse_iso_to_unix(iso: String) -> int:
	if iso.strip_edges().is_empty():
		return 0
	var clean = iso.replace("Z", "").strip_edges()
	var dt = Time.get_unix_time_from_datetime_string(clean)
	return dt

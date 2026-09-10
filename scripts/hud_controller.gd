class_name HUDController
extends CanvasLayer

## Controls the user interface: Event Log, Live Timers, Telemetry, and Testing Controls.

signal plant_now_requested()
signal fast_forward_requested(minutes: int)
signal reset_garden_requested()
signal credentials_submitted(url: String, anon_key: String)

@onready var event_log_text: RichTextLabel = %EventLogText
@onready var next_plant_timer_label: Label = %NextPlantTimerLabel
@onready var system_clock_label: Label = %SystemClockLabel
@onready var plant_count_label: Label = %PlantCountLabel
@onready var backend_status_badge: Label = %BackendStatusBadge
@onready var backend_details_label: Label = %BackendDetailsLabel

# Config Dialog
@onready var config_modal: PanelContainer = %ConfigModal
@onready var url_input: LineEdit = %UrlInput
@onready var key_input: LineEdit = %KeyInput
@onready var config_status_label: Label = %ConfigStatusLabel

@onready var btn_reset: Button = get_node_or_null("BottomBar/Margin/HBox/BtnReset")
@onready var btn_plant_now: Button = get_node_or_null("BottomBar/Margin/HBox/BtnPlantNow")

var current_events: Array = []

func _ready() -> void:
	if config_modal:
		config_modal.visible = false
	_update_clock()

func _process(_delta: float) -> void:
	_update_clock()

func _update_clock() -> void:
	if system_clock_label:
		var dt = Time.get_datetime_dict_from_system()
		system_clock_label.text = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

func update_countdown(seconds_remaining: float, is_full: bool = false) -> void:
	if next_plant_timer_label:
		if is_full:
			next_plant_timer_label.text = "Garden Full (12/12)"
			next_plant_timer_label.modulate = Color(0.9, 0.7, 1.0)
		else:
			var s = max(0, int(seconds_remaining))
			var mins = s / 60
			var secs = s % 60
			next_plant_timer_label.text = "%02d:%02d" % [mins, secs]
			next_plant_timer_label.modulate = Color(1.0, 1.0, 1.0)

func update_plant_count(current: int, maximum: int) -> void:
	if plant_count_label:
		if current >= maximum:
			plant_count_label.text = "Plants: %d / %d (Full Bloom ✨)" % [current, maximum]
			plant_count_label.modulate = Color(1.0, 0.85, 0.4)
		else:
			plant_count_label.text = "Plants: %d / %d" % [current, maximum]
			plant_count_label.modulate = Color(1.0, 1.0, 1.0)
	if btn_reset:
		btn_reset.text = "Harvest Garden (Reset)" if current >= maximum else "Reset Garden"
	if btn_plant_now:
		btn_plant_now.disabled = (current >= maximum)

func update_backend_status(is_cloud: bool, provider: String, details: String) -> void:
	if backend_status_badge:
		if is_cloud:
			backend_status_badge.text = "[Cloud: %s Active]" % provider
			backend_status_badge.modulate = Color(0.3, 1.0, 0.5)
		else:
			backend_status_badge.text = "[Local Sandbox]"
			backend_status_badge.modulate = Color(1.0, 0.85, 0.3)
	if backend_details_label:
		backend_details_label.text = details

func set_events(events: Array) -> void:
	current_events = events.duplicate()
	render_event_log()

func add_event(event_dict: Dictionary) -> void:
	current_events.append(event_dict)
	render_event_log()

func render_event_log() -> void:
	if not event_log_text:
		return

	var bbcode = ""
	if current_events.is_empty():
		bbcode = "[color=#94a3b8][i]No events recorded yet. Garden is awaiting first planting...[/i][/color]"
	else:
		for ev in current_events:
			var t_str = ev.get("event_time_str", "--:--")
			var msg = ev.get("message", "Plant created")
			var is_off = ev.get("is_offline", false)

			if is_off:
				bbcode += "[color=#fbbf24]%s - %s [b][offline][/b][/color]\n" % [t_str, msg]
			else:
				bbcode += "[color=#4ade80]%s[/color] - %s\n" % [t_str, msg]

	event_log_text.text = bbcode
	# Scroll to bottom to view latest
	await get_tree().process_frame
	var v_scroll = event_log_text.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value = v_scroll.max_value

# --- UI Button Handlers ---

func _on_plant_now_pressed() -> void:
	plant_now_requested.emit()

func _on_ff_10m_pressed() -> void:
	fast_forward_requested.emit(10)

func _on_ff_30m_pressed() -> void:
	fast_forward_requested.emit(30)

func _on_reset_garden_pressed() -> void:
	reset_garden_requested.emit()

func _on_open_config_pressed() -> void:
	if config_modal:
		config_modal.visible = true

func _on_close_config_pressed() -> void:
	if config_modal:
		config_modal.visible = false

func _on_save_config_pressed() -> void:
	if url_input and key_input:
		credentials_submitted.emit(url_input.text, key_input.text)

func populate_config_fields(url: String, key: String) -> void:
	if url_input:
		url_input.text = url
	if key_input:
		key_input.text = key

func set_config_status(msg: String, is_error: bool = false) -> void:
	if config_status_label:
		config_status_label.text = msg
		config_status_label.modulate = Color(1.0, 0.4, 0.4) if is_error else Color(0.4, 1.0, 0.6)

class_name CharacterController
extends Node2D

## Handles 2D character locomotion, idle wandering, and the planting action.

signal arrived_at_plot(plot_index: int)
signal planting_finished(plot_index: int)

enum State { IDLE, WALKING_TO_PLOT, PLANTING, RETURNING_HOME }

@export var move_speed: float = 140.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var action_label: Label = $ActionLabel

var current_state: State = State.IDLE
var target_pos: Vector2 = Vector2.ZERO
var target_plot_index: int = -1
var home_position: Vector2 = Vector2(400, 360)

var walk_timer: float = 0.0
var walk_frame_toggle: bool = false
var planting_duration: float = 1.4
var planting_timer: float = 0.0

var tex_idle: Texture2D = preload("res://assets/char_idle.png")
var tex_walk: Texture2D = preload("res://assets/char_walk.png")
var tex_plant: Texture2D = preload("res://assets/char_plant.png")

func _ready() -> void:
	home_position = position
	_set_state(State.IDLE)

func _process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WALKING_TO_PLOT:
			_process_walking(delta, true)
		State.PLANTING:
			_process_planting(delta)
		State.RETURNING_HOME:
			_process_walking(delta, false)

func _set_state(new_state: State) -> void:
	current_state = new_state
	match current_state:
		State.IDLE:
			if sprite:
				sprite.texture = tex_idle
				sprite.offset = Vector2.ZERO
			if action_label:
				action_label.text = "Tending Garden"
		State.WALKING_TO_PLOT:
			if action_label:
				action_label.text = "Walking to Plot #%d..." % (target_plot_index + 1)
		State.PLANTING:
			planting_timer = planting_duration
			if sprite:
				sprite.texture = tex_plant
				sprite.offset = Vector2(0, 2)
			if action_label:
				action_label.text = "Planting..."
		State.RETURNING_HOME:
			if action_label:
				action_label.text = "Returning to Path"

func _process_idle(delta: float) -> void:
	# Subtle breathing bobbing
	walk_timer += delta * 3.0
	if sprite:
		sprite.position.y = sin(walk_timer) * 1.5

func _process_walking(delta: float, is_heading_to_plot: bool) -> void:
	var dist = position.distance_to(target_pos)
	if dist < 4.0:
		position = target_pos
		if is_heading_to_plot:
			arrived_at_plot.emit(target_plot_index)
			_set_state(State.PLANTING)
		else:
			_set_state(State.IDLE)
		return

	# Direction & flip
	var dir = (target_pos - position).normalized()
	position += dir * move_speed * delta

	if sprite:
		if dir.x < -0.1:
			sprite.flip_h = true
		elif dir.x > 0.1:
			sprite.flip_h = false

		# Walk bounce animation
		walk_timer += delta * 10.0
		if fmod(walk_timer, 2.0) > 1.0:
			sprite.texture = tex_walk
			sprite.position.y = -2.0
		else:
			sprite.texture = tex_idle
			sprite.position.y = 0.0

func _process_planting(delta: float) -> void:
	planting_timer -= delta
	# Subtle rhythmic tool digging motion
	if sprite:
		sprite.position.y = sin(planting_timer * 15.0) * 1.5

	if planting_timer <= 0.0:
		planting_finished.emit(target_plot_index)
		# Walk slightly back or return to idle
		target_pos = home_position
		_set_state(State.RETURNING_HOME)

## Public API: Command character to walk to a plot and perform planting
func walk_to_and_plant(plot_idx: int, destination: Vector2) -> void:
	target_plot_index = plot_idx
	# Stand slightly above or to side of plot so plot is visible
	target_pos = destination + Vector2(0, -28)
	_set_state(State.WALKING_TO_PLOT)

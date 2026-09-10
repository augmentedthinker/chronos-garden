class_name PlantNode
extends Node2D

## Represents a growing plant in a garden plot.

@export var plant_number: int = 1
@export var plot_index: int = 0
@export var is_offline: bool = false
@export var planted_at_iso: String = ""
@export var time_str: String = ""
@export var stage: int = 2 # 1 = sprout, 2 = flower

@onready var plant_sprite: Sprite2D = $PlantSprite
@onready var info_label: Label = $InfoLabel
@onready var offline_badge: Label = $OfflineBadge

var tex_sprout: Texture2D = preload("res://assets/plant_sprout.png")
var tex_flower: Texture2D = preload("res://assets/plant_flower.png")

var sway_timer: float = 0.0

func _ready() -> void:
	sway_timer = randf() * PI
	update_visuals()
	
	# Spawn pop-in animation
	scale = Vector2.ZERO
	var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4)

func setup(p_num: int, p_idx: int, p_is_offline: bool, p_iso: String, p_time_str: String, p_stage: int = 2) -> void:
	plant_number = p_num
	plot_index = p_idx
	is_offline = p_is_offline
	planted_at_iso = p_iso
	time_str = p_time_str
	stage = p_stage
	update_visuals()

func update_visuals() -> void:
	if plant_sprite:
		plant_sprite.texture = tex_flower if stage == 2 else tex_sprout
	if info_label:
		info_label.text = "Plant #%d" % plant_number
	if offline_badge:
		offline_badge.visible = is_offline

func _process(delta: float) -> void:
	# Subtle gentle breeze sway
	sway_timer += delta * 2.0
	if plant_sprite:
		plant_sprite.rotation = sin(sway_timer) * 0.08

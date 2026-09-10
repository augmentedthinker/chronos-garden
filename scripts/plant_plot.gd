class_name PlantPlot
extends Node2D

## Represents a designated garden soil plot that can hold a plant.

@export var plot_index: int = 0

@onready var soil_sprite: Sprite2D = $SoilSprite
@onready var plot_label: Label = $PlotLabel
@onready var plant_container: Node2D = $PlantContainer

var current_plant: PlantNode = null

func _ready() -> void:
	if plot_label:
		plot_label.text = "#%d" % (plot_index + 1)

func is_occupied() -> bool:
	return current_plant != null

func set_plant(plant: PlantNode) -> void:
	current_plant = plant
	plant_container.add_child(plant)
	plant.position = Vector2.ZERO

func remove_plant() -> void:
	if current_plant:
		current_plant.queue_free()
		current_plant = null

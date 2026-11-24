class_name CheckpointNode
extends Area2D

signal car_entered_checkpoint(car: Node2D, checkpoint: CheckpointNode)

@export var checkpoint_id: StringName = &""
@export var next_checkpoint_ids: Array[StringName] = []
@export var route_group: StringName = &"shared"
@export var reward_value: float = 200.0
@export var is_shortcut: bool = false
@export var is_lap_finish: bool = false


func _ready() -> void:
	collision_layer = SimulationConfig.LAYER_CHECKPOINTS
	collision_mask = SimulationConfig.LAYER_CARS
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body != null and body.has_method("on_graph_checkpoint_reached"):
		car_entered_checkpoint.emit(body, self)

class_name ObstacleBase
extends StaticBody2D

enum Kind {
	ROCK,
	STOP_SIGN,
	BARRIER,
}

@export var obstacle_kind: Kind = Kind.ROCK
@export var crash_penalty: float = 120.0
@export var clearance_half_width: float = 14.0


func _ready() -> void:
	collision_layer = SimulationConfig.LAYER_LETHAL_OBSTACLES
	collision_mask = 0

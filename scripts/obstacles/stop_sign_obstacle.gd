class_name StopSignObstacle
extends ObstacleBase


func _ready() -> void:
	obstacle_kind = Kind.STOP_SIGN
	crash_penalty = SimulationConfig.STOP_SIGN_CRASH_PENALTY
	clearance_half_width = 13.0
	super._ready()

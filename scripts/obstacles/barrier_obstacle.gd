class_name BarrierObstacle
extends ObstacleBase


func _ready() -> void:
	obstacle_kind = Kind.BARRIER
	crash_penalty = SimulationConfig.BARRIER_CRASH_PENALTY
	clearance_half_width = 19.0
	super._ready()

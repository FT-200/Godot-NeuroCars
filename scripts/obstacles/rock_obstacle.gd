class_name RockObstacle
extends ObstacleBase


func _ready() -> void:
	obstacle_kind = Kind.ROCK
	if crash_penalty <= 0.0:
		crash_penalty = SimulationConfig.ROCK_CRASH_PENALTY
	super._ready()


func randomize_appearance(rng: RandomNumberGenerator) -> void:
	rotation = rng.randf_range(-PI, PI)
	var uniform_scale: float = rng.randf_range(0.88, 1.14)
	scale = Vector2(uniform_scale, uniform_scale)
	clearance_half_width = 12.5 * uniform_scale

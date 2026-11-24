class_name PedestrianObstacle
extends Area2D

@export var whip_penalty: float = SimulationConfig.PEDESTRIAN_WHIP_PENALTY
@export var slowdown_duration: float = SimulationConfig.PEDESTRIAN_RECOVERY_DURATION
@export var recovery_accel_factor: float = SimulationConfig.PEDESTRIAN_ACCEL_FACTOR
@export var patrol_half_span: float = 26.0
@export var walk_speed: float = 32.0
@export var is_moving: bool = true

var _anchor_pos: Vector2 = Vector2.ZERO
var _move_axis: Vector2 = Vector2.DOWN
var _patrol_offset: float = 0.0
var _patrol_dir: float = 1.0
var _pause_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _car_cooldowns: Dictionary = {}

@onready var walker_visual: Node2D = $WalkerVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var crosswalk_visual: Node2D = $CrosswalkVisual
@onready var hit_ring: Polygon2D = $WalkerVisual/HitRing


func _ready() -> void:
	collision_layer = SimulationConfig.LAYER_PEDESTRIANS
	collision_mask = SimulationConfig.LAYER_CARS
	monitoring = true
	monitorable = true
	_anchor_pos = position
	_move_axis = Vector2(0.0, 1.0)
	if hit_ring:
		hit_ring.visible = false
	body_entered.connect(_on_body_entered)


func configure_patrol(anchor: Vector2, road_tangent: Vector2, half_span: float, rng: RandomNumberGenerator) -> void:
	_anchor_pos = anchor
	position = anchor
	var angle: float = road_tangent.angle()
	rotation = angle
	_move_axis = Vector2(0.0, 1.0)
	patrol_half_span = clampf(half_span, 10.0, 34.0)
	_patrol_offset = rng.randf_range(-patrol_half_span * 0.65, patrol_half_span * 0.65)
	_patrol_dir = 1.0 if rng.randf() >= 0.5 else -1.0
	_apply_walker_offset()


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_hit_flash(delta)
	if not is_moving or patrol_half_span <= 0.5:
		return

	if _pause_timer > 0.0:
		_pause_timer -= delta
		return

	_patrol_offset += _patrol_dir * walk_speed * delta
	if _patrol_offset >= patrol_half_span:
		_patrol_offset = patrol_half_span
		_patrol_dir = -1.0
		_pause_timer = 0.6
	elif _patrol_offset <= -patrol_half_span:
		_patrol_offset = -patrol_half_span
		_patrol_dir = 1.0
		_pause_timer = 0.6

	_apply_walker_offset()


func _apply_walker_offset() -> void:
	var local_offset: Vector2 = _move_axis * _patrol_offset
	if walker_visual:
		walker_visual.position = local_offset
		walker_visual.rotation = (PI * 0.5) if _patrol_dir > 0.0 else (-PI * 0.5)
	if collision_shape:
		collision_shape.position = local_offset


func _tick_cooldowns(delta: float) -> void:
	if _car_cooldowns.is_empty():
		return
	var expired: Array = []
	for car_id in _car_cooldowns.keys():
		var remaining: float = float(_car_cooldowns[car_id]) - delta
		if remaining <= 0.0:
			expired.append(car_id)
		else:
			_car_cooldowns[car_id] = remaining
	for car_id in expired:
		_car_cooldowns.erase(car_id)


func _tick_hit_flash(delta: float) -> void:
	if _hit_flash_timer <= 0.0:
		return
	_hit_flash_timer -= delta
	if hit_ring:
		if _hit_flash_timer <= 0.0:
			hit_ring.visible = false
		else:
			hit_ring.modulate = Color(1.0, 0.35, 0.15, clampf(_hit_flash_timer / 0.55, 0.0, 1.0))


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.has_method("on_pedestrian_hit"):
		return
	var car_id: int = body.get_instance_id()
	if _car_cooldowns.has(car_id):
		return
	_car_cooldowns[car_id] = SimulationConfig.PEDESTRIAN_HIT_COOLDOWN
	_hit_flash_timer = 0.55
	if hit_ring:
		hit_ring.visible = true
		hit_ring.modulate = Color(1.0, 0.35, 0.15, 1.0)
	body.on_pedestrian_hit(whip_penalty, slowdown_duration, recovery_accel_factor)

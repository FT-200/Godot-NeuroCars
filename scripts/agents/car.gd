class_name Car
extends CharacterBody2D

signal crashed(car: Car)

@export var max_speed: float = 360.0
@export var normal_acceleration: float = 480.0
@export var braking_deceleration: float = 620.0
@export var turn_speed: float = 3.8

var brain: NeuralNetwork
var is_alive: bool = true
var fitness: float = 0.0
var time_alive: float = 0.0
var total_distance: float = 0.0
var current_speed: float = 120.0

var time_since_checkpoint: float = 0.0
var segment_fitness: float = 0.0
var show_rays: bool = false
var is_elite: bool = false
var is_leader: bool = false

var is_recovering_from_pedestrian: bool = false
var recovery_timer: float = 0.0
var recovery_duration: float = SimulationConfig.PEDESTRIAN_RECOVERY_DURATION
var recovery_accel_multiplier: float = SimulationConfig.PEDESTRIAN_ACCEL_FACTOR
var pedestrian_hits: int = 0

var track_ref: Node = null
var last_checkpoint_id: StringName = &""
var expected_checkpoint_ids: Array[StringName] = []
var laps_completed: int = 0
var shortcuts_taken: int = 0
var current_lap_time: float = 0.0
var best_lap_time: float = 999.0

@onready var sensors: Array = $Sensors.get_children()
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var wheel_fl: Node2D = get_node_or_null("CarModel/Wheels/WheelFL")
@onready var wheel_fr: Node2D = get_node_or_null("CarModel/Wheels/WheelFR")


func _ready() -> void:
	collision_layer = SimulationConfig.LAYER_CARS
	collision_mask = SimulationConfig.CAR_COLLISION_MASK
	for ray: RayCast2D in sensors:
		ray.collision_mask = SimulationConfig.SENSOR_COLLISION_MASK
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.hit_from_inside = true
	if brain == null or not brain.is_compatible_with(SimulationConfig.DEFAULT_NETWORK_LAYERS):
		brain = NeuralNetwork.new(SimulationConfig.DEFAULT_NETWORK_LAYERS)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	time_alive += delta
	time_since_checkpoint += delta
	current_lap_time += delta

	var moved_step: float = velocity.length() * delta
	total_distance += moved_step
	var step_fit: float = minf(moved_step * 0.1, 45.0 - segment_fitness)
	if step_fit > 0.0:
		segment_fitness += step_fit
		fitness += step_fit

	var max_idle_time: float = 8.5 if is_recovering_from_pedestrian else 5.5
	if (time_alive > 4.0 and total_distance < 80.0) or time_since_checkpoint > max_idle_time:
		die()
		return

	var inputs: Array[float] = _collect_inputs()
	var outputs: Array[float] = brain.predict(inputs)
	var steer: float = outputs[0]
	var raw_throttle: float = outputs[1]
	var throttle: float = clampf((raw_throttle + 1.0) * 0.5, 0.2, 1.0)
	var target_speed: float = throttle * max_speed

	if is_recovering_from_pedestrian:
		recovery_timer = maxf(0.0, recovery_timer - delta)
		var progress: float = 1.0 - clampf(recovery_timer / maxf(recovery_duration, 0.01), 0.0, 1.0)
		var cap_ratio: float = lerpf(0.32, 1.0, progress)
		var effective_target: float = minf(target_speed, cap_ratio * max_speed)
		var accel_scale: float = lerpf(recovery_accel_multiplier, 0.65, progress)
		current_speed = move_toward(current_speed, effective_target, normal_acceleration * accel_scale * delta)
		if recovery_timer <= 0.0:
			is_recovering_from_pedestrian = false
	else:
		var rate: float = normal_acceleration if target_speed >= current_speed else braking_deceleration
		current_speed = move_toward(current_speed, target_speed, rate * delta)

	var steer_authority: float = clampf(current_speed / 85.0, 0.25, 1.0)
	rotation += steer * turn_speed * steer_authority * delta
	velocity = transform.x * current_speed

	if wheel_fl and wheel_fr:
		wheel_fl.rotation = steer * 0.45
		wheel_fr.rotation = steer * 0.45

	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision:
		var collider: Object = collision.get_collider()
		if collider is ObstacleBase:
			fitness = maxf(0.0, fitness - collider.crash_penalty)
		else:
			fitness = maxf(0.0, fitness - SimulationConfig.WALL_CRASH_PENALTY)
		die()
		return

	if is_recovering_from_pedestrian:
		_apply_tint()
	if show_rays:
		queue_redraw()


func _collect_inputs() -> Array[float]:
	var inputs: Array[float] = []
	for ray: RayCast2D in sensors:
		if ray.is_colliding():
			var origin: Vector2 = ray.global_position
			var hit_point: Vector2 = ray.get_collision_point()
			var dist: float = origin.distance_to(hit_point)
			var max_len: float = maxf(ray.target_position.length(), 1.0)
			inputs.append(clampf(dist / max_len, 0.0, 1.0))
		else:
			inputs.append(1.0)

	var forward_dot: float = 1.0
	var right_dot: float = 0.0
	if track_ref != null and track_ref.has_method("get_guidance_target_for_car"):
		var target_pos: Vector2 = track_ref.get_guidance_target_for_car(self)
		var to_target: Vector2 = target_pos - global_position
		if to_target.length_squared() > 1.0:
			var dir: Vector2 = to_target.normalized()
			forward_dot = dir.dot(transform.x)
			right_dot = dir.dot(transform.y)

	inputs.append(forward_dot)
	inputs.append(right_dot)
	inputs.append(clampf(current_speed / maxf(max_speed, 1.0), 0.0, 1.0))
	var penalty_norm: float = clampf(recovery_timer / maxf(recovery_duration, 0.01), 0.0, 1.0) if is_recovering_from_pedestrian else 0.0
	inputs.append(penalty_norm)
	return inputs


func on_pedestrian_hit(whip_penalty: float, slowdown_duration: float, accel_factor: float) -> void:
	if not is_alive:
		return
	fitness = maxf(0.0, fitness - whip_penalty)
	current_speed = 0.0
	velocity = Vector2.ZERO
	is_recovering_from_pedestrian = true
	recovery_duration = maxf(slowdown_duration, 0.5)
	recovery_timer = recovery_duration
	recovery_accel_multiplier = clampf(accel_factor, 0.05, 0.8)
	pedestrian_hits += 1
	time_since_checkpoint = minf(time_since_checkpoint, 1.0)
	_apply_tint()


func on_graph_checkpoint_reached(cp_id: StringName, reward: float, next_ids: Array[StringName], is_shortcut: bool, is_lap_finish: bool) -> bool:
	if not is_alive:
		return false
	if not expected_checkpoint_ids.is_empty() and not expected_checkpoint_ids.has(cp_id):
		return false

	var speed_bonus: float = maxf(0.0, 5.0 - time_since_checkpoint) * 24.0
	fitness += reward + speed_bonus
	if is_shortcut:
		shortcuts_taken += 1
		fitness += SimulationConfig.SHORTCUT_BONUS

	if is_lap_finish and last_checkpoint_id != &"" and last_checkpoint_id != cp_id:
		laps_completed += 1
		if current_lap_time < best_lap_time:
			best_lap_time = current_lap_time
		current_lap_time = 0.0
		fitness += SimulationConfig.LAP_COMPLETION_BONUS

	last_checkpoint_id = cp_id
	expected_checkpoint_ids = next_ids.duplicate()
	time_since_checkpoint = 0.0
	segment_fitness = 0.0
	return true


func update_visual_state(leader_flag: bool, force_rays: bool) -> void:
	if not is_alive:
		return
	is_leader = leader_flag
	var target_rays: bool = is_leader or is_elite or force_rays
	_apply_tint()
	if show_rays != target_rays:
		show_rays = target_rays
		queue_redraw()


func _apply_tint() -> void:
	if not is_alive:
		return
	if is_recovering_from_pedestrian:
		var pulse: float = 0.5 + 0.5 * sin(time_alive * 18.0)
		modulate = Color(1.0, lerpf(0.35, 0.65, pulse), 0.15, 1.0)
		z_index = 12 if is_leader else 8
	elif is_leader:
		modulate = Color(0.2, 1.0, 0.2, 1.0)
		z_index = 10
	elif is_elite:
		modulate = Color(0.45, 0.95, 0.45, 1.0)
		z_index = 5
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		z_index = 1


func die() -> void:
	if not is_alive:
		return
	is_alive = false
	is_recovering_from_pedestrian = false
	show_rays = false
	z_index = 0
	current_speed = 0.0
	velocity = Vector2.ZERO
	modulate = Color(1.0, 1.0, 1.0, 0.25)
	for ray: RayCast2D in sensors:
		ray.enabled = false
	collision_shape.set_deferred("disabled", true)
	queue_redraw()
	crashed.emit(self)


func _draw() -> void:
	if not is_alive or not show_rays:
		return
	for ray: RayCast2D in sensors:
		var end_pos: Vector2
		var line_color: Color
		if ray.is_colliding():
			end_pos = to_local(ray.get_collision_point())
			var collider: Object = ray.get_collider()
			if collider is PedestrianObstacle:
				line_color = Color(1.0, 0.72, 0.12, 0.92)
			elif collider is ObstacleBase:
				line_color = Color(1.0, 0.42, 0.14, 0.88)
			else:
				line_color = Color(1.0, 0.2, 0.24, 0.8)
		else:
			end_pos = to_local(ray.to_global(ray.target_position))
			line_color = Color(0.2, 1.0, 0.2, 0.32)
		draw_line(to_local(ray.global_position), end_pos, line_color, 1.5)

class_name ObstacleSpawner
extends Node2D

const KIND_ROCK: int = 0
const KIND_PEDESTRIAN: int = 1
const KIND_STOP_SIGN: int = 2
const KIND_BARRIER: int = 3

const ROCK_SCENE: PackedScene = preload("res://scenes/obstacles/rock_obstacle.tscn")
const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/obstacles/pedestrian_obstacle.tscn")
const STOP_SIGN_SCENE: PackedScene = preload("res://scenes/obstacles/stop_sign_obstacle.tscn")
const BARRIER_SCENE: PackedScene = preload("res://scenes/obstacles/barrier_obstacle.tscn")

@export var min_obstacles: int = 5
@export var max_obstacles: int = 7
@export var pedestrian_ratio: float = 0.25
@export var rock_ratio: float = 0.30
@export var stop_sign_ratio: float = 0.22
@export var barrier_ratio: float = 0.23

var active_obstacles: Array[Node] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func clear_obstacles() -> void:
	for obs in active_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	active_obstacles.clear()


func respawn_for_generation(seed_val: int, active_groups: Dictionary, spawn_origin: Vector2) -> int:
	clear_obstacles()
	_rng.seed = seed_val

	var candidate_slots: Array[Marker2D] = _gather_slots(active_groups, spawn_origin, 220.0)
	if candidate_slots.is_empty():
		return 0

	_shuffle_slots(candidate_slots)
	var chosen_slots: Array[Marker2D] = []
	for slot in candidate_slots:
		if _is_slot_spaced(slot, chosen_slots, 155.0):
			chosen_slots.append(slot)

	if chosen_slots.is_empty():
		return 0

	var target_count: int = _rng.randi_range(mini(min_obstacles, chosen_slots.size()), mini(max_obstacles, chosen_slots.size()))
	if target_count <= 0:
		return 0

	var chosen_kinds: Array[int] = _plan_obstacle_kinds(target_count)
	for i in range(target_count):
		var slot: Marker2D = chosen_slots[i]
		var allowed: PackedInt32Array = _get_slot_allowed_kinds(slot)
		var kind: int = chosen_kinds[i]
		if not allowed.is_empty() and not _packed_contains(allowed, kind):
			kind = allowed[_rng.randi_range(0, allowed.size() - 1)]
		var spawned: Node = _spawn_obstacle_at_slot(slot, kind)
		if spawned != null:
			active_obstacles.append(spawned)

	return active_obstacles.size()


func respawn_group_obstacles(target_group: StringName, living_cars: Array) -> int:
	var to_keep: Array[Node] = []
	for obs in active_obstacles:
		if not is_instance_valid(obs):
			continue
		if obs.has_meta("route_group") and obs.get_meta("route_group") == target_group:
			obs.queue_free()
		else:
			to_keep.append(obs)
	active_obstacles = to_keep

	var group_slots: Array[Marker2D] = []
	for child in get_children():
		var marker: Marker2D = child as Marker2D
		if marker == null:
			continue
		var slot_group: StringName = marker.get_meta("route_group", &"shared")
		if slot_group != target_group:
			continue
		if _is_far_from_cars(marker.global_position, living_cars, 280.0):
			group_slots.append(marker)

	if group_slots.is_empty():
		return 0

	_shuffle_slots(group_slots)
	var spawn_count: int = mini(2, group_slots.size())
	var added: int = 0
	for i in range(spawn_count):
		var slot: Marker2D = group_slots[i]
		var allowed: PackedInt32Array = _get_slot_allowed_kinds(slot)
		var kind: int = _roll_weighted_kind()
		if not allowed.is_empty() and not _packed_contains(allowed, kind):
			kind = allowed[_rng.randi_range(0, allowed.size() - 1)]
		var spawned: Node = _spawn_obstacle_at_slot(slot, kind)
		if spawned != null:
			active_obstacles.append(spawned)
			added += 1
	return added


func get_obstacle_counts_summary() -> Dictionary:
	var rocks: int = 0
	var peds: int = 0
	var signs: int = 0
	var barriers: int = 0
	for obs in active_obstacles:
		if not is_instance_valid(obs):
			continue
		if obs is PedestrianObstacle:
			peds += 1
		elif obs is RockObstacle:
			rocks += 1
		elif obs is StopSignObstacle:
			signs += 1
		elif obs is BarrierObstacle:
			barriers += 1
	return {
		"total": rocks + peds + signs + barriers,
		"rocks": rocks,
		"pedestrians": peds,
		"stop_signs": signs,
		"barriers": barriers,
	}


func _gather_slots(active_groups: Dictionary, spawn_origin: Vector2, min_spawn_dist: float) -> Array[Marker2D]:
	var slots: Array[Marker2D] = []
	for child in get_children():
		var marker: Marker2D = child as Marker2D
		if marker == null:
			continue
		var slot_group: StringName = marker.get_meta("route_group", &"shared")
		if slot_group != &"shared" and not active_groups.get(slot_group, false):
			continue
		if marker.global_position.distance_to(spawn_origin) < min_spawn_dist:
			continue
		slots.append(marker)
	return slots


func _shuffle_slots(slots: Array[Marker2D]) -> void:
	for i in range(slots.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Marker2D = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp


func _is_slot_spaced(candidate: Marker2D, chosen: Array[Marker2D], min_spacing: float) -> bool:
	for existing in chosen:
		if candidate.global_position.distance_to(existing.global_position) < min_spacing:
			return false
	return true


func _is_far_from_cars(pos: Vector2, living_cars: Array, min_dist: float) -> bool:
	for car in living_cars:
		if is_instance_valid(car) and car.is_alive:
			if car.global_position.distance_to(pos) < min_dist:
				return false
	return true


func _plan_obstacle_kinds(target_count: int) -> Array[int]:
	var planned: Array[int] = []
	var guaranteed: Array[int] = [KIND_ROCK, KIND_PEDESTRIAN, KIND_STOP_SIGN, KIND_BARRIER]
	for g in guaranteed:
		if planned.size() < target_count:
			planned.append(g)
	while planned.size() < target_count:
		planned.append(_roll_weighted_kind())
	for i in range(planned.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: int = planned[i]
		planned[i] = planned[j]
		planned[j] = tmp
	return planned


func _roll_weighted_kind() -> int:
	var total_weight: float = maxf(rock_ratio + pedestrian_ratio + stop_sign_ratio + barrier_ratio, 0.01)
	var roll: float = _rng.randf() * total_weight
	if roll < rock_ratio:
		return KIND_ROCK
	roll -= rock_ratio
	if roll < pedestrian_ratio:
		return KIND_PEDESTRIAN
	roll -= pedestrian_ratio
	if roll < stop_sign_ratio:
		return KIND_STOP_SIGN
	return KIND_BARRIER


func _get_slot_allowed_kinds(slot: Marker2D) -> PackedInt32Array:
	var raw_val: Variant = slot.get_meta("allowed_kinds", PackedInt32Array([0, 1, 2, 3]))
	if raw_val is PackedInt32Array:
		return raw_val
	return PackedInt32Array([0, 1, 2, 3])


func _packed_contains(arr: PackedInt32Array, value: int) -> bool:
	for item in arr:
		if item == value:
			return true
	return false


func _spawn_obstacle_at_slot(slot: Marker2D, kind: int) -> Node:
	var tangent: Vector2 = slot.get_meta("road_tangent", Vector2.RIGHT).normalized()
	if tangent.length_squared() < 0.1:
		tangent = Vector2.RIGHT
	var normal: Vector2 = Vector2(-tangent.y, tangent.x)
	var half_width: float = float(slot.get_meta("road_half_width", 46.0))
	var slot_group: StringName = slot.get_meta("route_group", &"shared")

	if kind == KIND_PEDESTRIAN:
		var ped: PedestrianObstacle = PEDESTRIAN_SCENE.instantiate() as PedestrianObstacle
		var span: float = maxf(12.0, half_width - 18.0)
		add_child(ped)
		ped.configure_patrol(slot.position, tangent, span, _rng)
		ped.set_meta("route_group", slot_group)
		return ped

	var obs_half_width: float = 13.0
	if kind == KIND_BARRIER:
		obs_half_width = 18.0
	var lateral_offset: float = _pick_safe_lateral_offset(half_width, obs_half_width)
	var spawn_pos: Vector2 = slot.position + normal * lateral_offset

	var instance: Node2D
	if kind == KIND_ROCK:
		var rock: RockObstacle = ROCK_SCENE.instantiate() as RockObstacle
		rock.position = spawn_pos
		rock.randomize_appearance(_rng)
		instance = rock
	elif kind == KIND_STOP_SIGN:
		var sign_node: StopSignObstacle = STOP_SIGN_SCENE.instantiate() as StopSignObstacle
		sign_node.position = spawn_pos
		sign_node.rotation = tangent.angle()
		instance = sign_node
	else:
		var barrier: BarrierObstacle = BARRIER_SCENE.instantiate() as BarrierObstacle
		barrier.position = spawn_pos
		barrier.rotation = tangent.angle()
		instance = barrier

	instance.set_meta("route_group", slot_group)
	add_child(instance)
	return instance


func _pick_safe_lateral_offset(road_half_width: float, obs_half_width: float) -> float:
	var max_edge: float = maxf(4.0, road_half_width - obs_half_width - 7.0)
	var valid_offsets: Array[float] = []
	var steps: int = 12
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var candidate: float = lerpf(-max_edge, max_edge, t)
		var clearance_left: float = road_half_width - candidate - obs_half_width
		var clearance_right: float = road_half_width + candidate - obs_half_width
		if maxf(clearance_left, clearance_right) >= SimulationConfig.MIN_PASSABLE_CORRIDOR_WIDTH:
			valid_offsets.append(candidate)
	if valid_offsets.is_empty():
		var side: float = 1.0 if _rng.randf() >= 0.5 else -1.0
		return side * max_edge * 0.65
	return valid_offsets[_rng.randi_range(0, valid_offsets.size() - 1)]

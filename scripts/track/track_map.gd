class_name TrackMap
extends Node2D

signal route_switched(route_index: int, route_label: String)
signal gate_toggled(group_name: StringName, is_open: bool)
signal lap_completed(car: Node2D, lap_count: int)

@export var map_id: StringName = &"nordschleife"
@export var map_title: String = "Track"
@export var difficulty_tier: int = 1
@export var laps_per_route_switch: int = 3
@export var route_variant_groups: Array[StringName] = [&"route_a", &"route_b"]
@export var route_variant_labels: PackedStringArray = PackedStringArray(["Маршрут A (Основной)", "Маршрут B (Альтернативный)"])
@export var reference_lap_time: float = 16.0
@export var default_camera_center: Vector2 = Vector2(1050.0, 880.0)
@export var default_camera_zoom: float = 0.42
@export var start_checkpoint_id: StringName = &"cp_000"

var current_route_index: int = 0
var highest_lap_in_generation: int = 0
var _next_switch_lap: int = 3

var _checkpoints_by_id: Dictionary = {}
var _gates_by_group: Dictionary = {}
var _all_gates: Array[DynamicTrackGate] = []
var _active_groups: Dictionary = {}

@onready var spawn_point: Marker2D = $SpawnPoint
@onready var checkpoints_root: Node = get_node_or_null("Checkpoints")
@onready var gates_root: Node = get_node_or_null("DynamicGates")
@onready var obstacle_spawner: ObstacleSpawner = get_node_or_null("ObstacleSpawner") as ObstacleSpawner


func _ready() -> void:
	_index_checkpoints()
	_index_gates()
	_apply_route_variant(0, true)


func _index_checkpoints() -> void:
	_checkpoints_by_id.clear()
	if checkpoints_root == null:
		return
	for child in checkpoints_root.get_children():
		var cp: CheckpointNode = child as CheckpointNode
		if cp == null:
			continue
		_checkpoints_by_id[cp.checkpoint_id] = cp
		if not cp.car_entered_checkpoint.is_connected(_on_checkpoint_entered):
			cp.car_entered_checkpoint.connect(_on_checkpoint_entered)


func _index_gates() -> void:
	_gates_by_group.clear()
	_all_gates.clear()
	if gates_root == null:
		return
	for child in gates_root.get_children():
		var gate: DynamicTrackGate = child as DynamicTrackGate
		if gate == null:
			continue
		_all_gates.append(gate)
		if not _gates_by_group.has(gate.controlled_group):
			_gates_by_group[gate.controlled_group] = []
		_gates_by_group[gate.controlled_group].append(gate)
		if not gate.gate_state_changed.is_connected(_on_gate_state_changed):
			gate.gate_state_changed.connect(_on_gate_state_changed)


func reset_for_new_generation(generation_index: int) -> int:
	highest_lap_in_generation = 0
	_next_switch_lap = maxi(laps_per_route_switch, 1)
	_apply_route_variant(0, true)
	for gate in _all_gates:
		if gate.auto_cycle:
			gate.reset_gate()
	_refresh_active_groups()
	if obstacle_spawner != null:
		var seed_val: int = hash(str(map_id) + ":" + str(generation_index) + ":" + str(Time.get_ticks_usec()))
		return obstacle_spawner.respawn_for_generation(seed_val, _active_groups, get_spawn_transform().origin)
	return 0


func get_spawn_transform() -> Transform2D:
	if spawn_point != null:
		return spawn_point.global_transform
	return Transform2D.IDENTITY


func initialize_car_routing(car: Car) -> void:
	car.track_ref = self
	car.last_checkpoint_id = &""
	car.laps_completed = 0
	car.shortcuts_taken = 0
	car.current_lap_time = 0.0
	car.best_lap_time = 999.0
	car.expected_checkpoint_ids = [start_checkpoint_id]


func get_active_route_label() -> String:
	if current_route_index >= 0 and current_route_index < route_variant_labels.size():
		return route_variant_labels[current_route_index]
	if current_route_index >= 0 and current_route_index < route_variant_groups.size():
		return String(route_variant_groups[current_route_index])
	return "Основной"


func get_next_switch_lap() -> int:
	return _next_switch_lap


func get_open_next_ids(from_cp_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var cp: CheckpointNode = _checkpoints_by_id.get(from_cp_id, null) as CheckpointNode
	if cp == null:
		return result
	for next_id in cp.next_checkpoint_ids:
		var next_cp: CheckpointNode = _checkpoints_by_id.get(next_id, null) as CheckpointNode
		if next_cp == null:
			continue
		if _is_group_open(next_cp.route_group):
			result.append(next_id)
	if result.is_empty():
		return cp.next_checkpoint_ids.duplicate()
	return result


func get_guidance_target_for_car(car: Car) -> Vector2:
	if car == null:
		return get_spawn_transform().origin
	var open_ids: Array[StringName] = car.expected_checkpoint_ids
	if open_ids.is_empty():
		open_ids = [start_checkpoint_id]

	var fallback_pos: Vector2 = car.global_position + car.transform.x * 120.0
	var chosen_pos: Vector2 = fallback_pos
	var found_any: bool = false
	for cp_id in open_ids:
		var cp: CheckpointNode = _checkpoints_by_id.get(cp_id, null) as CheckpointNode
		if cp == null:
			continue
		if not _is_group_open(cp.route_group) and found_any:
			continue
		if not found_any:
			chosen_pos = cp.global_position
			found_any = true
		elif cp.is_shortcut and _is_group_open(cp.route_group):
			chosen_pos = cp.global_position
			break
	return chosen_pos


func advance_route_variant(living_cars: Array) -> String:
	if route_variant_groups.size() <= 1:
		return get_active_route_label()
	var next_idx: int = (current_route_index + 1) % route_variant_groups.size()
	_apply_route_variant(next_idx, false)

	var new_group: StringName = route_variant_groups[current_route_index]
	if obstacle_spawner != null:
		obstacle_spawner.respawn_group_obstacles(new_group, living_cars)

	for car in living_cars:
		if is_instance_valid(car) and car.is_alive and car.last_checkpoint_id != &"":
			car.expected_checkpoint_ids = get_open_next_ids(car.last_checkpoint_id)

	var label: String = get_active_route_label()
	route_switched.emit(current_route_index, label)
	return label


func toggle_auto_gates_manual() -> String:
	var toggled_count: int = 0
	var last_state: bool = true
	for gate in _all_gates:
		if gate.auto_cycle or gate.controlled_group.begins_with(&"fork") or gate.controlled_group.begins_with(&"corridor"):
			last_state = gate.toggle_manual()
			toggled_count += 1
	_refresh_active_groups()
	if toggled_count == 0:
		return "Нет дополнительных ворот"
	return "Ворота открыты" if last_state else "Ворота закрыты"


func get_obstacle_summary() -> Dictionary:
	if obstacle_spawner == null:
		return {"total": 0, "rocks": 0, "pedestrians": 0, "stop_signs": 0, "barriers": 0}
	return obstacle_spawner.get_obstacle_counts_summary()


func _apply_route_variant(route_idx: int, immediate: bool) -> void:
	if route_variant_groups.is_empty():
		return
	current_route_index = clampi(route_idx, 0, route_variant_groups.size() - 1)
	var active_variant: StringName = route_variant_groups[current_route_index]

	for variant_group in route_variant_groups:
		var should_open: bool = (variant_group == active_variant)
		if _gates_by_group.has(variant_group):
			for gate: DynamicTrackGate in _gates_by_group[variant_group]:
				gate.set_gate_open(should_open, immediate)
	_refresh_active_groups()


func _refresh_active_groups() -> void:
	_active_groups.clear()
	_active_groups[&"shared"] = true
	for variant_idx in range(route_variant_groups.size()):
		var grp: StringName = route_variant_groups[variant_idx]
		_active_groups[grp] = (variant_idx == current_route_index)
	for grp in _gates_by_group.keys():
		var any_open: bool = false
		for gate: DynamicTrackGate in _gates_by_group[grp]:
			if gate.is_gate_open():
				any_open = true
				break
		_active_groups[grp] = any_open


func _is_group_open(group_name: StringName) -> bool:
	if group_name == &"shared" or group_name == &"":
		return true
	return bool(_active_groups.get(group_name, true))


func _on_checkpoint_entered(body: Node2D, cp: CheckpointNode) -> void:
	var car: Car = body as Car
	if car == null or not car.is_alive:
		return
	var next_ids: Array[StringName] = get_open_next_ids(cp.checkpoint_id)
	var accepted: bool = car.on_graph_checkpoint_reached(
		cp.checkpoint_id,
		cp.reward_value,
		next_ids,
		cp.is_shortcut,
		cp.is_lap_finish
	)
	if accepted and cp.is_lap_finish and car.laps_completed > highest_lap_in_generation:
		highest_lap_in_generation = car.laps_completed
		lap_completed.emit(car, car.laps_completed)


func _on_gate_state_changed(gate: DynamicTrackGate, is_open: bool) -> void:
	_refresh_active_groups()
	gate_toggled.emit(gate.controlled_group, is_open)

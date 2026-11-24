class_name SimulationManager
extends Node2D

@export var car_scene: PackedScene = preload("res://scenes/agents/car.tscn")
@export var population_size: int = 50

var current_map_index: int = 0
var current_map: TrackMap = null
var generation: int = 1
var cars: Array[Car] = []
var alive_count: int = 0
var best_fitness: float = 0.0
var best_brain_ever: NeuralNetwork = null
var stagnation_count: int = 0
var generation_timer: float = 0.0
var dynamic_time_limit: float = SimulationConfig.BASE_GENERATION_TIME
var show_all_rays: bool = false
var transfer_brains_on_map_switch: bool = false
var _ending_generation: bool = false
var _last_hud_sync: float = 0.0

@onready var map_container: Node2D = $MapContainer
@onready var cars_container: Node2D = $CarsContainer
@onready var camera: CameraController = $CameraController as CameraController
@onready var hud: SimulationHUD = $HUD as SimulationHUD


func _ready() -> void:
	if hud:
		hud.map_selected.connect(_on_hud_map_selected)
		hud.camera_mode_toggled.connect(_on_camera_toggle_requested)
		hud.route_switch_requested.connect(_on_manual_route_switch)
		hud.gates_toggle_requested.connect(_on_manual_gates_toggle)
		hud.brain_transfer_toggled.connect(_on_brain_transfer_toggled)
	load_map(0)


func load_map(index: int) -> void:
	var map_count: int = MapRegistry.get_map_count()
	if map_count == 0:
		return
	current_map_index = clampi(index, 0, map_count - 1)
	var map_info: Dictionary = MapRegistry.get_map_by_index(current_map_index)
	var packed_map: PackedScene = load(String(map_info["scene_path"])) as PackedScene
	if packed_map == null:
		return

	_clear_cars()
	if current_map != null and is_instance_valid(current_map):
		current_map.queue_free()
		current_map = null

	current_map = packed_map.instantiate() as TrackMap
	map_container.add_child(current_map)
	current_map.route_switched.connect(_on_map_route_switched)
	current_map.lap_completed.connect(_on_map_lap_completed)

	population_size = int(map_info.get("recommended_population", 50))
	if camera:
		camera.configure_for_map(current_map.default_camera_center, current_map.default_camera_zoom)
		if hud:
			hud.update_camera_label(camera.get_mode_label())

	if hud:
		hud.set_selected_map(current_map_index, map_info)

	if not transfer_brains_on_map_switch:
		generation = 1
		best_fitness = 0.0
		best_brain_ever = null
		stagnation_count = 0
		spawn_generation([])
	else:
		generation = 1
		stagnation_count = 0
		var seed_brains: Array = []
		if best_brain_ever != null:
			seed_brains.append(best_brain_ever.clone())
		spawn_generation(seed_brains)


func spawn_generation(assigned_brains: Array) -> void:
	_clear_cars()
	if current_map == null:
		return

	current_map.reset_for_new_generation(generation)
	var spawn_tf: Transform2D = current_map.get_spawn_transform()

	alive_count = population_size
	generation_timer = 0.0
	dynamic_time_limit = SimulationConfig.BASE_GENERATION_TIME
	_ending_generation = false

	for i in range(population_size):
		var car: Car = car_scene.instantiate() as Car
		car.global_transform = spawn_tf
		if i < assigned_brains.size() and assigned_brains[i] != null:
			car.brain = assigned_brains[i]
			if i < GeneticEvolver.ELITE_SLOTS:
				car.is_elite = true
				car.show_rays = true
		car.crashed.connect(_on_car_crashed)
		cars_container.add_child(car)
		current_map.initialize_car_routing(car)
		cars.append(car)

	_update_leader_and_hud(true)


func _physics_process(delta: float) -> void:
	if current_map == null or alive_count <= 0 or _ending_generation:
		return

	generation_timer += delta
	if generation_timer >= dynamic_time_limit:
		_force_end_generation()
		return

	_last_hud_sync += delta
	var refresh_hud: bool = _last_hud_sync >= 0.25
	if refresh_hud:
		_last_hud_sync = 0.0
	_update_leader_and_hud(refresh_hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev: InputEventKey = event
		if key_ev.keycode >= KEY_1 and key_ev.keycode <= KEY_6:
			var target_map: int = int(key_ev.keycode - KEY_1)
			load_map(target_map)
		elif key_ev.keycode == KEY_R:
			show_all_rays = not show_all_rays
			_update_leader_and_hud(false)
		elif key_ev.keycode == KEY_C:
			_on_camera_toggle_requested()
		elif key_ev.keycode == KEY_M:
			_on_manual_route_switch()
		elif key_ev.keycode == KEY_G:
			_on_manual_gates_toggle()
		elif key_ev.keycode == KEY_SPACE:
			_force_end_generation()


func _update_leader_and_hud(update_hud_text: bool) -> void:
	var leader: Car = null
	var top_fit: float = -1.0
	for c in cars:
		if is_instance_valid(c) and c.is_alive and c.fitness > top_fit:
			top_fit = c.fitness
			leader = c

	for c in cars:
		if is_instance_valid(c) and c.is_alive:
			c.update_visual_state(c == leader, show_all_rays)

	if camera:
		camera.set_follow_target(leader)

	if update_hud_text and hud and current_map:
		var leader_lap: int = leader.laps_completed if leader != null else current_map.highest_lap_in_generation
		hud.update_telemetry(
			generation,
			alive_count,
			population_size,
			best_fitness,
			leader_lap,
			current_map.get_next_switch_lap(),
			current_map.get_active_route_label(),
			current_map.get_obstacle_summary(),
			dynamic_time_limit - generation_timer
		)


func _on_car_crashed(_car: Car) -> void:
	if _ending_generation:
		return
	alive_count = maxi(0, alive_count - 1)
	_update_leader_and_hud(true)
	if alive_count <= 0:
		_ending_generation = true
		next_generation.call_deferred()


func _force_end_generation() -> void:
	if _ending_generation:
		return
	_ending_generation = true
	alive_count = 0
	for c in cars:
		if is_instance_valid(c) and c.is_alive:
			c.die()
	next_generation.call_deferred()


func next_generation() -> void:
	if cars.is_empty():
		return
	var sorted_cars: Array = cars.duplicate()
	sorted_cars.sort_custom(func(a: Car, b: Car) -> bool: return a.fitness > b.fitness)

	var top_fit: float = sorted_cars[0].fitness
	if top_fit > best_fitness:
		best_fitness = top_fit
		if sorted_cars[0].brain != null:
			best_brain_ever = sorted_cars[0].brain.clone()
		stagnation_count = 0
	else:
		stagnation_count += 1

	var evo_result: Dictionary = GeneticEvolver.build_next_population_brains(
		sorted_cars,
		best_brain_ever,
		population_size,
		stagnation_count
	)
	generation += 1
	spawn_generation(evo_result["brains"])


func _on_map_lap_completed(_car: Node2D, lap_count: int) -> void:
	if current_map == null:
		return
	dynamic_time_limit = minf(
		SimulationConfig.MAX_GENERATION_TIME,
		SimulationConfig.BASE_GENERATION_TIME + float(lap_count) * SimulationConfig.EXTRA_TIME_PER_LAP
	)
	var switch_period: int = maxi(current_map.laps_per_route_switch, 1)
	if lap_count > 0 and lap_count >= current_map._next_switch_lap:
		current_map._next_switch_lap += switch_period
		current_map.advance_route_variant(cars)


func _on_map_route_switched(_route_index: int, route_label: String) -> void:
	if hud:
		hud.show_alert("СМЕНА МАРШРУТА: %s" % route_label, 3.6)
	_update_leader_and_hud(true)


func _on_hud_map_selected(index: int) -> void:
	if index != current_map_index:
		load_map(index)


func _on_camera_toggle_requested() -> void:
	if camera:
		camera.toggle_mode()
		if hud:
			hud.update_camera_label(camera.get_mode_label())


func _on_manual_route_switch() -> void:
	if current_map:
		var label: String = current_map.advance_route_variant(cars)
		if hud:
			hud.show_alert("РУЧНАЯ СМЕНА МАРШРУТА: %s" % label, 2.8)
		_update_leader_and_hud(true)


func _on_manual_gates_toggle() -> void:
	if current_map:
		var status_text: String = current_map.toggle_auto_gates_manual()
		if hud:
			hud.show_alert(status_text, 2.2)


func _on_brain_transfer_toggled(enabled: bool) -> void:
	transfer_brains_on_map_switch = enabled


func _clear_cars() -> void:
	for c in cars:
		if is_instance_valid(c):
			c.queue_free()
	cars.clear()

extends Node2D

@export var car_scene: PackedScene = preload("res://scenes/car.tscn")
@export var population_size: int = 50
@export var max_generation_time: float = 60.0

var generation: int = 1
var cars: Array = []
var alive_count: int = 0
var best_fitness: float = 0.0
var generation_timer: float = 0.0
var best_brain_ever: NeuralNetwork = null
var show_all_rays: bool = false
var _ending_generation: bool = false

@onready var spawn_point: Marker2D = $SpawnPoint
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	var checkpoints_root: Node = get_node_or_null("Checkpoints")
	if checkpoints_root:
		var cps: Array = checkpoints_root.get_children()
		for i in range(cps.size()):
			var area: Area2D = cps[i] as Area2D
			if area:
				area.body_entered.connect(_on_checkpoint_entered.bind(i, cps.size()))
	spawn_generation([])

func _on_checkpoint_entered(body: Node2D, index: int, total: int) -> void:
	if body.has_method("on_checkpoint_reached"):
		body.on_checkpoint_reached(index, total)

func _physics_process(delta: float) -> void:
	if alive_count <= 0 or _ending_generation:
		return
	
	generation_timer += delta
	if generation_timer >= max_generation_time:
		_force_end_generation()
		return
	
	_update_leader_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			show_all_rays = not show_all_rays
			_update_leader_highlight()
		elif event.keycode == KEY_SPACE:
			_force_end_generation()

func _update_leader_highlight() -> void:
	var leader: Node2D = null
	var top_fit: float = -1.0
	for c in cars:
		if is_instance_valid(c) and c.is_alive and c.fitness > top_fit:
			top_fit = c.fitness
			leader = c
	for c in cars:
		if is_instance_valid(c) and c.is_alive:
			c.update_visual_state(c == leader, show_all_rays)

func spawn_generation(parent_brains: Array) -> void:
	for c in cars:
		if is_instance_valid(c):
			c.queue_free()
	cars.clear()
	
	alive_count = population_size
	generation_timer = 0.0
	_ending_generation = false
	
	for i in range(population_size):
		var car = car_scene.instantiate()
		car.global_position = spawn_point.global_position
		car.global_rotation = spawn_point.global_rotation
		
		if parent_brains.size() > 0:
			if i < 3:
				car.brain = parent_brains[i % parent_brains.size()].clone()
				car.is_elite = true
				car.show_rays = true
			elif i >= population_size - 2:
				car.brain = null # Свежие случайные мозги для разнообразия
			else:
				var p_idx: int = int(pow(randf(), 1.8) * parent_brains.size())
				var parent: NeuralNetwork = parent_brains[p_idx]
				car.brain = parent.clone()
				car.brain.mutate(0.2, 0.35)
		
		car.crashed.connect(_on_car_crashed)
		add_child(car)
		cars.append(car)
	
	_update_leader_highlight()
	hud.update_stats(generation, alive_count, population_size, best_fitness)

func _on_car_crashed(_car) -> void:
	if _ending_generation:
		return
	alive_count -= 1
	hud.update_stats(generation, alive_count, population_size, best_fitness)
	
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
	cars.sort_custom(func(a, b): return a.fitness > b.fitness)
	
	var new_record: bool = cars[0].fitness > best_fitness
	if new_record:
		best_fitness = cars[0].fitness
		best_brain_ever = cars[0].brain.clone()
	
	var top_brains: Array = []
	if best_brain_ever != null:
		top_brains.append(best_brain_ever)
	for i in range(1 if new_record else 0, min(6, cars.size())):
		if top_brains.size() < 5:
			top_brains.append(cars[i].brain)
	
	generation += 1
	spawn_generation(top_brains)

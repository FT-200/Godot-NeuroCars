extends CharacterBody2D

signal crashed(car)

@export var max_speed: float = 350.0
@export var turn_speed: float = 3.5

var brain: NeuralNetwork
var is_alive: bool = true
var fitness: float = 0.0
var time_alive: float = 0.0

var next_checkpoint: int = 0
var time_since_checkpoint: float = 0.0
var segment_fitness: float = 0.0
var show_rays: bool = false
var is_elite: bool = false

@onready var sensors: Array = $Sensors.get_children()
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var wheel_fl: Node2D = get_node_or_null("CarModel/Wheels/WheelFL")
@onready var wheel_fr: Node2D = get_node_or_null("CarModel/Wheels/WheelFR")

func _ready() -> void:
	if brain == null:
		brain = NeuralNetwork.new(sensors.size(), 6, 2)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	time_alive += delta
	time_since_checkpoint += delta
	
	# Награда за пройденное расстояние в текущем сегменте (с потолком 40, чтобы не фармили на месте)
	var step_fit: float = minf(velocity.length() * delta * 0.1, 40.0 - segment_fitness)
	segment_fitness += step_fit
	fitness += step_fit
	
	# Если машина крутится на месте или не может доехать до следующего чекпоинта — выключаем
	if (time_alive > 3.0 and fitness < 50.0) or time_since_checkpoint > 4.0:
		die()
		return
	
	# 1. Собираем данные с 5 лучей
	var inputs: Array = []
	for ray: RayCast2D in sensors:
		if ray.is_colliding():
			var origin = ray.global_position
			var hit_point = ray.get_collision_point()
			var dist = origin.distance_to(hit_point)
			var max_len = ray.target_position.length()
			inputs.append(dist / max_len) # От 0.0 (упор) до 1.0 (далеко)
		else:
			inputs.append(1.0)
	
	# 2. Спрашиваем решение у нейросети
	var outputs = brain.predict(inputs)
	var steer = outputs[0] # От -1 до 1
	var throttle = clamp((outputs[1] + 1.0) * 0.5, 0.2, 1.0) # От 0.2 до 1.0 (чтобы не стояла)
	
	# 3. Двигаем машину и поворачиваем передние колёса новой модели
	rotation += steer * turn_speed * delta
	velocity = transform.x * (throttle * max_speed)
	if wheel_fl and wheel_fr:
		wheel_fl.rotation = steer * 0.45
		wheel_fr.rotation = steer * 0.45
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		die()
		return
	
	# Перерисовываем лучи только если у этой машины включено отображение сенсоров
	if show_rays:
		queue_redraw()

func on_checkpoint_reached(index: int, total_checkpoints: int) -> void:
	if not is_alive or index != next_checkpoint:
		return
	fitness += 200.0 + maxf(0.0, 4.0 - time_since_checkpoint) * 25.0
	time_since_checkpoint = 0.0
	segment_fitness = 0.0
	next_checkpoint = (next_checkpoint + 1) % total_checkpoints
	if next_checkpoint == 0:
		fitness += 500.0 # Бонус за полный круг

func update_visual_state(is_leader: bool, force_rays: bool) -> void:
	if not is_alive:
		return
	var target_rays: bool = is_leader or is_elite or force_rays
	if is_leader:
		modulate = Color(0.2, 1.0, 0.2)
		z_index = 10
	elif is_elite:
		modulate = Color(0.45, 0.95, 0.45)
		z_index = 5
	else:
		modulate = Color(1.0, 1.0, 1.0)
		z_index = 1
	if show_rays != target_rays:
		show_rays = target_rays
		queue_redraw()

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	show_rays = false
	z_index = 0
	modulate = Color(1, 1, 1, 0.25) # Делаем полупрозрачной после аварии
	for ray: RayCast2D in sensors:
		ray.enabled = false
	collision_shape.set_deferred("disabled", true)
	queue_redraw() # Убираем лучи после смерти
	crashed.emit(self)

func _draw() -> void:
	if not is_alive or not show_rays:
		return
	for ray: RayCast2D in sensors:
		var end_pos: Vector2
		var line_color: Color
		if ray.is_colliding():
			end_pos = to_local(ray.get_collision_point())
			line_color = Color(1.0, 0.2, 0.2, 0.8) # Красный луч — видит стену
		else:
			end_pos = to_local(ray.to_global(ray.target_position))
			line_color = Color(0.2, 1.0, 0.2, 0.35) # Зелёный луч — путь свободен
		draw_line(to_local(ray.global_position), end_pos, line_color, 1.5)

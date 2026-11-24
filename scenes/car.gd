extends CharacterBody2D

signal crashed(car)

@export var max_speed: float = 350.0
@export var turn_speed: float = 3.5

var brain: NeuralNetwork
var is_alive: bool = true
var fitness: float = 0.0
var time_alive: float = 0.0

@onready var sensors: Array = $Sensors.get_children()

func _ready() -> void:
	add_to_group("cars") # <--- НОВОЕ ОТ МЕНЯ добавляем машину в общий список
	input_pickable = true # <--- НОВОЕ ОТ МЕНЯ разрешаем кликать по машине
	if brain == null:
		brain = NeuralNetwork.new(sensors.size(), 6, 2)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	time_alive += delta
	# Награда за пройденное расстояние
	fitness += velocity.length() * delta * 0.1
	
	# Если машина крутится на месте или стоит больше 3 секунд — выключаем
	if time_alive > 3.0 and fitness < 50.0:
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
	
	# 3. Двигаем машину
	rotation += steer * turn_speed * delta
	velocity = transform.x * (throttle * max_speed)
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		die()

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	modulate = Color(1, 1, 1, 0.25) # Делаем полупрозрачной после аварии
	crashed.emit(self)

# <--- НОВОЕ ОТ МЕНЯ обработка клика левой кнопкой мыши по машине
func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pip = get_tree().get_first_node_in_group("pip_screen")
		if pip:
			pip.watch_car(self)

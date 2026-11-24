# ВСЕ ЭТО ОТ САНЖАРА
extends PanelContainer

@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var pip_camera: Camera2D = $SubViewportContainer/SubViewport/Camera2D

var target: CharacterBody2D = null

func _ready() -> void:
	add_to_group("pip_screen")
	sub_viewport.world_2d = get_tree().root.world_2d
	pip_camera.zoom = Vector2(1.5, 1.5)
	hide()

func _process(_delta: float) -> void:
	if is_instance_valid(target):
		pip_camera.global_position = target.global_position
		if not target.is_alive:
			switch_to_next_alive_car()
	elif visible:
		stop_watching()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)):
		stop_watching()
	
	if event.is_action_pressed("ui_focus_next"):
		switch_to_next_alive_car()

func watch_car(car: CharacterBody2D) -> void:
	target = car
	pip_camera.global_position = car.global_position
	show()

func stop_watching() -> void:
	target = null
	hide()

func switch_to_next_alive_car() -> void:
	var all_cars = get_tree().get_nodes_in_group("cars")
	var alive_cars = all_cars.filter(func(c): return is_instance_valid(c) and c.is_alive)
	
	if alive_cars.is_empty():
		stop_watching()
		return
	
	var current_idx = alive_cars.find(target)
	var next_idx = (current_idx + 1) % alive_cars.size()
	watch_car(alive_cars[next_idx])

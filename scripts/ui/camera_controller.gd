class_name CameraController
extends Camera2D

enum Mode {
	OVERVIEW,
	FOLLOW_LEADER,
}

var mode: Mode = Mode.OVERVIEW
var overview_center: Vector2 = Vector2(1050.0, 880.0)
var overview_zoom: float = 0.42
var target_zoom: float = 0.42
var follow_target: Node2D = null
var _is_panning: bool = false


func configure_for_map(center: Vector2, default_zoom: float) -> void:
	overview_center = center
	overview_zoom = clampf(default_zoom, 0.22, 1.5)
	if mode == Mode.OVERVIEW:
		position = overview_center
		target_zoom = overview_zoom
		zoom = Vector2(target_zoom, target_zoom)


func toggle_mode() -> Mode:
	if mode == Mode.OVERVIEW:
		mode = Mode.FOLLOW_LEADER
		target_zoom = 0.85
	else:
		mode = Mode.OVERVIEW
		target_zoom = overview_zoom
	return mode


func set_follow_target(target: Node2D) -> void:
	follow_target = target


func get_mode_label() -> String:
	return "Камера: Лидер" if mode == Mode.FOLLOW_LEADER else "Камера: Обзор"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clampf(target_zoom * 1.12, 0.22, 1.8)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clampf(target_zoom * 0.89, 0.22, 1.8)
			elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
				if mode == Mode.OVERVIEW:
					_is_panning = true
		else:
			if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning = false
	elif event is InputEventMouseMotion and _is_panning and mode == Mode.OVERVIEW:
		var mm: InputEventMouseMotion = event
		position -= mm.relative / maxf(zoom.x, 0.1)


func _process(delta: float) -> void:
	var smooth: float = clampf(delta * 6.5, 0.0, 1.0)
	var zoom_vec: Vector2 = Vector2(target_zoom, target_zoom)
	zoom = zoom.lerp(zoom_vec, smooth)

	if mode == Mode.FOLLOW_LEADER and is_instance_valid(follow_target):
		position = position.lerp(follow_target.global_position, clampf(delta * 8.0, 0.0, 1.0))
	elif mode == Mode.OVERVIEW and not _is_panning:
		position = position.lerp(overview_center, smooth * 0.65)

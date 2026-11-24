class_name SimulationHUD
extends CanvasLayer

signal map_selected(index: int)
signal camera_mode_toggled
signal route_switch_requested
signal gates_toggle_requested
signal brain_transfer_toggled(enabled: bool)

const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0]

var speed_index: int = 0
var _alert_timer: float = 0.0

@onready var map_title_label: Label = $StatsPanel/Margin/VBox/MapTitleLabel
@onready var stats_label: Label = $StatsPanel/Margin/VBox/StatsLabel
@onready var route_label: Label = $StatsPanel/Margin/VBox/RouteLabel
@onready var obstacles_label: Label = $StatsPanel/Margin/VBox/ObstaclesLabel

@onready var map_selector: OptionButton = $TopBar/HBox/MapSelector
@onready var transfer_check: CheckButton = $TopBar/HBox/TransferCheck
@onready var speed_button: Button = $TopBar/HBox/SpeedButton
@onready var camera_button: Button = $TopBar/HBox/CameraButton
@onready var route_button: Button = $TopBar/HBox/RouteButton

@onready var alert_banner: PanelContainer = $AlertBanner
@onready var alert_label: Label = $AlertBanner/Margin/AlertLabel
@onready var circuit_badge: Label = $CircuitBadge


func _ready() -> void:
	Engine.max_physics_steps_per_frame = 16
	if alert_banner:
		alert_banner.visible = false
	_populate_map_selector()
	if map_selector:
		map_selector.item_selected.connect(_on_map_selected)
	if transfer_check:
		transfer_check.toggled.connect(_on_transfer_toggled)
	if speed_button:
		speed_button.pressed.connect(_on_speed_button_pressed)
	if camera_button:
		camera_button.pressed.connect(_on_camera_button_pressed)
	if route_button:
		route_button.pressed.connect(_on_route_button_pressed)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	if _alert_timer > 0.0:
		_alert_timer -= delta
		if _alert_timer <= 0.0 and alert_banner:
			alert_banner.visible = false


func _populate_map_selector() -> void:
	if map_selector == null:
		return
	map_selector.clear()
	var maps: Array[Dictionary] = MapRegistry.get_all_maps()
	for i in range(maps.size()):
		var info: Dictionary = maps[i]
		var stars: String = "*".repeat(int(info.get("difficulty_stars", 1)))
		map_selector.add_item("%d. %s [%s]" % [i + 1, String(info["title"]), stars], i)


func set_selected_map(index: int, map_info: Dictionary) -> void:
	if map_selector and index >= 0 and index < map_selector.item_count:
		map_selector.select(index)
	var stars_count: int = int(map_info.get("difficulty_stars", 1))
	var stars_text: String = "★".repeat(stars_count) + "☆".repeat(maxi(0, 6 - stars_count))
	if map_title_label:
		map_title_label.text = "%s  %s" % [String(map_info.get("title", "Трасса")), stars_text]
	if circuit_badge:
		circuit_badge.text = "%s  •  %d AGENTS" % [String(map_info.get("title", "NEURO")).to_upper(), int(map_info.get("recommended_population", 50))]


func update_telemetry(
	gen: int,
	alive: int,
	total: int,
	best: float,
	leader_lap: int,
	switch_lap: int,
	active_route: String,
	obs_summary: Dictionary,
	time_left: float
) -> void:
	if stats_label:
		stats_label.text = "Поколение: %d   |   Таймер: %ds\nЖивых: %d / %d   |   Рекорд: %.0f\nКруг лидера: %d (смена на %d)" % [
			gen,
			int(ceilf(maxf(time_left, 0.0))),
			alive,
			total,
			best,
			leader_lap,
			switch_lap,
		]
	if route_label:
		route_label.text = "Маршрут: %s" % active_route
	if obstacles_label:
		obstacles_label.text = "Преграды: %d (К:%d П:%d С:%d Б:%d)" % [
			int(obs_summary.get("total", 0)),
			int(obs_summary.get("rocks", 0)),
			int(obs_summary.get("pedestrians", 0)),
			int(obs_summary.get("stop_signs", 0)),
			int(obs_summary.get("barriers", 0)),
		]


func update_camera_label(label_text: String) -> void:
	if camera_button:
		camera_button.text = label_text


func show_alert(text: String, duration: float = 3.2) -> void:
	if alert_label:
		alert_label.text = text
	if alert_banner:
		alert_banner.visible = true
	_alert_timer = duration


func _on_map_selected(index: int) -> void:
	map_selected.emit(index)


func _on_transfer_toggled(pressed: bool) -> void:
	brain_transfer_toggled.emit(pressed)


func _on_speed_button_pressed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	var s: float = SPEEDS[speed_index]
	Engine.time_scale = s
	speed_button.text = "Скорость: x%d" % int(s)


func _on_camera_button_pressed() -> void:
	camera_mode_toggled.emit()


func _on_route_button_pressed() -> void:
	route_switch_requested.emit()

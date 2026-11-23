extends CanvasLayer

const SPEEDS: Array = [1.0, 2.0, 5.0, 10.0]

var speed_index: int = 0

@onready var stats_label: Label = $StatsLabel
@onready var speed_button: Button = $SpeedButton

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 16
	speed_button.pressed.connect(_on_speed_button_pressed)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func update_stats(gen: int, alive: int, total: int, best: float) -> void:
	stats_label.text = "Поколение: %d\nЖивых: %d / %d\nРекорд: %.0f" % [gen, alive, total, best]

func _on_speed_button_pressed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	var s: float = SPEEDS[speed_index]
	Engine.time_scale = s
	speed_button.text = "Скорость: x%d" % int(s)

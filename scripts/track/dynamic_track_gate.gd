class_name DynamicTrackGate
extends StaticBody2D

signal gate_state_changed(gate: DynamicTrackGate, is_open: bool)

enum GateState {
	OPEN,
	WARNING,
	CLOSED,
}

@export var gate_id: StringName = &""
@export var controlled_group: StringName = &""
@export var gate_width: float = 110.0
@export var auto_cycle: bool = false
@export var open_duration: float = 12.0
@export var closed_duration: float = 8.0
@export var warning_duration: float = 1.8
@export var phase_offset: float = 0.0
@export var initial_open: bool = true

var state: GateState = GateState.OPEN
var _cycle_timer: float = 0.0
var _pending_close: bool = false
var _grace_timer: float = 0.0
var _pulse_time: float = 0.0

@onready var barrier_collision: CollisionShape2D = $BarrierCollision
@onready var safety_sensor: Area2D = $SafetySensor
@onready var safety_shape: CollisionShape2D = $SafetySensor/SafetyShape
@onready var closed_visual: Node2D = $ClosedVisual
@onready var open_visual: Node2D = $OpenVisual
@onready var beacon_left: Polygon2D = $BeaconLeft
@onready var beacon_right: Polygon2D = $BeaconRight


func _ready() -> void:
	collision_layer = SimulationConfig.LAYER_WALLS
	collision_mask = 0
	if safety_sensor:
		safety_sensor.collision_layer = 0
		safety_sensor.collision_mask = SimulationConfig.LAYER_CARS
		safety_sensor.monitoring = true
		safety_sensor.monitorable = false
	_apply_width_geometry()
	reset_gate()


func _apply_width_geometry() -> void:
	var half_w: float = gate_width * 0.5
	if barrier_collision and barrier_collision.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = barrier_collision.shape.duplicate() as RectangleShape2D
		rect_shape.size = Vector2(14.0, gate_width)
		barrier_collision.shape = rect_shape
	if safety_shape and safety_shape.shape is RectangleShape2D:
		var safe_rect: RectangleShape2D = safety_shape.shape.duplicate() as RectangleShape2D
		safe_rect.size = Vector2(46.0, gate_width + 12.0)
		safety_shape.shape = safe_rect
	if beacon_left:
		beacon_left.position = Vector2(0.0, -half_w - 4.0)
	if beacon_right:
		beacon_right.position = Vector2(0.0, half_w + 4.0)
	if closed_visual:
		closed_visual.scale = Vector2(1.0, gate_width / 110.0)
	if open_visual:
		open_visual.scale = Vector2(1.0, gate_width / 110.0)


func reset_gate() -> void:
	_pending_close = false
	_grace_timer = 0.0
	_pulse_time = 0.0
	if auto_cycle:
		var total_cycle: float = maxf(open_duration + warning_duration + closed_duration, 1.0)
		_cycle_timer = fposmod(phase_offset, total_cycle)
		_evaluate_auto_cycle_state(true)
	else:
		_set_state(GateState.OPEN if initial_open else GateState.CLOSED, true)


func set_gate_open(should_open: bool, immediate: bool = false) -> void:
	if should_open:
		_pending_close = false
		_grace_timer = 0.0
		_set_state(GateState.OPEN, immediate)
	else:
		if immediate:
			_pending_close = false
			_set_state(GateState.CLOSED, true)
		else:
			_begin_safe_close()


func toggle_manual() -> bool:
	var target_open: bool = state != GateState.OPEN
	set_gate_open(target_open, false)
	return target_open


func is_gate_open() -> bool:
	return state != GateState.CLOSED


func _physics_process(delta: float) -> void:
	_pulse_time += delta
	if auto_cycle:
		var total_cycle: float = maxf(open_duration + warning_duration + closed_duration, 1.0)
		_cycle_timer = fposmod(_cycle_timer + delta, total_cycle)
		_evaluate_auto_cycle_state(false)

	if _pending_close:
		_grace_timer += delta
		var occupied: bool = safety_sensor != null and not safety_sensor.get_overlapping_bodies().is_empty()
		if not occupied or _grace_timer >= 0.6:
			_pending_close = false
			_set_state(GateState.CLOSED, false)

	_update_beacon_colors()


func _evaluate_auto_cycle_state(immediate: bool) -> void:
	if _cycle_timer < open_duration:
		if state != GateState.OPEN:
			_pending_close = false
			_set_state(GateState.OPEN, immediate)
	elif _cycle_timer < open_duration + warning_duration:
		if state == GateState.OPEN:
			_set_state(GateState.WARNING, immediate)
	else:
		if state != GateState.CLOSED and not _pending_close:
			if immediate:
				_set_state(GateState.CLOSED, true)
			else:
				_begin_safe_close()


func _begin_safe_close() -> void:
	if state == GateState.CLOSED:
		return
	var occupied: bool = safety_sensor != null and not safety_sensor.get_overlapping_bodies().is_empty()
	if occupied:
		_pending_close = true
		_grace_timer = 0.0
		_set_state(GateState.WARNING, false)
	else:
		_pending_close = false
		_set_state(GateState.CLOSED, false)


func _set_state(new_state: GateState, immediate: bool) -> void:
	var was_open: bool = state != GateState.CLOSED
	state = new_state
	var is_now_open: bool = state != GateState.CLOSED
	if barrier_collision:
		if immediate:
			barrier_collision.disabled = is_now_open
		else:
			barrier_collision.set_deferred("disabled", is_now_open)
	if closed_visual:
		closed_visual.visible = (state == GateState.CLOSED)
	if open_visual:
		open_visual.visible = (state != GateState.CLOSED)
	_update_beacon_colors()
	if was_open != is_now_open or immediate:
		gate_state_changed.emit(self, is_now_open)


func _update_beacon_colors() -> void:
	var color: Color
	if state == GateState.OPEN:
		color = Color(0.18, 0.94, 0.44, 1.0)
	elif state == GateState.WARNING:
		var pulse: float = 0.45 + 0.55 * absf(sin(_pulse_time * 12.0))
		color = Color(1.0, 0.75, 0.12, pulse)
	else:
		color = Color(0.96, 0.22, 0.24, 1.0)
	if beacon_left:
		beacon_left.color = color
	if beacon_right:
		beacon_right.color = color

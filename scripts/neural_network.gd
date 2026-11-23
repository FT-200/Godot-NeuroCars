class_name NeuralNetwork
extends RefCounted

var input_nodes: int
var hidden_nodes: int
var output_nodes: int

var weights_ih: Array = []
var weights_ho: Array = []
var bias_h: Array = []
var bias_o: Array = []

func _init(inputs: int = 5, hidden: int = 6, outputs: int = 2) -> void:
	input_nodes = inputs
	hidden_nodes = hidden
	output_nodes = outputs
	weights_ih = _create_matrix(hidden_nodes, input_nodes)
	weights_ho = _create_matrix(output_nodes, hidden_nodes)
	bias_h = _create_array(hidden_nodes)
	bias_o = _create_array(output_nodes)

func _create_matrix(rows: int, cols: int) -> Array:
	var mat = []
	for i in range(rows):
		var row = []
		for j in range(cols):
			row.append(randf_range(-1.0, 1.0))
		mat.append(row)
	return mat

func _create_array(size: int) -> Array:
	var arr = []
	for i in range(size):
		arr.append(randf_range(-1.0, 1.0))
	return arr

func predict(inputs: Array) -> Array:
	var hidden = []
	for i in range(hidden_nodes):
		var sum = bias_h[i]
		for j in range(input_nodes):
			sum += inputs[j] * weights_ih[i][j]
		hidden.append(tanh(sum))
	
	var outputs = []
	for i in range(output_nodes):
		var sum = bias_o[i]
		for j in range(hidden_nodes):
			sum += hidden[j] * weights_ho[i][j]
		outputs.append(tanh(sum))
	
	return outputs

func clone() -> NeuralNetwork:
	var copy = NeuralNetwork.new(input_nodes, hidden_nodes, output_nodes)
	copy.weights_ih = weights_ih.duplicate(true)
	copy.weights_ho = weights_ho.duplicate(true)
	copy.bias_h = bias_h.duplicate(true)
	copy.bias_o = bias_o.duplicate(true)
	return copy

func mutate(rate: float = 0.15, strength: float = 0.3) -> void:
	for i in range(weights_ih.size()):
		for j in range(weights_ih[i].size()):
			if randf() < rate:
				weights_ih[i][j] = clampf(weights_ih[i][j] + randfn(0.0, strength), -4.0, 4.0)
	
	for i in range(weights_ho.size()):
		for j in range(weights_ho[i].size()):
			if randf() < rate:
				weights_ho[i][j] = clampf(weights_ho[i][j] + randfn(0.0, strength), -4.0, 4.0)
	
	for i in range(bias_h.size()):
		if randf() < rate:
			bias_h[i] = clampf(bias_h[i] + randfn(0.0, strength), -4.0, 4.0)
	
	for i in range(bias_o.size()):
		if randf() < rate:
			bias_o[i] = clampf(bias_o[i] + randfn(0.0, strength), -4.0, 4.0)

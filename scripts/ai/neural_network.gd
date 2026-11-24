class_name NeuralNetwork
extends RefCounted

var layer_sizes: Array[int] = []
var weights: Array = []
var biases: Array = []


func _init(sizes: Array[int] = SimulationConfig.DEFAULT_NETWORK_LAYERS) -> void:
	if sizes.size() < 2:
		layer_sizes = SimulationConfig.DEFAULT_NETWORK_LAYERS.duplicate()
	else:
		layer_sizes = sizes.duplicate()
	_initialize_parameters()


func _initialize_parameters() -> void:
	weights.clear()
	biases.clear()
	for layer_idx in range(layer_sizes.size() - 1):
		var fan_in: int = layer_sizes[layer_idx]
		var fan_out: int = layer_sizes[layer_idx + 1]
		var limit: float = sqrt(6.0 / float(maxi(fan_in + fan_out, 1)))
		var matrix: Array = []
		for _out_i in range(fan_out):
			var row: PackedFloat32Array = PackedFloat32Array()
			row.resize(fan_in)
			for in_j in range(fan_in):
				row[in_j] = randf_range(-limit, limit)
			matrix.append(row)
		weights.append(matrix)
		var bias_vec: PackedFloat32Array = PackedFloat32Array()
		bias_vec.resize(fan_out)
		for out_i in range(fan_out):
			bias_vec[out_i] = randf_range(-limit * 0.5, limit * 0.5)
		biases.append(bias_vec)


func predict(inputs: Array) -> Array[float]:
	var activations: PackedFloat32Array = PackedFloat32Array()
	var input_count: int = layer_sizes[0]
	activations.resize(input_count)
	for i in range(input_count):
		activations[i] = float(inputs[i]) if i < inputs.size() else 0.0

	for layer_idx in range(weights.size()):
		var matrix: Array = weights[layer_idx]
		var bias_vec: PackedFloat32Array = biases[layer_idx]
		var out_count: int = bias_vec.size()
		var next_activations: PackedFloat32Array = PackedFloat32Array()
		next_activations.resize(out_count)
		var in_count: int = activations.size()
		for i in range(out_count):
			var row: PackedFloat32Array = matrix[i]
			var weighted_sum: float = bias_vec[i]
			for j in range(in_count):
				weighted_sum += activations[j] * row[j]
			next_activations[i] = tanh(weighted_sum)
		activations = next_activations

	var result: Array[float] = []
	for val in activations:
		result.append(val)
	return result


func clone() -> NeuralNetwork:
	var copy: NeuralNetwork = NeuralNetwork.new(layer_sizes)
	copy.weights.clear()
	copy.biases.clear()
	for layer_idx in range(weights.size()):
		var src_matrix: Array = weights[layer_idx]
		var dst_matrix: Array = []
		for row in src_matrix:
			dst_matrix.append(row.duplicate())
		copy.weights.append(dst_matrix)
		copy.biases.append(biases[layer_idx].duplicate())
	return copy


func crossover(partner: NeuralNetwork) -> NeuralNetwork:
	if partner == null or partner.layer_sizes != layer_sizes:
		return clone()
	var child: NeuralNetwork = NeuralNetwork.new(layer_sizes)
	for layer_idx in range(weights.size()):
		var src_a: Array = weights[layer_idx]
		var src_b: Array = partner.weights[layer_idx]
		var bias_a: PackedFloat32Array = biases[layer_idx]
		var bias_b: PackedFloat32Array = partner.biases[layer_idx]
		var dst_matrix: Array = child.weights[layer_idx]
		var dst_bias: PackedFloat32Array = child.biases[layer_idx]
		for out_i in range(dst_bias.size()):
			var take_self: bool = randf() < 0.5
			var chosen_row: PackedFloat32Array = src_a[out_i] if take_self else src_b[out_i]
			dst_matrix[out_i] = chosen_row.duplicate()
			dst_bias[out_i] = bias_a[out_i] if take_self else bias_b[out_i]
	return child


func mutate(rate: float = 0.14, strength: float = 0.28) -> void:
	for layer_idx in range(weights.size()):
		var matrix: Array = weights[layer_idx]
		var bias_vec: PackedFloat32Array = biases[layer_idx]
		for out_i in range(matrix.size()):
			var row: PackedFloat32Array = matrix[out_i]
			for in_j in range(row.size()):
				if randf() < rate:
					row[in_j] = clampf(row[in_j] + randfn(0.0, strength), -4.5, 4.5)
			if randf() < rate:
				bias_vec[out_i] = clampf(bias_vec[out_i] + randfn(0.0, strength), -4.5, 4.5)


func is_compatible_with(expected_sizes: Array[int]) -> bool:
	return layer_sizes == expected_sizes


func to_dict() -> Dictionary:
	var serialized_weights: Array = []
	for matrix in weights:
		var layer_rows: Array = []
		for row in matrix:
			layer_rows.append(Array(row))
		serialized_weights.append(layer_rows)
	var serialized_biases: Array = []
	for bias_vec in biases:
		serialized_biases.append(Array(bias_vec))
	return {
		"layer_sizes": layer_sizes.duplicate(),
		"weights": serialized_weights,
		"biases": serialized_biases,
	}


static func from_dict(data: Dictionary) -> NeuralNetwork:
	var raw_sizes: Array = data.get("layer_sizes", [])
	var typed_sizes: Array[int] = []
	for val in raw_sizes:
		typed_sizes.append(int(val))
	if typed_sizes.size() < 2:
		typed_sizes = SimulationConfig.DEFAULT_NETWORK_LAYERS.duplicate()
	var net: NeuralNetwork = NeuralNetwork.new(typed_sizes)
	var raw_weights: Array = data.get("weights", [])
	var raw_biases: Array = data.get("biases", [])
	if raw_weights.size() == net.weights.size() and raw_biases.size() == net.biases.size():
		for layer_idx in range(raw_weights.size()):
			var layer_rows: Array = raw_weights[layer_idx]
			for out_i in range(mini(layer_rows.size(), net.weights[layer_idx].size())):
				net.weights[layer_idx][out_i] = PackedFloat32Array(layer_rows[out_i])
			net.biases[layer_idx] = PackedFloat32Array(raw_biases[layer_idx])
	return net

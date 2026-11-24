class_name GeneticEvolver
extends RefCounted

const ELITE_SLOTS: int = 4
const RANDOM_SLOTS: int = 3
const PARENT_POOL_LIMIT: int = 10


static func build_next_population_brains(
	sorted_cars: Array,
	champion_brain: NeuralNetwork,
	population_size: int,
	stagnation_count: int
) -> Dictionary:
	var pool: Array[NeuralNetwork] = []
	if champion_brain != null:
		pool.append(champion_brain.clone())

	for car in sorted_cars:
		if car != null and car.brain != null:
			var candidate: NeuralNetwork = car.brain
			var duplicate_found: bool = false
			for existing in pool:
				if existing == candidate:
					duplicate_found = true
					break
			if not duplicate_found:
				pool.append(candidate.clone())
		if pool.size() >= PARENT_POOL_LIMIT:
			break

	var brains: Array[NeuralNetwork] = []
	if pool.is_empty():
		for _i in range(population_size):
			brains.append(NeuralNetwork.new(SimulationConfig.DEFAULT_NETWORK_LAYERS))
		return {"brains": brains, "elite_count": 0}

	var elite_count: int = mini(ELITE_SLOTS, mini(pool.size(), population_size))
	for i in range(elite_count):
		brains.append(pool[i].clone())

	var random_tail: int = mini(RANDOM_SLOTS, maxi(0, population_size - elite_count))
	var offspring_count: int = maxi(0, population_size - elite_count - random_tail)
	var stagnation_boost: bool = stagnation_count >= 3

	for idx in range(offspring_count):
		var parent_a: NeuralNetwork = _select_parent(pool)
		var child: NeuralNetwork
		if pool.size() > 1 and randf() < 0.70:
			var parent_b: NeuralNetwork = _select_parent(pool)
			child = parent_a.crossover(parent_b)
		else:
			child = parent_a.clone()

		var mut_rate: float = 0.16
		var mut_strength: float = 0.28
		if stagnation_boost and idx % 2 == 0:
			mut_rate = 0.28
			mut_strength = 0.48
		child.mutate(mut_rate, mut_strength)
		brains.append(child)

	for _r in range(random_tail):
		brains.append(NeuralNetwork.new(SimulationConfig.DEFAULT_NETWORK_LAYERS))

	return {"brains": brains, "elite_count": elite_count}


static func _select_parent(pool: Array[NeuralNetwork]) -> NeuralNetwork:
	if pool.size() == 1:
		return pool[0]
	var a_idx: int = int(pow(randf(), 1.8) * float(pool.size()))
	var b_idx: int = int(pow(randf(), 1.8) * float(pool.size()))
	a_idx = clampi(a_idx, 0, pool.size() - 1)
	b_idx = clampi(b_idx, 0, pool.size() - 1)
	return pool[mini(a_idx, b_idx)]

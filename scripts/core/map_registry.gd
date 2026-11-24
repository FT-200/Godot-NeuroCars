class_name MapRegistry
extends RefCounted


static func get_all_maps() -> Array[Dictionary]:
	return [
		{
			"id": &"nordschleife",
			"title": "Nürburgring Nordschleife",
			"subtitle": "Классическая трасса • 1 развилка • смена на GP-петлю",
			"difficulty_stars": 1,
			"scene_path": "res://scenes/maps/map_01_nordschleife.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
		{
			"id": &"coastal_loop",
			"title": "Azure Coastal Sprint",
			"subtitle": "Скоростное побережье • внутренняя срезка • пирс-петля",
			"difficulty_stars": 2,
			"scene_path": "res://scenes/maps/map_02_coastal_loop.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
		{
			"id": &"canyon_switch",
			"title": "Redrock Canyon",
			"subtitle": "Парные шлюзы коридоров • динамические ворота • развилка",
			"difficulty_stars": 3,
			"scene_path": "res://scenes/maps/map_03_canyon_switch.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
		{
			"id": &"urban_grid",
			"title": "Metro District Circuit",
			"subtitle": "Городские кварталы • 2 аллеи-срезки • плотные переходы",
			"difficulty_stars": 4,
			"scene_path": "res://scenes/maps/map_04_urban_grid.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
		{
			"id": &"alpine_pass",
			"title": "Alpine Switchbacks",
			"subtitle": "Горный серпантин • 2 развилки • 3 варианта маршрута",
			"difficulty_stars": 5,
			"scene_path": "res://scenes/maps/map_05_alpine_pass.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
		{
			"id": &"apex_gauntlet",
			"title": "Apex Proving Grounds",
			"subtitle": "Финальный полигон • узкие шиканы • 3 маршрута и шлюзы",
			"difficulty_stars": 6,
			"scene_path": "res://scenes/maps/map_06_apex_gauntlet.tscn",
			"laps_per_route_switch": 3,
			"recommended_population": 50,
		},
	]


static func get_map_by_index(index: int) -> Dictionary:
	var maps: Array[Dictionary] = get_all_maps()
	if maps.is_empty():
		return {}
	var clamped_idx: int = clampi(index, 0, maps.size() - 1)
	return maps[clamped_idx]


static func get_map_count() -> int:
	return get_all_maps().size()

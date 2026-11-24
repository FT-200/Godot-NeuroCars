class_name TrackGeometryBuilder
extends RefCounted


static func sample_closed_spline(control_points: PackedVector2Array, subdivisions_per_segment: int = 10) -> PackedVector2Array:
	var n: int = control_points.size()
	var result: PackedVector2Array = PackedVector2Array()
	if n < 3:
		return control_points
	for i in range(n):
		var p0: Vector2 = control_points[(i - 1 + n) % n]
		var p1: Vector2 = control_points[i]
		var p2: Vector2 = control_points[(i + 1) % n]
		var p3: Vector2 = control_points[(i + 2) % n]
		for s in range(subdivisions_per_segment):
			var t: float = float(s) / float(subdivisions_per_segment)
			result.append(_catmull_rom(p0, p1, p2, p3, t))
	return result


static func sample_open_spline(control_points: PackedVector2Array, subdivisions_per_segment: int = 8) -> PackedVector2Array:
	var n: int = control_points.size()
	var result: PackedVector2Array = PackedVector2Array()
	if n < 2:
		return control_points
	for i in range(n - 1):
		var p0: Vector2 = control_points[maxi(0, i - 1)]
		var p1: Vector2 = control_points[i]
		var p2: Vector2 = control_points[i + 1]
		var p3: Vector2 = control_points[mini(n - 1, i + 2)]
		var steps: int = subdivisions_per_segment
		for s in range(steps):
			var t: float = float(s) / float(steps)
			result.append(_catmull_rom(p0, p1, p2, p3, t))
	result.append(control_points[n - 1])
	return result


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func resample_closed_polyline(points: PackedVector2Array, step_px: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var total_len: float = 0.0
	for i in range(points.size()):
		total_len += points[i].distance_to(points[(i + 1) % points.size()])
	var count: int = maxi(16, int(round(total_len / maxf(step_px, 4.0))))
	var actual_step: float = total_len / float(count)

	var out: PackedVector2Array = PackedVector2Array()
	var seg_idx: int = 0
	var seg_pos: float = 0.0
	var curr: Vector2 = points[0]
	var next_pt: Vector2 = points[1]
	var seg_len: float = curr.distance_to(next_pt)

	for _k in range(count):
		out.append(curr.lerp(next_pt, seg_pos / maxf(seg_len, 0.001)))
		var advance: float = actual_step
		while advance > 0.0:
			var remain: float = seg_len - seg_pos
			if advance <= remain or seg_idx >= points.size() * 2:
				seg_pos += advance
				advance = 0.0
			else:
				advance -= remain
				seg_idx = (seg_idx + 1) % points.size()
				seg_pos = 0.0
				curr = points[seg_idx]
				next_pt = points[(seg_idx + 1) % points.size()]
				seg_len = maxf(curr.distance_to(next_pt), 0.001)
	return out


static func extend_open_polyline(points: PackedVector2Array, extend_px: float = 22.0) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out: PackedVector2Array = points.duplicate()
	var start_dir: Vector2 = (points[0] - points[1]).normalized()
	var end_dir: Vector2 = (points[points.size() - 1] - points[points.size() - 2]).normalized()
	out[0] = points[0] + start_dir * extend_px
	out[out.size() - 1] = points[points.size() - 1] + end_dir * extend_px
	return out


static func build_track_polygons(
	main_loop: PackedVector2Array,
	branches: Array[PackedVector2Array],
	road_half_width: float
) -> Dictionary:
	var n: int = main_loop.size()
	var half_idx: int = n / 2

	var part_a: PackedVector2Array = PackedVector2Array()
	for i in range(0, half_idx + 4):
		part_a.append(main_loop[i % n])

	var part_b: PackedVector2Array = PackedVector2Array()
	for i in range(half_idx - 3, n + 4):
		part_b.append(main_loop[(i + n) % n])

	var ribbons_a: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		part_a,
		road_half_width,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_ROUND
	)
	var ribbons_b: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		part_b,
		road_half_width,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_ROUND
	)

	var all_polys: Array[PackedVector2Array] = []
	if not ribbons_a.is_empty() and not ribbons_b.is_empty():
		all_polys = Geometry2D.merge_polygons(ribbons_a[0], ribbons_b[0])

	for branch_pts in branches:
		var extended: PackedVector2Array = extend_open_polyline(branch_pts, 20.0)
		var branch_ribbons: Array[PackedVector2Array] = Geometry2D.offset_polyline(
			extended,
			road_half_width,
			Geometry2D.JOIN_ROUND,
			Geometry2D.END_ROUND
		)
		for br in branch_ribbons:
			all_polys = _merge_ribbon_into_topology(all_polys, br)

	var outer_shells: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for poly in all_polys:
		if Geometry2D.is_polygon_clockwise(poly):
			holes.append(poly)
		else:
			outer_shells.append(poly)

	return {
		"outer_shells": outer_shells,
		"holes": holes,
	}


static func _merge_ribbon_into_topology(
	current_polys: Array[PackedVector2Array],
	ribbon: PackedVector2Array
) -> Array[PackedVector2Array]:
	var outer_list: Array[PackedVector2Array] = []
	var hole_list: Array[PackedVector2Array] = []
	for p in current_polys:
		if Geometry2D.is_polygon_clockwise(p):
			hole_list.append(p)
		else:
			outer_list.append(p)

	if outer_list.is_empty():
		return [ribbon]

	var merged_outers: Array[PackedVector2Array] = Geometry2D.merge_polygons(outer_list[0], ribbon)
	var new_outer: PackedVector2Array = outer_list[0]
	var extra_holes: Array[PackedVector2Array] = []
	for mo in merged_outers:
		if Geometry2D.is_polygon_clockwise(mo):
			extra_holes.append(mo)
		else:
			new_outer = mo

	var updated_holes: Array[PackedVector2Array] = []
	for hole in hole_list:
		var ccw_hole: PackedVector2Array = _reverse_poly(hole)
		var clipped: Array[PackedVector2Array] = Geometry2D.clip_polygons(ccw_hole, ribbon)
		for cp in clipped:
			if not Geometry2D.is_polygon_clockwise(cp):
				var area: float = absf(_signed_area(cp))
				if area >= 400.0:
					updated_holes.append(_reverse_poly(cp))

	for eh in extra_holes:
		if absf(_signed_area(eh)) >= 400.0:
			updated_holes.append(eh)

	var combined: Array[PackedVector2Array] = [new_outer]
	for uh in updated_holes:
		combined.append(uh)
	return combined


static func _reverse_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(poly[i])
	return out


static func _signed_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func populate_map_visuals_and_walls(
	map_root: Node2D,
	main_loop: PackedVector2Array,
	branches: Array[PackedVector2Array],
	road_half_width: float,
	palette: Dictionary,
	spawn_pos: Vector2,
	spawn_tangent: Vector2
) -> Dictionary:
	var topo: Dictionary = build_track_polygons(main_loop, branches, road_half_width)
	var outer_shells: Array[PackedVector2Array] = topo["outer_shells"]
	var holes: Array[PackedVector2Array] = topo["holes"]
	if outer_shells.is_empty():
		return topo

	var outer_poly: PackedVector2Array = outer_shells[0]
	var min_pt: Vector2 = Vector2(1e9, 1e9)
	var max_pt: Vector2 = Vector2(-1e9, -1e9)
	for p in outer_poly:
		min_pt.x = minf(min_pt.x, p.x)
		min_pt.y = minf(min_pt.y, p.y)
		max_pt.x = maxf(max_pt.x, p.x)
		max_pt.y = maxf(max_pt.y, p.y)

	var bg_pad: Vector2 = Vector2(750.0, 650.0)
	var bg_min: Vector2 = min_pt - bg_pad
	var bg_max: Vector2 = max_pt + bg_pad

	var turf_base_col: Color = palette.get("turf_base", Color(0.075, 0.145, 0.102, 1.0))
	var turf_stripe_col: Color = palette.get("turf_stripe", Color(0.092, 0.175, 0.122, 1.0))
	var apron_col: Color = palette.get("apron", Color(0.078, 0.09, 0.118, 1.0))
	var asphalt_col: Color = palette.get("asphalt", Color(0.157, 0.173, 0.212, 1.0))
	var edge_col: Color = palette.get("edge", Color(0.894, 0.918, 0.957, 0.9))
	var kerb_a_col: Color = palette.get("kerb_a", Color(0.855, 0.188, 0.22, 1.0))
	var kerb_b_col: Color = palette.get("kerb_b", Color(0.941, 0.957, 0.98, 1.0))

	var bg_node: Node2D = Node2D.new()
	bg_node.name = "Background"
	bg_node.z_index = -10
	map_root.add_child(bg_node)

	var turf_base: Polygon2D = Polygon2D.new()
	turf_base.name = "TurfBase"
	turf_base.color = turf_base_col
	turf_base.polygon = PackedVector2Array([
		bg_min,
		Vector2(bg_max.x, bg_min.y),
		bg_max,
		Vector2(bg_min.x, bg_max.y),
	])
	bg_node.add_child(turf_base)

	var stripes_node: Node2D = Node2D.new()
	stripes_node.name = "MowStripes"
	bg_node.add_child(stripes_node)
	var stripe_x: float = bg_min.x - 1600.0
	var stripe_idx: int = 0
	while stripe_x < bg_max.x + 1600.0:
		var st: Polygon2D = Polygon2D.new()
		st.name = "Stripe_%02d" % stripe_idx
		st.color = turf_stripe_col
		st.polygon = PackedVector2Array([
			Vector2(stripe_x, bg_min.y),
			Vector2(stripe_x + 70.0, bg_min.y),
			Vector2(stripe_x - 1200.0 + 70.0, bg_max.y),
			Vector2(stripe_x - 1200.0, bg_max.y),
		])
		stripes_node.add_child(st)
		stripe_x += 140.0
		stripe_idx += 1

	var visuals: Node2D = Node2D.new()
	visuals.name = "TrackVisuals"
	visuals.z_index = -5
	map_root.add_child(visuals)

	var apron_offsets: Array[PackedVector2Array] = Geometry2D.offset_polygon(outer_poly, 9.0, Geometry2D.JOIN_ROUND)
	for idx in range(apron_offsets.size()):
		var ap: Polygon2D = Polygon2D.new()
		ap.name = "OuterApron_%d" % idx
		ap.color = apron_col
		ap.polygon = apron_offsets[idx]
		visuals.add_child(ap)

	var road_poly: Polygon2D = Polygon2D.new()
	road_poly.name = "RoadAsphalt"
	road_poly.color = asphalt_col
	road_poly.polygon = outer_poly
	visuals.add_child(road_poly)

	var outer_line: Line2D = Line2D.new()
	outer_line.name = "OuterEdgeLine"
	outer_line.points = outer_poly
	outer_line.closed = true
	outer_line.width = 2.6
	outer_line.default_color = edge_col
	outer_line.joint_mode = Line2D.LINE_JOINT_ROUND
	visuals.add_child(outer_line)

	var scenery: Node2D = Node2D.new()
	scenery.name = "Scenery"
	scenery.z_index = -2
	map_root.add_child(scenery)

	var trees_node: Node2D = Node2D.new()
	trees_node.name = "Trees"
	scenery.add_child(trees_node)

	var tree_counter: int = 0
	for h_idx in range(holes.size()):
		var hole_cw: PackedVector2Array = holes[h_idx]
		var hole_ccw: PackedVector2Array = _reverse_poly(hole_cw)

		var inner_aprons: Array[PackedVector2Array] = Geometry2D.offset_polygon(hole_ccw, 8.0, Geometry2D.JOIN_ROUND)
		for ia_idx in range(inner_aprons.size()):
			var iap: Polygon2D = Polygon2D.new()
			iap.name = "IslandApron_%d_%d" % [h_idx, ia_idx]
			iap.color = apron_col
			iap.polygon = inner_aprons[ia_idx]
			visuals.add_child(iap)

		var island_turf: Polygon2D = Polygon2D.new()
		island_turf.name = "IslandTurf_%d" % h_idx
		island_turf.color = turf_base_col
		island_turf.polygon = hole_ccw
		visuals.add_child(island_turf)

		var inner_line: Line2D = Line2D.new()
		inner_line.name = "InnerEdgeLine_%d" % h_idx
		inner_line.points = hole_ccw
		inner_line.closed = true
		inner_line.width = 2.6
		inner_line.default_color = edge_col
		inner_line.joint_mode = Line2D.LINE_JOINT_ROUND
		visuals.add_child(inner_line)

		var safe_tree_zones: Array[PackedVector2Array] = Geometry2D.offset_polygon(hole_ccw, -46.0, Geometry2D.JOIN_ROUND)
		for sz in safe_tree_zones:
			if absf(_signed_area(sz)) > 2400.0:
				var stride: int = maxi(1, sz.size() / 5)
				for pt_i in range(0, sz.size(), stride):
					var tree_pos: Vector2 = sz[pt_i]
					if tree_counter < 28:
						_add_stylized_tree(trees_node, "Tree_%02d" % tree_counter, tree_pos, 22.0 + float((tree_counter * 7) % 14), palette)
						tree_counter += 1

	var dashes_node: Node2D = Node2D.new()
	dashes_node.name = "CenterDashes"
	visuals.add_child(dashes_node)
	_build_dashes_for_polyline(dashes_node, main_loop, true, "MainDash")
	for b_idx in range(branches.size()):
		_build_dashes_for_polyline(dashes_node, branches[b_idx], false, "BranchDash_%d" % b_idx)

	var kerbs_node: Node2D = Node2D.new()
	kerbs_node.name = "RacingKerbs"
	visuals.add_child(kerbs_node)
	_build_corner_kerbs(kerbs_node, main_loop, road_half_width, kerb_a_col, kerb_b_col)

	_build_start_finish_line(visuals, spawn_pos, spawn_tangent, road_half_width)

	var walls: StaticBody2D = StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = SimulationConfig.LAYER_WALLS
	walls.collision_mask = 0
	map_root.add_child(walls)

	_add_wall_ring(walls, outer_poly, false, "OuterWall")
	for h_idx in range(holes.size()):
		var hole_ccw: PackedVector2Array = _reverse_poly(holes[h_idx])
		_add_wall_ring(walls, hole_ccw, true, "InnerWall_%d" % h_idx)

	return topo


static func _build_dashes_for_polyline(parent: Node2D, pts: PackedVector2Array, is_closed: bool, prefix: String) -> void:
	var n: int = pts.size()
	var step: int = 2
	var limit: int = n if is_closed else n - 1
	for i in range(0, limit, step):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		if a.distance_to(b) < 2.0:
			continue
		var dash: Line2D = Line2D.new()
		dash.name = "%s_%03d" % [prefix, i]
		dash.points = PackedVector2Array([a, a.lerp(b, 0.72)])
		dash.width = 2.4
		dash.default_color = Color(1.0, 1.0, 1.0, 0.14)
		parent.add_child(dash)


static func _build_corner_kerbs(parent: Node2D, loop_pts: PackedVector2Array, road_half_width: float, col_a: Color, col_b: Color) -> void:
	var n: int = loop_pts.size()
	var kerb_idx: int = 0
	for i in range(0, n, 2):
		var prev_p: Vector2 = loop_pts[(i - 2 + n) % n]
		var curr_p: Vector2 = loop_pts[i]
		var next_p: Vector2 = loop_pts[(i + 2) % n]
		var d1: Vector2 = (curr_p - prev_p).normalized()
		var d2: Vector2 = (next_p - curr_p).normalized()
		var turn_angle: float = d1.angle_to(d2)
		if absf(turn_angle) < 0.14:
			continue
		var side: float = -1.0 if turn_angle > 0.0 else 1.0
		var tangent: Vector2 = (next_p - curr_p).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x) * side
		var p_a: Vector2 = curr_p + normal * (road_half_width - 5.0)
		var p_b: Vector2 = curr_p + tangent * 15.0 + normal * (road_half_width - 5.0)
		var p_c: Vector2 = curr_p + tangent * 15.0 + normal * (road_half_width + 2.5)
		var p_d: Vector2 = curr_p + normal * (road_half_width + 2.5)
		var kerb: Polygon2D = Polygon2D.new()
		kerb.name = "Kerb_%03d" % kerb_idx
		kerb.color = col_a if (kerb_idx % 2 == 0) else col_b
		kerb.polygon = PackedVector2Array([p_a, p_b, p_c, p_d])
		parent.add_child(kerb)
		kerb_idx += 1


static func _build_start_finish_line(parent: Node2D, spawn_pos: Vector2, tangent: Vector2, road_half_width: float) -> void:
	var sf_node: Node2D = Node2D.new()
	sf_node.name = "StartFinishLine"
	parent.add_child(sf_node)
	var t: Vector2 = tangent.normalized()
	var n: Vector2 = Vector2(-t.y, t.x)
	var rows: int = 8
	var tile_w: float = (road_half_width * 1.8) / float(rows)
	var start_n: float = -road_half_width * 0.9
	for col in range(2):
		for row in range(rows):
			var d0: float = start_n + float(row) * tile_w
			var d1: float = d0 + tile_w
			var x0: float = 28.0 + float(col) * 8.0
			var x1: float = x0 + 8.0
			var check: Polygon2D = Polygon2D.new()
			check.name = "Check_%d_%d" % [col, row]
			check.color = Color(0.96, 0.97, 0.99, 1.0) if ((col + row) % 2 == 0) else Color(0.08, 0.09, 0.11, 1.0)
			check.polygon = PackedVector2Array([
				spawn_pos + t * x0 + n * d0,
				spawn_pos + t * x1 + n * d0,
				spawn_pos + t * x1 + n * d1,
				spawn_pos + t * x0 + n * d1,
			])
			sf_node.add_child(check)


static func _add_wall_ring(walls_body: StaticBody2D, ccw_ring: PackedVector2Array, extrude_inward: bool, prefix: String) -> void:
	var n: int = ccw_ring.size()
	var thickness: float = 18.0
	var sign_dir: float = -1.0 if extrude_inward else 1.0
	var chunk_size: int = 8
	var idx: int = 0
	var seg_i: int = 0
	while idx < n:
		var end_idx: int = mini(idx + chunk_size, n)
		for k in range(idx, end_idx):
			var a: Vector2 = ccw_ring[k]
			var b: Vector2 = ccw_ring[(k + 1) % n]
			var edge: Vector2 = b - a
			if edge.length_squared() < 0.25:
				continue
			var out_normal: Vector2 = Vector2(-edge.y, edge.x).normalized() * sign_dir
			var coll: CollisionPolygon2D = CollisionPolygon2D.new()
			coll.name = "%s_%03d" % [prefix, seg_i]
			coll.polygon = PackedVector2Array([
				a,
				b,
				b + out_normal * thickness,
				a + out_normal * thickness,
			])
			walls_body.add_child(coll)
			seg_i += 1
		idx = end_idx


static func _add_stylized_tree(parent: Node2D, node_name: String, pos: Vector2, radius: float, palette: Dictionary) -> void:
	var tree: Node2D = Node2D.new()
	tree.name = node_name
	tree.position = pos
	parent.add_child(tree)

	var dark_col: Color = palette.get("tree_dark", Color(0.095, 0.245, 0.145, 1.0))
	var mid_col: Color = palette.get("tree_mid", Color(0.145, 0.345, 0.195, 1.0))
	var light_col: Color = palette.get("tree_light", Color(0.205, 0.45, 0.255, 1.0))

	var shadow: Polygon2D = Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(0.04, 0.08, 0.055, 0.6)
	shadow.polygon = _circle_poly(Vector2(5.0, 6.0), radius * 1.05, 10)
	tree.add_child(shadow)

	var canopy_dark: Polygon2D = Polygon2D.new()
	canopy_dark.name = "CanopyDark"
	canopy_dark.color = dark_col
	canopy_dark.polygon = _circle_poly(Vector2.ZERO, radius, 10)
	tree.add_child(canopy_dark)

	var canopy_mid: Polygon2D = Polygon2D.new()
	canopy_mid.name = "CanopyMid"
	canopy_mid.color = mid_col
	canopy_mid.polygon = _circle_poly(Vector2(-radius * 0.14, -radius * 0.12), radius * 0.7, 9)
	tree.add_child(canopy_mid)

	var canopy_light: Polygon2D = Polygon2D.new()
	canopy_light.name = "CanopyLight"
	canopy_light.color = light_col
	canopy_light.polygon = _circle_poly(Vector2(-radius * 0.22, -radius * 0.22), radius * 0.36, 8)
	tree.add_child(canopy_light)


static func _circle_poly(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts

extends Node2D

const WATER := Color("#091f3c")
const GRID := Color("#14354f")
const GRID_VERTICAL := Color("#112e49")
const CYAN := Color("#40e6ff")
const GOLD := Color("#ffbf56")
const GREEN := Color("#74f49d")
const WHITE := Color("#e5f6ff")
const RED := Color("bd0c66ff")
const FLOOR_FILL := Color("#14323c")

var _probe_animation: Dictionary = {}


func _ready() -> void:
	set_process(false)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func start_probe_animation(result: Dictionary) -> void:
	_probe_animation = {
		"x": float(result.get("x", 0.0)),
		"y": float(GameConstants.SEA_Y),
		"target": float(result.get("y", GameConstants.SEA_Y)),
		"age": 0.0,
	}
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _probe_animation.is_empty():
		set_process(false)
		return

	_probe_animation["age"] = float(_probe_animation["age"]) + maxf(delta, 0.0)
	_probe_animation["y"] = minf(
		float(_probe_animation["target"]),
		float(_probe_animation["y"]) + maxf(delta/2, 0.0) * 680.0
	)
	if float(_probe_animation["age"]) > GameConstants.PROBE_COOLDOWN_SECONDS:
		_probe_animation.clear()
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var extended_left := GameConstants.WORLD_LEFT - GameConstants.VIEWPORT_WIDTH
	var extended_right := GameConstants.WORLD_RIGHT + GameConstants.VIEWPORT_WIDTH
	draw_rect(
		Rect2(
			extended_left,
			181,
			extended_right - extended_left,
			489
		),
		WATER
	)

	for y in range(295, 653, 65):
		draw_line(Vector2(extended_left, y), Vector2(extended_right, y), GRID, 1.0)
	for x in range(GameConstants.WORLD_LEFT + 80, GameConstants.WORLD_RIGHT, 88):
		draw_line(Vector2(x, 275), Vector2(x, 654), GRID_VERTICAL, 1.0)
	draw_line(
		Vector2(extended_left, GameConstants.SEA_Y),
		Vector2(extended_right, GameConstants.SEA_Y),
		CYAN,
		3.0,
		true
	)

	if not ClientSession.released_terrain.is_empty():
		_draw_released_terrain()
	else:
		_draw_measurements()

	if not _probe_animation.is_empty():
		var probe_x := float(_probe_animation["x"])
		var probe_y := float(_probe_animation["y"])
		draw_line(Vector2(probe_x, GameConstants.SEA_Y), Vector2(probe_x, probe_y), CYAN, 2.0)
		draw_circle(Vector2(probe_x, probe_y), 6.0, CYAN)


func _draw_released_terrain() -> void:
	var points := _to_points(ClientSession.released_terrain)
	if points.size() < 2:
		return

	var floor_polygon := PackedVector2Array(points)
	floor_polygon.append(Vector2(points[-1].x, 668))
	floor_polygon.append(Vector2(points[0].x, 668))
	draw_colored_polygon(floor_polygon, FLOOR_FILL)
	draw_polyline(points, GREEN, 3.0, true)

	if ClientSession.released_treasure_x == null:
		return
	var treasure_x := float(ClientSession.released_treasure_x)
	var treasure_y := _profile_depth(points, treasure_x)
	draw_circle(Vector2(treasure_x, treasure_y - 11.0), 11.0, GOLD)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(treasure_x - 12.0, treasure_y - 25.0),
		"★",
		HORIZONTAL_ALIGNMENT_CENTER,
		24.0,
		23,
		GOLD
	)


func _draw_measurements() -> void:
	for measurement: Dictionary in ClientSession.measurements:
		var measurement_color := RED #_measurement_color(int(measurement.get("player_id", 0)))
		var patch := _to_points(measurement.get("patch", []))
		if patch.size() >= 2:
			draw_polyline(patch, measurement_color, 3.0, true)
		draw_circle(
			Vector2(float(measurement.get("x", 0.0)), float(measurement.get("y", 0.0))),
			4.0,
			measurement_color
		)
		_draw_tangent(measurement, 2.0, measurement_color)

	if ClientSession.last_measurement.is_empty():
		return
	_draw_tangent(ClientSession.last_measurement, 3.0, GOLD)
	draw_circle(
		Vector2(
			float(ClientSession.last_measurement.get("x", 0.0)),
			float(ClientSession.last_measurement.get("y", 0.0))
		),
		5.0,
		GOLD
	)


func _draw_tangent(measurement: Dictionary, width: float, color: Color = RED) -> void:
	var center_x := float(measurement.get("x", 0.0))
	var center_y := float(measurement.get("y", 0.0))
	var slope := float(measurement.get("slope", 0.0))
	var half_span := GameConstants.MEASUREMENT_TANGENT_LENGTH / 2.0
	draw_line(
		Vector2(center_x - half_span, center_y - half_span * slope),
		Vector2(center_x + half_span, center_y + half_span * slope),
		color,
		width,
		true
	)


func _to_points(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if typeof(source) != TYPE_ARRAY:
		return result

	for item: Variant in source:
		if typeof(item) == TYPE_VECTOR2:
			result.append(item)
		elif typeof(item) == TYPE_ARRAY and item.size() >= 2:
			result.append(Vector2(float(item[0]), float(item[1])))
	return result


func _profile_depth(points: PackedVector2Array, world_x: float) -> float:
	var closest := points[0]
	for point: Vector2 in points:
		if absf(point.x - world_x) < absf(closest.x - world_x):
			closest = point
	return closest.y


func _measurement_color(player_id: int) -> Color:
	for player: Dictionary in ClientSession.public_state.get("players", []):
		if int(player.get("id", 0)) == player_id:
			return Color.from_string(str(player.get("color", "#74f49d")), GREEN)
	return WHITE

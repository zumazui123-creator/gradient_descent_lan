extends Node2D

var _display_name := "Spieler"
var _ship_color := Color.WHITE
var _is_local := false
var _target_x := 0.0
var _initialized := false


func set_state(world_x: float, display_name: String, ship_color: Color, is_local: bool) -> void:
	_target_x = world_x
	_display_name = display_name
	_ship_color = ship_color
	_is_local = is_local
	if not _initialized:
		position.x = world_x
		_initialized = true
	queue_redraw()


func _process(delta: float) -> void:
	position.x = lerpf(position.x, _target_x, minf(1.0, maxf(delta, 0.0) * 12.0))


func _draw() -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-29, -13),
			Vector2(30, -13),
			Vector2(19, 3),
			Vector2(-19, 3),
		]),
		_ship_color
	)
	draw_line(Vector2(-6, -13), Vector2(-6, -40), Color("#e5f6ff"), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-5, -39),
			Vector2(14, -28),
			Vector2(-5, -28),
		]),
		Color("#e5f6ff")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-70, -49),
		_display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		140.0,
		13,
		_ship_color
	)
	if _is_local:
		draw_circle(Vector2(0, 12), 3.0, _ship_color)

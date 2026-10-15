extends Control

const VIEW_WIDTH := 1128 - 72

var _snapshot: Dictionary = {}
var _camera_x := 0.0


func set_state(snapshot: Dictionary, camera_x: float) -> void:
	_snapshot = snapshot
	_camera_x = camera_x
	queue_redraw()


func _draw() -> void:
	var world_width := float(GameConstants.WORLD_RIGHT - GameConstants.WORLD_LEFT)
	var bar_width := size.x
	draw_line(Vector2(0, size.y / 2.0), Vector2(bar_width, size.y / 2.0), Color("#2c4c71"), 2.0)

	var viewport_left := _camera_x / world_width * bar_width
	var viewport_width := VIEW_WIDTH / world_width * bar_width
	draw_rect(
		Rect2(viewport_left, 0, viewport_width, size.y),
		Color("#40e6ff"),
		false,
		1.0
	)

	for player: Dictionary in _snapshot.get("players", []):
		var normalized_x := (
			float(player.get("x", GameConstants.WORLD_LEFT)) - GameConstants.WORLD_LEFT
		) / world_width
		var marker_x := normalized_x * bar_width
		var is_local := int(player.get("id", 0)) == ClientSession.local_player_id
		draw_circle(
			Vector2(marker_x, size.y / 2.0),
			5.0 if is_local else 3.0,
			Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		)

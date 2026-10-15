extends Node2D

signal leave_requested

const SHIP_VIEW_SCENE := preload("res://scenes/components/ShipView.tscn")
const MAX_CAMERA := (
	GameConstants.WORLD_RIGHT
	- GameConstants.WORLD_LEFT
	- (1128 - 72)
)

@onready var seabed_renderer = $World/SeabedRenderer
@onready var ships_container: Node2D = $World/Ships
@onready var game_camera: Camera2D = $World/Camera2D
@onready var round_label: Label = $HUD/Root/RoundLabel
@onready var player_strip: HBoxContainer = $HUD/Root/PlayerStrip
@onready var overview_bar = $HUD/Root/OverviewBar
@onready var measurement_label: Label = $HUD/Root/MeasurementPanel/Content/MeasurementLabel
@onready var controls_label: Label = $HUD/Root/MeasurementPanel/Content/ControlsLabel
@onready var finished_panel: PanelContainer = $HUD/Root/FinishedPanel
@onready var finished_label: Label = $HUD/Root/FinishedPanel/Margin/Content/ResultLabel
@onready var restart_button: Button = $HUD/Root/FinishedPanel/Margin/Content/RestartButton
@onready var waiting_label: Label = $HUD/Root/FinishedPanel/Margin/Content/WaitingLabel
@onready var help_dialog: Control = $HUD/Root/HelpDialog

var _ship_views: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _last_axis := 0
var _camera_x := 0.0


func _ready() -> void:
	NetworkManager.state_received.connect(_on_state_received)
	NetworkManager.private_probe_received.connect(_on_private_probe_received)
	NetworkManager.round_finished.connect(_on_round_finished)
	_last_snapshot = ClientSession.public_state.duplicate(true)
	_refresh_from_snapshot(_last_snapshot)
	seabed_renderer.refresh()
	_center_released_treasure()


func _exit_tree() -> void:
	if _last_axis != 0 and NetworkManager.peer != null:
		NetworkManager.submit_axis(0)


func _process(delta: float) -> void:
	var phase := str(_last_snapshot.get("phase", ""))
	if phase == GameManager.PHASE_PLAYING:
		var axis := 0 if help_dialog.visible else _movement_axis()
		if axis != _last_axis:
			NetworkManager.submit_axis(axis)
			_last_axis = axis

		var own_player := _local_player(_last_snapshot)
		if not own_player.is_empty():
			var target := clampf(
				float(own_player.get("x", GameConstants.WORLD_LEFT))
				- GameConstants.VIEWPORT_WIDTH / 2.0,
				0.0,
				MAX_CAMERA
			)
			_camera_x = lerpf(_camera_x, target, minf(1.0, maxf(delta, 0.0) * 10.0))
	elif phase == GameManager.PHASE_FINISHED:
		_last_axis = 0
		if not help_dialog.visible:
			_camera_x = clampf(
				_camera_x + _movement_axis() * 700.0 * maxf(delta, 0.0),
				0.0,
				MAX_CAMERA
			)
	else:
		_last_axis = 0

	game_camera.position = Vector2(GameConstants.VIEWPORT_WIDTH / 2.0 + _camera_x, 380.0)
	overview_bar.set_state(_last_snapshot, _camera_x)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_H:
		if help_dialog.visible:
			help_dialog.close()
		else:
			help_dialog.open()
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_ESCAPE:
		if help_dialog.visible:
			help_dialog.close()
		else:
			leave_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if help_dialog.visible:
		return

	var phase := str(_last_snapshot.get("phase", ""))
	var can_restart := NetworkManager.is_host and not restart_button.disabled
	if phase == GameManager.PHASE_PLAYING and event.keycode in [KEY_SPACE, KEY_DOWN, KEY_S]:
		NetworkManager.request_probe()
		get_viewport().set_input_as_handled()
	elif phase == GameManager.PHASE_FINISHED and event.keycode == KEY_R and can_restart:
		NetworkManager.request_restart_round()
		get_viewport().set_input_as_handled()


func _movement_axis() -> int:
	var move_right := Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
	var move_left := Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
	return int(move_right) - int(move_left)


func _on_state_received(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)
	_refresh_from_snapshot(_last_snapshot)


func _on_private_probe_received(result: Dictionary) -> void:
	seabed_renderer.start_probe_animation(result)
	_update_measurement()


func _on_round_finished(
	_winner_id: Variant,
	_terrain: Array,
	_treasure_x: int
) -> void:
	seabed_renderer.refresh()
	_center_released_treasure()
	_refresh_from_snapshot(ClientSession.public_state)


func _refresh_from_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	round_label.text = "Runde %d  ·  UDP %d" % [
		int(snapshot.get("round", 0)),
		NetworkManager.port,
	]
	_sync_ships(snapshot)
	_sync_player_strip(snapshot)
	overview_bar.set_state(snapshot, _camera_x)
	_update_measurement()
	_update_finished_panel(snapshot)
	seabed_renderer.refresh()


func _sync_ships(snapshot: Dictionary) -> void:
	var active_ids: Dictionary = {}
	for player: Dictionary in snapshot.get("players", []):
		var player_id := int(player.get("id", 0))
		active_ids[player_id] = true
		var ship = _ship_views.get(player_id)
		if ship == null:
			ship = SHIP_VIEW_SCENE.instantiate()
			ship.position.y = GameConstants.SEA_Y
			ships_container.add_child(ship)
			_ship_views[player_id] = ship
		ship.set_state(
			float(player.get("x", GameConstants.WORLD_LEFT)),
			str(player.get("name", "Spieler")),
			Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE),
			player_id == ClientSession.local_player_id
		)

	for player_id: Variant in _ship_views.keys():
		if not active_ids.has(player_id):
			var ship = _ship_views[player_id]
			_ship_views.erase(player_id)
			ship.queue_free()


func _sync_player_strip(snapshot: Dictionary) -> void:
	for child in player_strip.get_children():
		player_strip.remove_child(child)
		child.queue_free()

	for player: Dictionary in snapshot.get("players", []):
		var label := Label.new()
		label.text = "● %s  %d/%d" % [
			str(player.get("name", "Spieler")).substr(0, 14),
			int(player.get("probes_left", 0)),
			GameConstants.PROBES_PER_PLAYER,
		]
		label.add_theme_color_override(
			"font_color",
			Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		)
		label.add_theme_font_size_override("font_size", 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_strip.add_child(label)


func _update_measurement() -> void:
	if ClientSession.last_measurement.is_empty():
		measurement_label.text = "Noch keine Messung: Der Boden ist verborgen."
	else:
		var measurement := ClientSession.last_measurement
		var slope := float(measurement.get("slope", 0.0))
		var hint := "fast eben"
		if slope > 0.075:
			hint = "tiefer rechts →"
		elif slope < -0.075:
			hint = "← tiefer links"
		measurement_label.text = "Tiefe: %d   ·   Gefälle: %+.2f   ·   %s" % [
			roundi(float(measurement.get("y", GameConstants.SEA_Y)) - GameConstants.SEA_Y),
			slope,
			hint,
		]

	var phase := str(_last_snapshot.get("phase", ""))
	controls_label.text = (
		"← → / A D Karte ansehen   ·   H Hilfe"
		if phase == GameManager.PHASE_FINISHED
		else "← → / A D bewegen   ·   Leertaste / ↓ / S Sonde   ·   H Hilfe"
	)


func _update_finished_panel(snapshot: Dictionary) -> void:
	var phase := str(snapshot.get("phase", ""))
	finished_panel.visible = phase == GameManager.PHASE_FINISHED
	if not finished_panel.visible:
		return

	var winner_id: Variant = snapshot.get("winner")
	var winner_name := ""
	for player: Dictionary in snapshot.get("players", []):
		if player.get("id") == winner_id:
			winner_name = str(player.get("name", "Spieler"))
			break
	finished_label.text = (
		"%s hat den Schatz gefunden!" % winner_name
		if not winner_name.is_empty()
		else "Alle Sonden wurden verbraucht!"
	)

	var players: Array = snapshot.get("players", [])
	var player_count := players.size()
	restart_button.visible = NetworkManager.is_host
	restart_button.disabled = player_count < GameConstants.MIN_PLAYERS
	waiting_label.visible = not NetworkManager.is_host


func _local_player(snapshot: Dictionary) -> Dictionary:
	for player: Dictionary in snapshot.get("players", []):
		if int(player.get("id", 0)) == ClientSession.local_player_id:
			return player
	return {}


func _center_released_treasure() -> void:
	if ClientSession.released_treasure_x == null:
		return
	_camera_x = clampf(
		float(ClientSession.released_treasure_x) - GameConstants.VIEWPORT_WIDTH / 2.0,
		0.0,
		MAX_CAMERA
	)


func _on_help_button_pressed() -> void:
	help_dialog.open()


func _on_restart_button_pressed() -> void:
	NetworkManager.request_restart_round()


func _on_leave_button_pressed() -> void:
	leave_requested.emit()

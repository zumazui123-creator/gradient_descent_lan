extends Node

const MAIN_MENU_SCENE := preload("res://scenes/MainMenu.tscn")
const LOBBY_SCENE := preload("res://scenes/Lobby.tscn")
const GAME_VIEW_SCENE := preload("res://scenes/GameView.tscn")

@onready var scene_container: Node = $SceneContainer
@onready var notice_label: Label = $OverlayLayer/NoticeLabel

var _current_scene_kind := ""
var _notice_generation := 0


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.state_received.connect(_on_state_received)
	NetworkManager.round_started.connect(_on_round_started)
	NetworkManager.round_finished.connect(_on_round_finished)
	NetworkManager.notice_received.connect(_show_notice)
	_show_scene(MAIN_MENU_SCENE, "menu")


func _on_connection_succeeded(_is_host: bool) -> void:
	var phase := str(ClientSession.public_state.get("phase", GameManager.PHASE_LOBBY))
	if phase == GameManager.PHASE_LOBBY:
		_show_scene(LOBBY_SCENE, "lobby")
	else:
		_show_scene(GAME_VIEW_SCENE, "game")


func _on_connection_failed(message: String) -> void:
	_show_scene(MAIN_MENU_SCENE, "menu")
	_show_notice(message, 7.0)


func _on_server_disconnected() -> void:
	_show_scene(MAIN_MENU_SCENE, "menu")
	_show_notice("Verbindung zum Host verloren.", 7.0)


func _on_state_received(snapshot: Dictionary) -> void:
	if ClientSession.local_player_id == 0:
		return

	var phase := str(snapshot.get("phase", ""))
	var is_game_phase := phase in [GameManager.PHASE_PLAYING, GameManager.PHASE_FINISHED]
	if phase == GameManager.PHASE_LOBBY and _current_scene_kind != "lobby":
		_show_scene(LOBBY_SCENE, "lobby")
	elif is_game_phase and _current_scene_kind != "game":
		_show_scene(GAME_VIEW_SCENE, "game")


func _on_round_started(_round_number: int) -> void:
	if _current_scene_kind != "game":
		_show_scene(GAME_VIEW_SCENE, "game")


func _on_round_finished(
	_winner_id: Variant,
	_terrain: Array,
	_treasure_x: int
) -> void:
	if _current_scene_kind != "game":
		_show_scene(GAME_VIEW_SCENE, "game")


func _on_leave_requested() -> void:
	NetworkManager.disconnect_network()
	_show_scene(MAIN_MENU_SCENE, "menu")


func _show_scene(scene: PackedScene, kind: String) -> void:
	if _current_scene_kind == kind and scene_container.get_child_count() > 0:
		return

	for child in scene_container.get_children():
		scene_container.remove_child(child)
		child.queue_free()

	var next_scene := scene.instantiate()
	scene_container.add_child(next_scene)
	_current_scene_kind = kind
	if next_scene.has_signal("leave_requested"):
		next_scene.connect("leave_requested", _on_leave_requested)


func _show_notice(message: String, seconds: float = 5.0) -> void:
	_notice_generation += 1
	var generation := _notice_generation
	notice_label.text = message.substr(0, 160)
	notice_label.visible = true
	await get_tree().create_timer(seconds).timeout
	if generation == _notice_generation:
		notice_label.visible = false

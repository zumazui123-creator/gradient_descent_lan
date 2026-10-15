extends Control

signal leave_requested

@onready var status_label: Label = $Center/Panel/Margin/Content/StatusLabel
@onready var player_list: VBoxContainer = $Center/Panel/Margin/Content/Body/PlayerSection/PlayerList
@onready var start_button: Button = $Center/Panel/Margin/Content/Actions/StartButton


func _ready() -> void:
	NetworkManager.state_received.connect(_on_state_received)
	_refresh(ClientSession.public_state)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var can_start := NetworkManager.is_host and not start_button.disabled
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and can_start:
		NetworkManager.request_start_round()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		leave_requested.emit()
		get_viewport().set_input_as_handled()


func _on_state_received(snapshot: Dictionary) -> void:
	_refresh(snapshot)


func _refresh(snapshot: Dictionary) -> void:
	if NetworkManager.is_host:
		status_label.text = "Mitspieler verbinden sich mit %s:%d" % [
			NetworkManager.local_ip(),
			NetworkManager.port,
		]
	else:
		status_label.text = "Warte, bis der Host die Runde startet."

	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	var players: Array = snapshot.get("players", [])
	for player: Dictionary in players:
		var label := Label.new()
		var suffix := "  (Host)" if int(player.get("id", 0)) == NetworkManager.SERVER_PEER_ID else ""
		label.text = "●  %s%s" % [str(player.get("name", "Spieler")), suffix]
		label.add_theme_color_override(
			"font_color",
			Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		)
		label.add_theme_font_size_override("font_size", 20)
		player_list.add_child(label)

	start_button.visible = NetworkManager.is_host
	start_button.disabled = players.size() < GameConstants.MIN_PLAYERS


func _on_start_button_pressed() -> void:
	NetworkManager.request_start_round()


func _on_leave_button_pressed() -> void:
	leave_requested.emit()

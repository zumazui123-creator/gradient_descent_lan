extends Control

signal leave_requested

@onready var status_label: Label = $Center/Panel/Margin/Content/StatusLabel
@onready var player_list: VBoxContainer = $Center/Panel/Margin/Content/Body/PlayerSection/PlayerList
@onready var measurement_toggle: CheckButton = $Center/Panel/Margin/Content/Body/Rules/AllMeasurementsToggle
@onready var team_mode_toggle: CheckButton = $Center/Panel/Margin/Content/Body/Rules/TeamModeToggle
@onready var measurement_rule: Label = $Center/Panel/Margin/Content/Body/Rules/Rule2
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
	var show_all := bool(snapshot.get("show_all_measurements", false))
	var team_mode := bool(snapshot.get("team_mode", false))
	if NetworkManager.is_host:
		status_label.text = "Mitspieler verbinden sich mit %s:%d" % [
			NetworkManager.local_ip(),
			NetworkManager.port,
		]
		if team_mode and not GameManager.can_start_round():
			status_label.text += "  ·  Bitte mindestens zwei Teams belegen."
	else:
		status_label.text = "Warte, bis der Host die Runde startet."

	measurement_toggle.set_pressed_no_signal(show_all)
	measurement_toggle.disabled = not NetworkManager.is_host
	measurement_toggle.text = (
		"Alle Messungen sichtbar: AN"
		if show_all
		else "Alle Messungen sichtbar: AUS"
	)
	team_mode_toggle.set_pressed_no_signal(team_mode)
	team_mode_toggle.disabled = not NetworkManager.is_host
	team_mode_toggle.text = "Teamspiel: AN" if team_mode else "Teamspiel: AUS"
	measurement_rule.text = (
		"40 Sonden, je 3 s vor Anker – alle Messpunkte sind sichtbar."
		if show_all
		else "40 Sonden, je 3 s vor Anker – nur eigene Messpunkte sind sichtbar."
	)

	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	var players: Array = snapshot.get("players", [])
	for player: Dictionary in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		player_list.add_child(row)

		var label := Label.new()
		var suffix := "  (Host)" if int(player.get("id", 0)) == NetworkManager.SERVER_PEER_ID else ""
		label.text = "●  %s%s" % [str(player.get("name", "Spieler")), suffix]
		label.add_theme_color_override(
			"font_color",
			Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		)
		label.add_theme_font_size_override("font_size", 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		if team_mode:
			var team_picker := OptionButton.new()
			team_picker.custom_minimum_size = Vector2(132, 38)
			for team_id in range(1, GameConstants.MAX_TEAMS + 1):
				team_picker.add_item("Team %d" % team_id, team_id)
			var selected_team := clampi(
				int(player.get("team_id", 1)),
				1,
				GameConstants.MAX_TEAMS
			)
			team_picker.select(selected_team - 1)
			team_picker.disabled = not NetworkManager.is_host
			team_picker.item_selected.connect(
				_on_team_selected.bind(int(player.get("id", 0)), team_picker)
			)
			row.add_child(team_picker)

	start_button.visible = NetworkManager.is_host
	start_button.disabled = not GameManager.can_start_round()


func _on_start_button_pressed() -> void:
	NetworkManager.request_start_round()


func _on_all_measurements_toggled(enabled: bool) -> void:
	if NetworkManager.is_host:
		NetworkManager.request_set_measurement_visibility(enabled)


func _on_team_mode_toggled(enabled: bool) -> void:
	if NetworkManager.is_host:
		NetworkManager.request_set_team_mode(enabled)


func _on_team_selected(index: int, player_id: int, picker: OptionButton) -> void:
	if NetworkManager.is_host:
		NetworkManager.request_set_player_team(player_id, picker.get_item_id(index))


func _on_leave_button_pressed() -> void:
	leave_requested.emit()

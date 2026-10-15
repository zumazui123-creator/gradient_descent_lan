extends Control

@onready var name_input: LineEdit = $Center/Panel/Margin/Content/NameInput
@onready var address_input: LineEdit = $Center/Panel/Margin/Content/AddressInput
@onready var port_input: LineEdit = $Center/Panel/Margin/Content/PortInput
@onready var host_button: Button = $Center/Panel/Margin/Content/Buttons/HostButton
@onready var join_button: Button = $Center/Panel/Margin/Content/Buttons/JoinButton
@onready var status_label: Label = $Center/Panel/Margin/Content/StatusLabel


func _ready() -> void:
	port_input.text = str(NetworkManager.DEFAULT_PORT)
	name_input.grab_focus()


func _on_host_button_pressed() -> void:
	var selected_port := _read_port()
	if selected_port < 0:
		return

	_set_busy(true, "Server wird gestartet …")
	var error := NetworkManager.host_game(name_input.text, selected_port)
	if error != OK:
		_set_busy(false, "Host konnte nicht starten: %s" % error_string(error))


func _on_join_button_pressed() -> void:
	var selected_port := _read_port()
	if selected_port < 0:
		return

	_set_busy(true, "Verbindung wird aufgebaut …")
	var error := NetworkManager.join_game(address_input.text, name_input.text, selected_port)
	if error != OK:
		_set_busy(false, "Verbindung fehlgeschlagen: %s" % error_string(error))


func _read_port() -> int:
	var value := port_input.text.strip_edges()
	if not value.is_valid_int():
		status_label.text = "Der Port muss eine Zahl zwischen 1 und 65535 sein."
		return -1

	var selected_port := int(value)
	if selected_port < 1 or selected_port > 65535:
		status_label.text = "Der Port muss zwischen 1 und 65535 liegen."
		return -1
	return selected_port


func _set_busy(busy: bool, message: String) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	name_input.editable = not busy
	address_input.editable = not busy
	port_input.editable = not busy
	status_label.text = message

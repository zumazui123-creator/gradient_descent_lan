extends Control

signal closed


func open() -> void:
	visible = true
	$Center/Panel/Margin/Content/CloseButton.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _on_close_button_pressed() -> void:
	close()

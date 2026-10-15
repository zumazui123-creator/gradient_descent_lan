extends Node

const MAIN_MENU_SCENE := preload("res://scenes/MainMenu.tscn")

@onready var scene_container: Node = $SceneContainer


func _ready() -> void:
	show_scene(MAIN_MENU_SCENE)


func show_scene(scene: PackedScene) -> void:
	for child in scene_container.get_children():
		scene_container.remove_child(child)
		child.queue_free()

	var next_scene := scene.instantiate()
	scene_container.add_child(next_scene)

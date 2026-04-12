extends Node2D

@export var mass: float = 1000
@export var speed: Vector2
@export var sprite: Texture2D


func _ready() -> void:
	$Sprite2D.texture = sprite

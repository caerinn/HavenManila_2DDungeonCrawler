# Shared by the coffee, the energy drink and the controller. Flies in a
# straight line, can swing from side to side, and vanishes off screen.
# main.gd sets the direction when it spawns one.
class_name Enemy
extends Area2D

@export var speed: float = 60.0
@export var zigzag: float = 0.0
@export var zigzag_speed: float = 6.0

var direction: Vector2 = Vector2.RIGHT
var time_alive: float = 0.0


func _process(delta: float) -> void:
	time_alive += delta

	var swing: float = sin(time_alive * zigzag_speed) * zigzag
	var sideways: Vector2 = direction.orthogonal() * swing

	position += (direction * speed + sideways) * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

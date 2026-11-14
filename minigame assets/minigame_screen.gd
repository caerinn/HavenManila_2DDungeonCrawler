extends Node2D

@onready var label: Label = $doomScreen/deathText
@onready var text_timer: Timer = $dialogueTimer
@onready var text_timer2: Timer = $dialogueTimer2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _on_dialogue_timer_timeout() -> void:
	text_timer.stop()
	label.text = "You are given another chance. "

func _on_dialogue_timer_2_timeout() -> void:
	label.text = "Win... and you live."
	text_timer2.stop()

func _on_minigame_start_timeout() -> void:
	pass # Replace with function body.

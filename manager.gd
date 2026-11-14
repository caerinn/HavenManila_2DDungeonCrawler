extends Node

# Tracks coins collected and a short-lived "combo": grab coins in quick
# succession and the count climbs, which the coin uses to pitch its pickup
# sound higher and higher for a satisfying ramp.

var score := 0
var combo := 0
var combo_timer := 0.0
const COMBO_WINDOW := 1.5  # seconds you have to grab the next coin

# Colour the HUD warmer the higher your combo climbs (white -> hot orange).
const BASE_COLOR := Color(1, 1, 1)
const HOT_COLOR  := Color(1.0, 0.55, 0.15)

var label_tween: Tween

@onready var score_label = %ScoreLabel

func _process(delta):
	# Let the combo cool off if you stop collecting.
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			# Combo dropped — settle the HUD back to its calm white state.
			score_label.add_theme_color_override("font_color", BASE_COLOR)


# Adds a coin and returns the new combo count (so the coin can react to it).
func add_point() -> int:
	score += 1
	combo += 1
	combo_timer = COMBO_WINDOW

	if combo > 1:
		score_label.text = "Coins: %d   x%d combo!" % [score, combo]
	else:
		score_label.text = "Coins: %d" % score

	# Warm the colour and pop the size a little harder as the combo grows.
	var t := clampf((combo - 1) / 8.0, 0.0, 1.0)
	score_label.add_theme_color_override("font_color", BASE_COLOR.lerp(HOT_COLOR, t))
	_pop_label(1.18 + t * 0.22)

	return combo


# Springy scale-pop on the score label so every pickup punches the HUD.
func _pop_label(scale_amount: float):
	if label_tween and label_tween.is_valid():
		label_tween.kill()
	score_label.pivot_offset = Vector2.ZERO   # grow from the top-left text origin
	score_label.scale = Vector2(scale_amount, scale_amount)
	label_tween = score_label.create_tween()
	label_tween.tween_property(score_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

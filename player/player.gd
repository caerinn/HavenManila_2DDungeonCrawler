# --- Horizontal movement ---
const SPEED            = 130.0    # top running speed
const ACCELERATION     = 1300.0   # how fast we reach top speed on the ground
const FRICTION         = 1600.0   # how fast we stop on the ground
const AIR_ACCELERATION = 900.0    # weaker control in the air...
const AIR_FRICTION     = 350.0    # ...and we keep momentum longer in the air

# --- Jumping ---
const JUMP_VELOCITY        = -300.0  # initial jump impulse
const DOUBLE_JUMP_VELOCITY = -260.0  # the second (air) jump, a touch weaker
const JUMP_CUT             = 0.45    # velocity kept when you release jump early (variable height)
const STOMP_BOUNCE         = -260.0  # upward kick when you stomp an enemy
const MAX_FALL_SPEED       = 400.0   # terminal velocity so falls stay controllable
const MAX_AIR_JUMPS        = 1       # extra jumps after leaving the ground

# --- Forgiveness windows (seconds) ---
const COYOTE_TIME  = 0.10  # grace period to jump after walking off an edge
const JUMP_BUFFER  = 0.10  # remember a jump press this long before landing

# Corner correction: if you clip a ceiling tile by just a few pixels on the way
# up, nudge sideways past the corner instead of bonking your head and dropping.
const CORNER_CORRECTION_PIXELS = 4

# --- Gravity feel ---
# Pulled from project settings, then scaled differently going up vs. down.
# Falling faster than you rise is the single biggest "this feels good" trick.
var base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
const RISE_GRAVITY_MULT = 0.9    # a little floaty on the way up
const FALL_GRAVITY_MULT = 1.5    # snappier on the way down
# Apex hang time: near the top of the arc gravity eases off for a graceful beat
# of "hang" that makes the peak readable. (See GMTK / Celeste on jump feel.)
const APEX_SPEED_THRESHOLD = 45.0  # |vertical speed| under this = "near the apex"
const APEX_GRAVITY_MULT    = 0.55  # extra-light gravity inside the hang window

@onready var animatedSprite = $AnimatedSprite2D


func _on_spawn_timer_timeout() -> void:
	pass # Replace with function body.

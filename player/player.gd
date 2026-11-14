extends CharacterBody2D

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

# --- Runtime state ---
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var air_jumps_left := 0
var was_on_floor := false
var is_dead := false
var dust_cooldown := 0.0

# Squash & stretch spring state (see _update_squash). squash > 0 = squashed
# (wide & short), squash < 0 = stretched (tall & thin); it springs back to 0.
var squash := 0.0
var squash_vel := 0.0
var base_sprite_y := 0.0

# --- Camera feel: shake, look-ahead, zoom punch ---
var shake_strength := 0.0
const SHAKE_DECAY = 28.0   # higher = shake settles back faster

# Look-ahead: the camera leads slightly in the direction you're running so you
# can see what you're moving into. The camera is a character too.
var look_ahead_x := 0.0
const LOOK_AHEAD       = 16.0   # how far the camera leads, in pixels
const LOOK_AHEAD_SPEED = 4.0    # how quickly it eases to the lead position

# Zoom "punch": a quick push-in on big impacts that springs back to normal.
var base_zoom := Vector2.ONE
var zoom_punch := 0.0
const ZOOM_PUNCH_DECAY = 5.0

# --- Motion trail (after-images) ---
# A short streak of fading ghost-sprites left behind by the flashy moves
# (double jump, stomp bounce) to make them read as fast and powerful.
var trail_timer := 0.0
var afterimage_cooldown := 0.0
const TRAIL_DURATION      = 0.35
const AFTERIMAGE_INTERVAL = 0.05
const TRAIL_COLOR = Color(0.6, 0.8, 1.0, 0.5)

# --- Squash & stretch (Mario-style spring) ---
const SQUASH_STIFFNESS = 360.0  # spring strength — higher = snappier recovery
const SQUASH_DAMPING   = 16.0   # higher = calmer; lower = more bounce/wobble
const AIR_STRETCH_MAX  = 0.10   # subtle tall-stretch that grows with air speed
const SQUASH_PIVOT     = 16.0   # keeps the feet planted while squashing
const LAND_SQUASH_MIN  = 0.14   # squash from the softest landing
const LAND_SQUASH_MAX  = 0.36   # squash from a full-speed slam
const JUMP_STRETCH     = 0.22   # stretch on take-off
const BOUNCE_SQUASH    = 0.28   # squash kick when stomping an enemy
const SPAWN_SQUASH     = 0.22   # the pop-in at level start

@onready var animatedSprite = $AnimatedSprite2D
@onready var camera         = get_node_or_null("Camera2D")

func _ready():
	add_to_group("player")
	if camera:
		base_zoom = camera.zoom   # remember the resting zoom so punches settle back
	base_sprite_y = animatedSprite.position.y
	
func _physics_process(delta):
	if is_dead:
		return

	_apply_gravity(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	_update_animation()

	# Slip past ceiling corners you *almost* cleared, just before we move.
	_corner_correction()

	# Leave a fading after-image streak during the flashy moves.
	_update_trail(delta)

	# Remember floor state + fall speed, run, then react to having just landed.
	# (move_and_slide zeroes velocity.y on impact, so we must read it first.)
	was_on_floor = is_on_floor()
	var fall_speed = velocity.y
	move_and_slide()
	_check_landing(fall_speed)
	
func _apply_gravity(delta):
	if not is_on_floor():
		# Heavier gravity while falling than while rising = a satisfying arc.
		var mult = RISE_GRAVITY_MULT if velocity.y < 0.0 else FALL_GRAVITY_MULT
		# Apex hang: ease gravity right at the top of the arc for a beat of float.
		if absf(velocity.y) < APEX_SPEED_THRESHOLD:
			mult *= APEX_GRAVITY_MULT
		velocity.y += base_gravity * mult * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
		
# Animations
func _update_animation():
	if not is_on_floor():
		animated_sprite.play("jump")
	elif abs(velocity.x) > 10.0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

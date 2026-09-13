## Every colour in the game, in one place.
##
## The course used to pick its colours one at a time, wherever they were needed.
## That produced about a dozen greens sitting at almost the same brightness, so
## nothing read at a glance: the fairway, the rough and the trees were all the
## same grey once you squinted at them.
##
## The fix is a **value ladder**. Squint at the course, or turn it greyscale, and
## the surfaces still sort themselves from dark to light in a fixed order:
##
##     scrub . water . rough . first cut . fairway . stripe . green . sand
##
## Every turf colour below is picked to sit on that ladder with real separation
## between the rungs, and warmed towards yellow so the course reads as a hazy
## morning rather than a snooker table. Water breaks the ladder on purpose -- it
## sits close in brightness to the first cut but is a completely different hue,
## so it separates by colour instead. Trouble should be obvious by hue alone.
##
## `tools/palette_check.gd` asserts the ordering, so a colour tweaked by eye
## cannot quietly collapse two rungs back together.
##
## A static class rather than an autoload, for the same reason Sfx is one:
## autoloads are invisible to the `--script` test harnesses.
class_name Palette
extends RefCounted

# --- Turf, dark to light --------------------------------------------------

## Beyond the hole. Reads as unlit ground rather than as a black border.
const SHADE := Color("#16281b")
## Deep rough: the scrub and tree cover that eats golf balls. The darkest turf
## on the course, so a blob of it reads as trouble before you have read a word.
const SCRUB_SHADOW := Color("#17300f")
const SCRUB := Color("#1f3a1a")
## The sunlit top of a clump of scrub, for the pass that gives it a canopy.
const SCRUB_CROWN := Color("#2d5220")
const ROUGH := Color("#325a2e")
## The collar of longer grass around the fairway. Sits between the two, which is
## both where it belongs in golf and what stops the fairway edge being a hard
## line between two flat colours.
const FIRST_CUT := Color("#4e8140")
const FAIRWAY := Color("#74a94f")
const FAIRWAY_STRIPE := Color("#7fb559")
const GREEN_FRINGE := Color("#8abc5c")
const GREEN := Color("#97c766")
const TEE := Color("#85b85e")

# --- Trouble --------------------------------------------------------------

const SAND := Color("#e6d2a6")
const SAND_SHADOW := Color("#c9b084")
const WATER_DEEP := Color("#24536b")
const WATER_SHALLOW := Color("#3e7e96")
const WATER_FOAM := Color("#7fb3c4")
## Boggy ground: reads as water that has lost the argument with the grass.
const MARSH := Color("#35634f")
const EARTH := Color("#5e4a2e")
const EARTH_SHADOW := Color("#45371f")

# --- Course furniture -----------------------------------------------------

## Near black, so the cup reads as a hole in the ground and not a dark disc.
const CUP := Color("#14180f")
## The one warm red on the course. It is the only thing that colour, which is
## what makes the eye go to it before anything else on screen.
const FLAG := Color("#e0503c")
const YARDAGE_RING := Color(1.0, 1.0, 1.0, 0.09)

# --- Light ----------------------------------------------------------------

## The sun sits off the top left, so everything casts down and to the right.
## One direction for the whole game: nothing sells depth like every shadow in a
## scene agreeing with every other one.
const SUN := Vector2(0.52, 0.85)
const SHADOW := Color(0.05, 0.09, 0.05, 0.28)
const SHADOW_SOFT := Color(0.05, 0.09, 0.05, 0.14)
## Warm light catching the top edge of raised things.
const HIGHLIGHT := Color(1.0, 0.98, 0.86, 0.16)

# --- The ball -------------------------------------------------------------

const BALL := Color("#fdfbf2")
const BALL_SHADE := Color("#cfd0c2")

# --- Chrome ---------------------------------------------------------------
#
# A polished clubhead, top of the crown to the bottom of the sole. The stops
# crowd together around the middle on purpose: a smooth ramp from light to dark
# is what plastic looks like, and what makes metal read as metal is the hard,
# narrow band where the curve turns over and starts reflecting the ground
# instead of the sky.

const CHROME_SKY := Color("#f6fafb")
const CHROME_HIGH := Color("#d3dee4")
const CHROME_MID := Color("#8b9ca7")
const CHROME_TURN := Color("#4d5c66")
## The horizon. Everything else on this list is in service of it.
const CHROME_HORIZON := Color("#161e23")
const CHROME_UNDER := Color("#334049")
const CHROME_GROUND := Color("#5d6d6a")
const CHROME_BOUNCE := Color("#93a58c")
const CHROME_SOLE := Color("#dfe6dc")
## The pale plane of a clubface, and the score lines cut across it.
const CHROME_FACE := Color("#c3ced5")
const CHROME_SEAM := Color(0.16, 0.21, 0.24, 0.62)
## Steel, and the black ferrule where it meets the head.
const CHROME_SHAFT := Color("#8d99a1")
const FERRULE := Color("#16221c")
## Anodised green, the way a club maker brands one.
const ANODISED := Color("#4f9e46")
const ANODISED_DARK := Color("#2f6b31")

# --- Ink ------------------------------------------------------------------

## Warm off-white rather than pure white: pure white on a dark panel glares, and
## the whole palette is warm, so cold text would sit apart from it.
const INK := Color("#f2f5ec")
const INK_DIM := Color(0.949, 0.961, 0.925, 0.66)
const INK_FAINT := Color(0.949, 0.961, 0.925, 0.38)

const PANEL := Color(0.078, 0.125, 0.102, 0.88)
const PANEL_RAISED := Color(0.110, 0.169, 0.133, 0.94)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.10)

# --- Accents --------------------------------------------------------------

const ACCENT_SHOT := Color("#8fcc6b")
const ACCENT_TECHNIQUE := Color("#6fb0dc")
const ACCENT_UTILITY := Color("#e0b96a")

const GOOD := Color("#8fcc6b")
const WARN := Color("#e8a44e")
const DANGER := Color("#e06a54")
const GOLD := Color("#f0c860")


## Where a thing of this height throws its shadow.
static func shadow_offset(height: float) -> Vector2:
	return SUN * height


## A surface lit from the sun side. Used for the top edge of anything raised.
static func lit(base: Color, amount: float = 0.12) -> Color:
	return base.lerp(Color(1.0, 0.97, 0.84), amount)


## The same surface in shade. Deliberately not just "darker": shadowed ground
## goes cooler and less saturated as well as darker, which is what stops a shaded
## green from looking like a different, muddier green.
static func shaded(base: Color, amount: float = 0.18) -> Color:
	return base.lerp(Color(0.20, 0.28, 0.34), amount)

## Procedurally generated textures, built once on first use and cached.
##
## The same bargain the sound bank makes: no binary assets ship with the game,
## everything is generated at runtime, and the result is still real texture
## rather than flat colour. A hole drawn in flat fills reads as a diagram; the
## difference between that and something that looks like ground is almost
## entirely grain and shadow.
##
## Textures are generated rather than drawn as thousands of little primitives
## because the renderer redraws on window events as well as on hole changes, and
## ten thousand draw calls per redraw is a stutter you can feel.
##
## Static, not an autoload -- autoloads are invisible to the `--script` harnesses.
class_name TextureBank
extends RefCounted

## Strengths above are deliberately tiny. The first pass used three times these
## values and the rough came out looking like television static -- loud grain
## does not read as "textured", it reads as noise, and it quietly wrecked the
## fairway-against-rough contrast by dragging the rough's brightness up. Texture
## should be something you notice only when you take it away.
##
## Grain tiles must be a power of two and seamless, or the repeat shows as a grid.
const GRAIN_SIZE := 128
const GRADIENT_SIZE := 64

static var _cache: Dictionary = {}


## Mottling for grass. Light and dark speckle in one texture, so a single draw
## gives both the highlights and the shadows between blades.
static func turf_grain() -> Texture2D:
	return _cached(&"turf", func() -> Texture2D:
		return _grain(0.085, 0.10, 1337))


## Finer and stronger than turf, because sand is the one surface where you can
## actually see the individual grains catching the light.
static func sand_grain() -> Texture2D:
	return _cached(&"sand", func() -> Texture2D:
		return _grain(0.240, 0.20, 90210))


## Broad, slow variation. Used to break up very large flat areas -- the rough
## covers most of the screen, and uniform speckle over that much space still
## reads as flat.
static func turf_mottle() -> Texture2D:
	return _cached(&"mottle", func() -> Texture2D:
		return _grain(0.022, 0.06, 5150))


## A soft round shadow, black fading to nothing at the rim. Everything that sits
## proud of the ground drops one of these.
static func soft_shadow() -> Texture2D:
	return _cached(&"shadow", func() -> Texture2D:
		return _radial(Color(0.05, 0.09, 0.05), 1.0, 2.1))


## The same shape in warm light, for the sunlit crown of a clump of trees.
static func soft_light() -> Texture2D:
	return _cached(&"light", func() -> Texture2D:
		return _radial(Color(1.0, 0.97, 0.84), 1.0, 1.6))


# --- Generation -----------------------------------------------------------

## Seamless noise turned into a two-sided alpha mask: pixels above the midpoint
## become white, pixels below become black, and how far from the middle they sit
## becomes their opacity. Drawn over a colour that gives mottling in both
## directions at once, which is what grass actually does.
static func _grain(frequency: float, strength: float, seed_value: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	var source := noise.get_seamless_image(GRAIN_SIZE, GRAIN_SIZE)

	var image := Image.create_empty(GRAIN_SIZE, GRAIN_SIZE, false, Image.FORMAT_RGBA8)
	for y in GRAIN_SIZE:
		for x in GRAIN_SIZE:
			# Seamless noise comes back normalised into 0..1 around a 0.5 midpoint.
			var signed_value := (source.get_pixel(x, y).r - 0.5) * 2.0
			var tone := 1.0 if signed_value >= 0.0 else 0.0
			image.set_pixel(x, y, Color(tone, tone, tone,
				absf(signed_value) * strength))
	return ImageTexture.create_from_image(image)


## A radial gradient, opaque at the centre and gone by the rim. `falloff` above
## one keeps the middle solid and pulls the fade towards the edge, which is what
## makes a shadow look soft rather than like a blurry ring.
static func _radial(colour: Color, strength: float, falloff: float) -> Texture2D:
	var image := Image.create_empty(GRADIENT_SIZE, GRADIENT_SIZE, false,
		Image.FORMAT_RGBA8)
	var centre := Vector2(GRADIENT_SIZE, GRADIENT_SIZE) * 0.5
	var radius := float(GRADIENT_SIZE) * 0.5

	for y in GRADIENT_SIZE:
		for x in GRADIENT_SIZE:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), falloff) * strength
			image.set_pixel(x, y, Color(colour.r, colour.g, colour.b, alpha))
	return ImageTexture.create_from_image(image)


static func _cached(key: StringName, build: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Throws the cache away. Only the tests need this, to prove generation actually
## happens rather than quietly handing back something built by an earlier case.
static func clear_cache() -> void:
	_cache.clear()

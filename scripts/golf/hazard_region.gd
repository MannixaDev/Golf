## A patch of ground on a hole: a shape plus the surface that fills it.
##
## Regions are stored on HoleData in draw order, and later regions sit on top of
## earlier ones, so a bunker authored after the fairway cuts into it.
class_name HazardRegion
extends Resource

enum Shape { CIRCLE, POLYGON }

## Resolved through SurfaceLibrary, so holes never carry resource references.
@export var surface_id: StringName = &"rough"
@export var shape: Shape = Shape.CIRCLE

@export_group("Circle")
@export var centre: Vector2 = Vector2.ZERO
@export var radius: float = 50.0

@export_group("Polygon")
@export var polygon: PackedVector2Array = PackedVector2Array()

## Cached once. The clump is rolled from the region's position, so it never
## changes -- but it is asked for every frame the ball is in the air.
var _blobs: Array[Rect2] = []
## -1 until asked. See is_foliage().
var _foliage: int = -1


func contains(point: Vector2) -> bool:
	# Foliage is drawn as a clump of overlapping blobs, so that is what it has to
	# be measured as. Testing the bounding circle instead made the canopy that
	# stops your ball noticeably larger than the one you can see -- you would aim
	# at a gap that was really there and be told you had hit a tree.
	if is_foliage():
		for blob in blobs():
			if point.distance_squared_to(blob.position) <= blob.size.x * blob.size.x:
				return true
		return false

	match shape:
		Shape.CIRCLE:
			return point.distance_squared_to(centre) <= radius * radius
		Shape.POLYGON:
			if polygon.size() < 3:
				return false
			return Geometry2D.is_point_in_polygon(point, polygon)
	return false


## True where this region stands up off the ground rather than being cut into it.
##
## Cached: contains() is asked every frame the ball is in the air, and this was
## a library lookup by name each time.
func is_foliage() -> bool:
	if _foliage < 0:
		var type := surface()
		_foliage = 1 if (type != null and type.has_canopy()) else 0
	return _foliage == 1


## The blobs a clump is made of: centre and radius packed into a Rect2, the same
## way the renderer wants them.
##
## Deterministic from the region's own position, so the picture and the physics
## agree without either having to be told about the other. This used to live in
## the renderer alone, which is exactly how the two came apart.
func blobs() -> Array[Rect2]:
	if not _blobs.is_empty():
		return _blobs

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(centre.x), roundi(centre.y)))
	_blobs.append(Rect2(centre, Vector2(radius * 0.80, 0.0)))
	var count := 3 if radius > 26.0 else 2
	for i in count:
		var angle := rng.randf_range(0.0, TAU)
		var reach := radius * rng.randf_range(0.26, 0.42)
		_blobs.append(Rect2(
			centre + Vector2(cos(angle), sin(angle) * 0.78) * reach,
			Vector2(radius * rng.randf_range(0.50, 0.70), 0.0)))
	return _blobs


func surface() -> SurfaceType:
	return SurfaceLibrary.by_id(surface_id)

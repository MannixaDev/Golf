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


func contains(point: Vector2) -> bool:
	match shape:
		Shape.CIRCLE:
			return point.distance_squared_to(centre) <= radius * radius
		Shape.POLYGON:
			if polygon.size() < 3:
				return false
			return Geometry2D.is_point_in_polygon(point, polygon)
	return false


func surface() -> SurfaceType:
	return SurfaceLibrary.by_id(surface_id)

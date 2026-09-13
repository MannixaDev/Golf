## Loads every SurfaceType in a folder and indexes it by id.
##
## Holes refer to surfaces by id rather than by resource reference, so a hole
## .tres stays readable and a new hazard type never requires rewiring holes.
class_name SurfaceLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/surfaces"

static var _by_id: Dictionary = {}
static var _loaded: bool = false
static var _fallback: SurfaceType = null


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true

	for res in ResourceFolder.load_all(dir_path):
		if res is SurfaceType:
			var surface: SurfaceType = res
			_by_id[surface.id] = surface
		else:
			push_warning("SurfaceLibrary: %s is not a SurfaceType" % res.resource_path)


static func by_id(id: StringName) -> SurfaceType:
	ensure_loaded()
	if _by_id.has(id):
		return _by_id[id]
	push_warning("SurfaceLibrary: unknown surface '%s'" % id)
	return fallback()


static func has(id: StringName) -> bool:
	ensure_loaded()
	return _by_id.has(id)


## A plain, harmless surface, so a bad id can never crash a hole mid-round.
static func fallback() -> SurfaceType:
	if _fallback == null:
		_fallback = SurfaceType.new()
		_fallback.id = &"unknown"
		_fallback.display_name = "Ground"
	return _fallback


static func all_ids() -> Array:
	ensure_loaded()
	return _by_id.keys()

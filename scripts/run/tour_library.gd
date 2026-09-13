## Every rung of the ladder, in order, and which of them you have earned.
##
## Kept separate from Settings because these are two different things wearing
## the same coat: Settings is what you prefer, this is what you have done. One
## of them is safe to reset and the other is somebody's career.
class_name TourLibrary
extends RefCounted

const PATH := "res://resources/tours"
const SAVE := "user://career.cfg"
const SECTION := "career"

static var _tours: Array[TourSpec] = []
static var _loaded := false

## Highest rung the player has earned the right to play.
static var unlocked_rung: int = 0
## Best finishing place on each rung, keyed by id. Absent means never finished.
static var best_place: Dictionary = {}
static var _career_loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(PATH):
		if res is TourSpec:
			_tours.append(res)
		else:
			push_warning("TourLibrary: %s is not a TourSpec" % res.resource_path)
	_tours.sort_custom(func(a: TourSpec, b: TourSpec) -> bool: return a.rung < b.rung)


static func all() -> Array[TourSpec]:
	ensure_loaded()
	return _tours


static func by_rung(rung: int) -> TourSpec:
	ensure_loaded()
	for tour in _tours:
		if tour.rung == rung:
			return tour
	return _tours[0] if not _tours.is_empty() else null


## The rung everything falls back to, including every harness that does not care
## about the ladder. Must always exist and must always be the gentle one.
static func opening() -> TourSpec:
	return by_rung(0)


static func is_unlocked(tour: TourSpec) -> bool:
	ensure_career_loaded()
	return tour != null and tour.rung <= unlocked_rung


# --- The career -----------------------------------------------------------

static func ensure_career_loaded() -> void:
	if _career_loaded:
		return
	_career_loaded = true
	var config := ConfigFile.new()
	if config.load(SAVE) != OK:
		return  # first time out
	unlocked_rung = int(config.get_value(SECTION, "unlocked_rung", 0))
	best_place = config.get_value(SECTION, "best_place", {})


static func save_career() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "unlocked_rung", unlocked_rung)
	config.set_value(SECTION, "best_place", best_place)
	config.save(SAVE)


## Record how a round went. Finishing one at all -- surviving the cut to the
## last green -- earns the next rung, because the cut is the thing the ladder
## actually tightens and clearing it is the achievement worth marking.
##
## Returns true if this opened something new up.
static func record_result(tour: TourSpec, place: int, made_the_end: bool) -> bool:
	ensure_career_loaded()
	if tour == null:
		return false

	var previous: int = int(best_place.get(String(tour.id), 0))
	if place > 0 and (previous <= 0 or place < previous):
		best_place[String(tour.id)] = place

	var opened := false
	if made_the_end and tour.rung >= unlocked_rung and by_rung(tour.rung + 1) != null \
			and by_rung(tour.rung + 1).rung == tour.rung + 1:
		unlocked_rung = tour.rung + 1
		opened = true
	save_career()
	return opened


static func best_on(tour: TourSpec) -> int:
	ensure_career_loaded()
	return int(best_place.get(String(tour.id), 0)) if tour != null else 0


## Dev and test only: forget the career.
static func reset_career() -> void:
	unlocked_rung = 0
	best_place = {}
	_career_loaded = true
	save_career()

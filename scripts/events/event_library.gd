## Loads every EventSpec and picks one that fits where the run has got to.
class_name EventLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/events"

static var _events: Array[EventSpec] = []
static var _loaded: bool = false


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(dir_path):
		if res is EventSpec:
			_events.append(res)
		else:
			push_warning("EventLibrary: %s is not an EventSpec" % res.resource_path)
	_events.sort_custom(func(a: EventSpec, b: EventSpec) -> bool: return a.id < b.id)


static func all() -> Array[EventSpec]:
	ensure_loaded()
	return _events


## Weighted pick, avoiding anything already seen this run so a single run does
## not tell you the same joke twice.
static func pick(rng: RandomNumberGenerator, holes_played: int,
		seen: Array) -> EventSpec:
	ensure_loaded()
	var pool: Array[EventSpec] = []
	var total := 0.0
	for event in _events:
		if event.weight <= 0.0 or holes_played < event.min_holes_played:
			continue
		if seen.has(event.id):
			continue
		pool.append(event)
		total += event.weight

	# Everything has been seen: allow repeats rather than showing nothing.
	if pool.is_empty():
		for event in _events:
			if event.weight > 0.0 and holes_played >= event.min_holes_played:
				pool.append(event)
				total += event.weight
	if pool.is_empty():
		return null

	var roll := rng.randf() * total
	for event in pool:
		roll -= event.weight
		if roll <= 0.0:
			return event
	return pool[pool.size() - 1]

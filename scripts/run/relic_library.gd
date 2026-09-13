## Loads every RelicSpec in a folder and indexes it by id.
class_name RelicLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/relics"

static var _by_id: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded(dir_path: String = DEFAULT_PATH) -> void:
	if _loaded:
		return
	_loaded = true
	for res in ResourceFolder.load_all(dir_path):
		if res is RelicSpec:
			_by_id[res.id] = res
		else:
			push_warning("RelicLibrary: %s is not a RelicSpec" % res.resource_path)


static func by_id(id: StringName) -> RelicSpec:
	ensure_loaded()
	return _by_id.get(id)


static func all() -> Array[RelicSpec]:
	ensure_loaded()
	var out: Array[RelicSpec] = []
	for id in _by_id:
		out.append(_by_id[id])
	out.sort_custom(func(a: RelicSpec, b: RelicSpec) -> bool: return a.id < b.id)
	return out


## A relic the player does not already own, weighted by rarity.
static func offer(rng: RandomNumberGenerator, owned: Array[RelicSpec]) -> RelicSpec:
	ensure_loaded()
	var owned_ids: Dictionary = {}
	for relic in owned:
		owned_ids[relic.id] = true

	var pool: Array[RelicSpec] = []
	var total := 0.0
	for relic in all():
		if owned_ids.has(relic.id) or relic.weight <= 0.0:
			continue
		pool.append(relic)
		total += relic.weight

	if pool.is_empty():
		return null

	var roll := rng.randf() * total
	for relic in pool:
		roll -= relic.weight
		if roll <= 0.0:
			return relic
	return pool[pool.size() - 1]

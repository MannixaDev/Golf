## Loads every ClubSpec resource in a folder.
##
## Dropping a new .tres into res://resources/clubs/ adds a club to the bag with
## no code change.
class_name ClubLibrary
extends RefCounted

const DEFAULT_PATH := "res://resources/clubs"


static func load_all(dir_path: String = DEFAULT_PATH) -> Array[ClubSpec]:
	var clubs: Array[ClubSpec] = []
	for res in ResourceFolder.load_all(dir_path):
		if res is ClubSpec:
			clubs.append(res)
		else:
			push_warning("ClubLibrary: %s is not a ClubSpec" % res.resource_path)

	clubs.sort_custom(func(a: ClubSpec, b: ClubSpec) -> bool:
		return a.sort_order < b.sort_order)
	return clubs

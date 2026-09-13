## Loads every resource in a folder, in a way that survives being exported.
##
## Four systems in this game discover their content by scanning a folder rather
## than by keeping a registry, which is what makes "drop a .tres in and it exists"
## true. That only holds if the scan matches what is actually in the build:
##
##   - export can convert text resources to binary, so a .tres becomes a .res
##   - remapped files gain a .remap suffix on top of their real name
##
## Filtering on ".tres" alone therefore works perfectly in the editor and finds
## nothing at all in a real build, which would leave the game with no clubs, no
## cards, no surfaces and no map nodes. Hence this single shared scan.
class_name ResourceFolder
extends RefCounted

const RESOURCE_EXTENSIONS := [".tres", ".res"]


static func load_all(dir_path: String) -> Array[Resource]:
	var found: Array[Resource] = []

	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("ResourceFolder: cannot open %s" % dir_path)
		return found

	for file_name in dir.get_files():
		var clean_name := file_name.trim_suffix(".remap")
		if not _is_resource(clean_name):
			continue
		var res: Resource = load(dir_path.path_join(clean_name))
		if res == null:
			push_warning("ResourceFolder: failed to load %s" % clean_name)
			continue
		found.append(res)

	if found.is_empty():
		push_warning("ResourceFolder: %s contained no resources" % dir_path)
	return found


static func _is_resource(file_name: String) -> bool:
	for extension in RESOURCE_EXTENSIONS:
		if file_name.ends_with(extension):
			return true
	return false

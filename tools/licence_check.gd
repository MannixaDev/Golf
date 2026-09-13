## Pre-release gate: does everything we redistribute carry its licence?
##
## Deliberately **not** part of the routine battery. It fails until somebody
## does a manual step, and a suite that is permanently red is a suite people
## stop reading. Run it before publishing a build.
##
## Fairway Fiends ships no binary assets except its fonts. Lato is free to embed
## under the SIL Open Font License, and that permission is conditional: clause 2
## requires the copyright notice and the licence to travel with every copy. A
## build without them is a build distributed without permission.
extends SceneTree

const FONT_DIR := "res://resources/fonts"
const LICENCE := "res://resources/fonts/OFL.txt"
## Sections the real OFL 1.1 contains. Checked because the obvious way to get
## this wrong is to paste in a summary of the licence rather than the licence --
## which is exactly what a web fetch of it returns.
const REQUIRED_SECTIONS := [
	"PREAMBLE", "DEFINITIONS", "PERMISSION & CONDITIONS",
	"TERMINATION", "DISCLAIMER",
]
## The full text is a little over 4KB. Anything much shorter is a summary.
const MIN_LENGTH := 3500

var failures := 0


func _initialize() -> void:
	print("=== fonts we redistribute ===")

	var fonts := 0
	var dir := DirAccess.open(FONT_DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".ttf") or file.ends_with(".otf"):
				fonts += 1
				print("  %s" % file)
	print("  %d font files" % fonts)

	if fonts == 0:
		print("  nothing to license")
		_finish()
		return

	if not FileAccess.file_exists(LICENCE):
		_expect(false, "no OFL.txt beside the fonts")
		print("")
		print("  Lato is SIL Open Font License 1.1. Clause 2 requires the licence")
		print("  to travel with every copy, so the build cannot ship without it.")
		print("")
		print("  Download the full text and save it as:")
		print("    resources/fonts/OFL.txt")
		print("  from https://openfontlicense.org/documents/OFL.txt")
		print("")
		print("  Fetch it as a file rather than through anything that summarises")
		print("  pages: a paraphrased licence misstates the terms you are")
		print("  granting, which is worse than having none at all.")
		_finish()
		return

	var text := FileAccess.get_file_as_string(LICENCE)
	print("  OFL.txt present, %d characters" % text.length())
	_expect(text.length() >= MIN_LENGTH,
		"OFL.txt is only %d characters -- that is a summary, not the licence"
			% text.length())
	for section in REQUIRED_SECTIONS:
		_expect(text.contains(section), "OFL.txt is missing its %s" % section)
	_expect(text.contains("Version 1.1"), "OFL.txt does not name its version")
	# Clause 2 wants the copyright notice, not just the licence, and the blank
	# template from openfontlicense.org carries neither -- it ships with
	# <Copyright Holder> placeholders where the notice belongs.
	_expect(not text.contains("<Copyright Holder>"),
		"OFL.txt still has the template's placeholder copyright in it")
	_expect(text.contains("Reserved Font Name"),
		"OFL.txt does not carry the reserved font name")
	for font in ["Lato-Regular.ttf"]:
		_expect(_notice_matches_font(text, "%s/%s" % [FONT_DIR, font]),
			"the notice in OFL.txt matches the one inside %s" % font)

	_check_the_build_carries_it()
	_finish()


## The licence sitting in the repository protects nobody: what has to carry it
## is the thing people download. A plain .txt is not a resource Godot imports,
## so "all_resources" leaves it behind unless the preset names it explicitly --
## which is exactly how this went wrong the first time.
func _check_the_build_carries_it() -> void:
	print("")
	print("=== builds ===")
	var packs := _built_packs()
	if packs.is_empty():
		print("  no builds to check")
		return
	for pack in packs:
		# Said out loud, because _expect is silent when it passes and a build
		# check that quietly examined nothing looks exactly like one that passed.
		print("  %s (%.1f MB)" % [pack.get_file(),
			FileAccess.get_file_as_bytes(pack).size() / 1048576.0])
		_expect(_pack_contains(pack, "SIL OPEN FONT LICENSE"),
			"%s ships the licence" % pack.get_file())
		_expect(_pack_contains(pack, "tyPoland"),
			"%s ships the copyright notice with it" % pack.get_file())


## Every pack or self-contained executable under build/.
func _built_packs() -> Array[String]:
	var found: Array[String] = []
	for dir_name in ["windows", "web"]:
		var path := "res://build/%s" % dir_name
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		for file in dir.get_files():
			if file.ends_with(".pck") or file.ends_with(".exe"):
				found.append("%s/%s" % [path, file])
	return found


## The copyright line the font itself declares, which is the authority on what
## clause 2 requires us to reproduce. Read out of the name table rather than
## written from memory: a licence notice is not a thing to recall.
func _notice_matches_font(text: String, font_path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(font_path)
	if bytes.is_empty():
		return false
	# Name-table strings are UTF-16BE, so the nulls come out between letters.
	var flat := ""
	for byte in bytes:
		if byte >= 32 and byte < 127:
			flat += char(byte)
	var mark := flat.find("tyPoland")
	if mark < 0:
		return false
	return text.contains("tyPoland")


## PackedByteArray has no substring search, and a 100MB executable is far too
## big to turn into a String, so this walks it a window at a time.
func _pack_contains(path: String, needle: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var want := needle.to_ascii_buffer()
	var chunk := 1 << 20
	var carry := PackedByteArray()
	while not file.eof_reached():
		var block := file.get_buffer(chunk)
		if block.is_empty():
			break
		var window := carry + block
		if _find(window, want) >= 0:
			return true
		# Keep the tail, so a match straddling two reads is still found.
		carry = window.slice(maxi(window.size() - want.size() + 1, 0))
	return false


func _find(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	var limit := haystack.size() - needle.size()
	for start in range(maxi(limit + 1, 0)):
		if haystack[start] != needle[0]:
			continue
		var hit := true
		for i in range(1, needle.size()):
			if haystack[start + i] != needle[i]:
				hit = false
				break
		if hit:
			return start
	return -1


func _finish() -> void:
	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)

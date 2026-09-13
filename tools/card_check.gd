## Diagnostic: load every card and print what it parsed to, so resource format
## problems surface immediately instead of at runtime.
extends SceneTree

var failures := 0


func _initialize() -> void:
	CardLibrary.ensure_loaded()
	var ids: Array = CardLibrary.all_ids()
	ids.sort()
	print("%d cards found" % ids.size())

	for id in ids:
		var card: CardData = CardLibrary.template(id)
		var kind: String = ["SHOT", "TECHNIQUE", "UTILITY"][card.type]
		print("  %-14s %-10s cost %d  effects %d" % [
			card.id, kind, card.effective_cost(), card.active_effects().size()])
		for effect in card.active_effects():
			if effect == null:
				print("      !! NULL EFFECT -- resource failed to parse")
				continue
			print("      %-22s modifier=%s  %s" % [
				effect.get_script().get_global_name(),
				effect.is_shot_modifier(), effect.describe()])
		if card.is_shot():
			var profile := ShotProfile.from_card(card)
			print("      %.0f yd, spread %.1f, curve %.1f" % [
				profile.carry_yards_max, profile.dispersion_deg, profile.curve_deg])

		# Every card should have something to gain from the driving range, and
		# upgrading a copy must not touch the shared template.
		var copy := CardLibrary.copy(id)
		if not copy.can_upgrade():
			print("      !! nothing to upgrade")
			failures += 1
			continue
		copy.upgrade()
		print("      upgrade -> %-16s cost %d  %s" % [
			copy.title(), copy.effective_cost(), copy.upgrade_note])
		if copy.is_shot():
			var upgraded_profile := ShotProfile.from_card(copy)
			print("               %.0f yd, spread %.2f" % [
				upgraded_profile.carry_yards_max, upgraded_profile.dispersion_deg])
		if CardLibrary.template(id).upgraded:
			print("      !! upgrading a copy changed the shared template")
			failures += 1

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)

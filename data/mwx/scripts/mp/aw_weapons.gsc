// Ported Advanced Warfare weapons (W1: the explosive crossbow).
//
// Two hooks are needed because HMW's own class script does not handle iw5_* weapon refs:
// - isvalidsecondary(): HMW's whitelist only lists h2_* / h1_* refs, so a class with
//   "iw5_exocrossbow" would be replaced by the default secondary.
// - buildweaponname(): HMW's replacement (scripts/mp_patches/custom_weapons.gsc) builds
//   "<ref>_mp_<attachment>" for iw5_* but has no return in that branch, so the class would get an
//   undefined weapon name. AW/H1 assets are named "<ref>_mp[_<attachment>]" and attachment variants
//   are resolved by the engine from the weapon def, so the name is built directly here.
//
// Both replacefunc calls run in init(): the loader executes every script's main() first (that is
// where HMW installs its replacements) and init() afterwards, so ours wins.

init()
{
	replacefunc(maps\mp\gametypes\_class::isvalidsecondary, ::aw_isvalidsecondary);
	replacefunc(maps\mp\gametypes\_class::buildweaponname, ::aw_buildweaponname);
}

aw_isvalidsecondary(weapon, twoprimaries, report)
{
	if (weapon == "iw5_exocrossbow")
		return 1;

	return scripts\mp_patches\custom_weapons::isvalidsecondary(weapon, twoprimaries, report);
}

aw_buildweaponname(ref, attachment1, attachment2, camo, perks, unused)
{
	if (!isdefined(ref) || ref == "" || ref == "none")
		return ref;

	if (!issubstr(ref, "iw5_"))
		return scripts\mp_patches\custom_weapons::buildweaponname(ref, attachment1, attachment2, camo, perks);

	// AW naming: <ref>_mp, then _<attachment>. The attachment is only appended when the weapon's
	// statstable attachment list allows it (the same list isvalidattachment checks). AW weapons have
	// no _camoNN variants yet, so a selected camo is ignored instead of giving an unknown weapon.
	name = ref + "_mp";

	if (isdefined(attachment1) && attachment1 != "" && attachment1 != "none")
	{
		allowed = maps\mp\_utility::getweaponattachmentarrayfromstats(ref);
		if (common_scripts\utility::array_contains(allowed, attachment1))
			name = name + "_" + attachment1;
	}

	return name;
}

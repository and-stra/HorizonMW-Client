// MWX "just play": no persistent weapon stats.
//
// HMW's _persistence::incrementweaponstat() returns early when level.disableweaponstats is set
// (refs\dumps\hmw_files\maps\mp\gametypes\_persistence.gsc), so shots/kills/hits/deaths no longer
// reach the players2 weaponStats array. That array is indexed by the playerdata Weapon enum, whose
// member count we extend at runtime (ddl_weapon_enum.cpp); writing stats for the appended indices
// is exactly what must not happen.
//
// init() runs for every script load, including the frontend (mapname mp_vlobby_room / mp_background),
// so it only acts on a real map.

init()
{
	mapname = getdvar("mapname");
	if (mapname == "" || mapname == "mp_vlobby_room" || mapname == "mp_background")
		return;

	level.disableweaponstats = 1;
	print("[mwx] weapon stats disabled on " + mapname);
}

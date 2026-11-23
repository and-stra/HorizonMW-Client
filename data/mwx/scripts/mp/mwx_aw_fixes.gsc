// MWX: helicopter killstreak fix for maps without helicopter paths (from opencode/aw-maps).
// The AW faction names are fixed in C++ (factions.cpp adds the "marines" row to mp/factionTable.csv).
// HMW's maps/mp/_helicopter::init() returns early when the map has no "heli_start" /
// "heli_loop_start" nodes, so level.killstreakfuncs["helicopter_mp"] is never set: the
// reward can still be earned (it only checks level.hardpointitems) but does nothing when
// used. Disable it instead: no reward, and players/bots get a UAV in its slot.
init()
{
	// scripts/mp also load in the frontend (virtual lobby); only run for a real map
	mapname = getdvar("mapname");
	if (mapname == "" || mapname == "mp_vlobby_room" || mapname == "mp_background")
		return;

	level thread mwx_heli_check();
}

mwx_heli_check()
{
	wait 0.1;

	hasnodes = 0;
	if (isdefined(level.heli_start_nodes) && level.heli_start_nodes.size > 0)
		hasnodes = 1;

	if (hasnodes)
		return;

	if (isdefined(level.hardpointitems))
		level.hardpointitems["helicopter_mp"] = 0;

	print("[aw-fix] " + getdvar("mapname") + ": no heli_start nodes, helicopter killstreak disabled");
	level thread mwx_heli_filter();
}

mwx_heli_filter()
{
	level endon("game_ended");

	for (;;)
	{
		wait 1;
		if (!isdefined(level.players))
			continue;

		foreach (p in level.players)
		{
			if (!isdefined(p) || !isdefined(p.customKillstreaks))
				continue;

			changed = 0;
			for (i = 0; i < p.customKillstreaks.size; i++)
			{
				if (p.customKillstreaks[i] == "helicopter_mp")
				{
					p.customKillstreaks[i] = "radar_mp";
					changed = 1;
				}
			}
			if (changed)
				print("[aw-fix] " + p.name + ": helicopter_mp replaced with radar_mp (no heli paths on this map)");
		}
	}
}

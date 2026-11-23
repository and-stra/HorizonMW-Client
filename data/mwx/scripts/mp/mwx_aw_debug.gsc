// MWX debug helpers for the ported Advanced Warfare maps (branch opencode/aw-maps).
// Only active with mwx_debug_gamemodes 1.
// - factions: prints game["allies"] / game["axis"] (stringtable refs; empty = no name)
// - classic geometry: counts boost_remove / boost_add game objects (9e); the "load" count runs
//   during script load, before _gameobjects::main() deletes the boost_add entities
// - killstreak test: set mwx_debug_ks 1 (UAV) or 2 (Attack Helicopter) to grant the hardpoint
//   through the normal _hardpoints path (path check included), 3 = both

init()
{
	if (!getdvarint("mwx_debug_gamemodes"))
		return;

	level thread mwx_aw_debug_reports();
	level thread mwx_aw_debug_killstreaks();
	level thread mwx_aw_debug_commands();
}

mwx_aw_debug_commands()
{
	level endon("game_ended");

	for (;;)
	{
		wait 0.5;

		// mwx_debug_report 1: dump every player's team, weapons and scavenger perk
		if (getdvarint("mwx_debug_report") == 1)
		{
			setdvar("mwx_debug_report", "0");
			foreach (p in level.players)
			{
				if (!isdefined(p))
					continue;
				weapons = "";
				foreach (w in p getweaponslistall())
					weapons = weapons + " " + w;
				scav = 0;
				if (p maps\mp\_utility::_hasperk("specialty_scavenger"))
					scav = 1;
				print("[aw-debug] player " + p.name + " team=" + p.pers["team"] + " scavenger=" + scav + " weapons=" + weapons);
			}
		}

		// mwx_debug_report 2: count scavenger bags in the world
		if (getdvarint("mwx_debug_report") == 2)
		{
			setdvar("mwx_debug_report", "0");
			bags = 0;
			bagorigin = "";
			foreach (e in getentarray())
			{
				if (!isdefined(e.classname) || e.classname != "script_model")
					continue;
				m = e.model;
				if (isdefined(m) && issubstr(m, "scavenger"))
				{
					bags++;
					if (bagorigin == "")
						bagorigin = e.origin;
				}
			}
			print("[aw-debug] scavenger bags=" + bags + " first=" + bagorigin);
		}

		// mwx_debug_kill <playernum>: player 0 deals lethal damage (kill credit for scavenger tests)
		if (getdvar("mwx_debug_kill") != "")
		{
			num = getdvarint("mwx_debug_kill");
			setdvar("mwx_debug_kill", "");
			if (isdefined(level.players) && level.players.size > num && num > 0 && isdefined(level.players[0]))
			{
				victim = level.players[num];
				attacker = level.players[0];
				if (isdefined(victim))
				{
					print("[aw-debug] kill player " + num + " (" + victim.name + ") by " + attacker.name);
					victim dodamage(1000, victim.origin, attacker, attacker);
				}
			}
		}
	}
}

mwx_aw_debug_reports()
{
	wait 0.05;
	mwx_aw_debug_count("load");
	wait 5;
	mwx_aw_debug_count("after5");

	allies = "";
	axis = "";
	if (isdefined(game["allies"]))
		allies = game["allies"];
	if (isdefined(game["axis"]))
		axis = game["axis"];
	haspaths = 0;
	if (isdefined(level.heli_start_nodes) && level.heli_start_nodes.size > 0)
		haspaths = 1;
	print("[aw-debug] factions map=" + getdvar("mapname") + " gametype=" + getdvar("g_gametype") + " allies=" + allies + " axis=" + axis);
	print("[aw-debug] high_jump=" + getdvarint("scr_game_high_jump") + " heli_paths=" + haspaths);
}

mwx_aw_debug_count(tag)
{
	count_remove = 0;
	count_add = 0;
	origins = "";
	entities = getentarray();
	foreach (entity in entities)
	{
		if (!isdefined(entity.script_gameobjectname))
			continue;
		name = entity.script_gameobjectname;
		if (issubstr(name, "boost_remove"))
		{
			count_remove++;
			if (count_remove <= 5)
				origins = origins + " [" + entity.origin[0] + "," + entity.origin[1] + "," + entity.origin[2] + "]";
		}
		if (issubstr(name, "boost_add"))
			count_add++;
	}
	borders = 0;
	if (isdefined(getentarray("boost_jump_border", "targetname")))
		borders = getentarray("boost_jump_border", "targetname").size;
	print("[aw-debug] " + tag + " map=" + getdvar("mapname") + " high_jump=" + getdvarint("scr_game_high_jump") + " boost_remove=" + count_remove + " boost_add=" + count_add + " boost_borders=" + borders + " first_remove_origins=" + origins);
}

mwx_aw_debug_killstreaks()
{
	level endon("game_ended");

	for (;;)
	{
		wait 0.5;
		requested = getdvarint("mwx_debug_ks");
		if (!requested)
			continue;

		setdvar("mwx_debug_ks", "0");
		player = undefined;
		if (isdefined(level.players) && level.players.size > 0)
			player = level.players[0];
		if (!isdefined(player))
			continue;

		if (requested == 1 || requested == 3)
		{
			player thread maps\mp\gametypes\_hardpoints::givehardpoint("radar_mp", 3);
			print("[aw-debug] killstreak UAV granted to " + player.name);
		}
		if (requested == 2 || requested == 3)
		{
			player thread maps\mp\gametypes\_hardpoints::givehardpoint("helicopter_mp", 7);
			haspaths = 0;
			if (isdefined(level.heli_start_nodes) && level.heli_start_nodes.size > 0)
				haspaths = 1;
			print("[aw-debug] killstreak helicopter granted to " + player.name + " heli_paths=" + haspaths);
		}
		if (requested == 4)
		{
			used = player maps\mp\gametypes\_hardpoints::triggerhardpoint();
			usedint = 0;
			if (used)
				usedint = 1;
			print("[aw-debug] triggerhardpoint returned " + usedint);
		}
	}
}

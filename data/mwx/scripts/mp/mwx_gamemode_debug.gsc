init()
{
	if (getdvarint("mwx_debug_gamemodes"))
	{
		level thread report();
	}
}

report()
{
	wait 5;
	print("[gamemodes] level.gametype=" + level.gametype + " g_gametype=" + getdvar("g_gametype") + " hodgepodge=" + level.hodgepodgemode);
}

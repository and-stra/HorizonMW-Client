// MWX: fixes for the MWR "hodgepodge" party modes in private matches.
// Slasher (hodgepodge 2), which MWR only ran from a playlist:
// - one life: initmmmode sets scr_war_numLives 1 in onstartgametype, after war.gsc already read the
//   private match rules (unlimited lives). Survivors respawned, the survivor count never reached 0, the
//   match never ended and the "final survivor" slasher powers went to several players.
// - match end: the team counters are only counted up on spawn and down on kills, so any extra spawn
//   (respawn, the slasher's class change) left them too high and "all survivors dead" was never
//   detected. The kill handler now recounts the living players of each team.
// - survivor bots: MWR disables firing for all bots (allowfire 0) and makes them flee while the slasher
//   looks at them. Survivor bots may now shoot, and flee only while the slasher is still far away.

#define SLASHER_FIGHT_DIST 600

main()
{
    replacefunc(maps\mp\gametypes\_hodgepodge::botslasheristargetingme, ::botslasheristargetingme_stub);
    replacefunc(maps\mp\gametypes\_hodgepodge::onmmplayerkilled, ::onmmplayerkilled_stub);
}

init()
{
    if (!isdefined(level.hodgepodgemode) || level.hodgepodgemode != 2)
        return;

    level.numlives = 1;
    setdynamicdvar("scr_war_numlives", 1);
    level thread slasher_onconnect();
}

slasher_onconnect()
{
    for (;;)
    {
        level waittill("connected", player);
        if (isai(player))
            player thread slasher_botfire();
    }
}

slasher_botfire()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");
        // onmmspawnplayer ran allowfire(0) for every bot
        waittillframeend;
        if (self.team == "allies")
            self allowfire(1);
    }
}

botslasheristargetingme_stub()
{
    if (!isdefined(level.slasher))
        return 0;

    if (distance(level.slasher.origin, self.origin) < SLASHER_FIGHT_DIST)
    {
        // botmmlogic only clears ignoreall on its 30 s hide timer
        self.ignoreall = 0;
        return 0;
    }

    if (isai(level.slasher))
        return isdefined(level.slasher.enemy) && level.slasher.enemy == self && level.slasher botcanseeentity(self);

    return common_scripts\utility::within_fov(level.slasher geteye(), level.slasher getplayerangles(), self geteye(), 0.422618) && sighttracepassed(level.slasher geteye(), self geteye(), 0, self);
}

alive_on_team(team, ignore)
{
    count = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player) || player == ignore || player.team != team)
            continue;
        if (maps\mp\_utility::isreallyalive(player))
            count++;
    }
    return count;
}

onmmplayerkilled_stub(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, timeoffset, deathanimduration, killid)
{
    if (!isdefined(attacker))
        return;

    if ((attacker == self || !isplayer(attacker)) && !level.mm_allowsuicide)
        return;

    level notify("update_game_time");
    level.mm_teamscores["allies"] = alive_on_team("allies", self);
    level.mm_teamscores["axis"] = alive_on_team("axis", self);
    maps\mp\gametypes\_hodgepodge::updateteamscores();

    if (self.team == "allies")
    {
        maps\mp\_utility::playsoundonplayers("mp_enemy_obj_captured", "allies");
        maps\mp\_utility::playsoundonplayers("mp_war_objective_taken", "axis");
    }

    level thread maps\mp\_utility::teamplayercardsplash("callout_eliminated", self, self.team);

    if (level.mm_teamscores["allies"] == 0)
    {
        maps\mp\gametypes\_hodgepodge::onsurvivorseliminated();
        return;
    }

    if (level.mm_teamscores["axis"] == 0)
    {
        maps\mp\gametypes\_hodgepodge::onslashereliminated();
        return;
    }

    if (level.mm_teamscores["allies"] == 1)
        maps\mp\gametypes\_hodgepodge::onfinalsurvivor();
}

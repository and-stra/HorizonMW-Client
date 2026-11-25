// MWX: Arena for H1/HMW.
//
// Port of IW4 arena.gsc (refs: COD-GSC-Source/IW4-GSC/maps/mp/gametypes/arena.gsc) to H1: team
// deathmatch with rounds and one life per round. A neutral flag appears when the round timer runs
// low (scr_arena_flagtime seconds after the start, 60 default) or when a team is down to one player;
// capturing it (3 s hold) wins the round. Eliminating the enemy team also wins the round. First team
// with scr_arena_winlimit round wins takes the match.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

#define AR_TIMELIMIT 5
#define AR_WINLIMIT 3
#define AR_CAPTURETIME 3
#define AR_RADIUS 170
#define AR_FLAGTIME 60

main()
{
    if (getdvar("mapname") == "mp_background")
        return;

    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::setupcallbacks();
    maps\mp\gametypes\_globallogic::setupcallbacks();

    if (isusingmatchrulesdata())
    {
        level.initializematchrules = ::initializematchrules;
        [[level.initializematchrules]]();
        level thread maps\mp\_utility::reinitializematchrulesonmigration();
    }
    else
    {
        maps\mp\_utility::registertimelimitdvar(level.gametype, AR_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 0);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, AR_WINLIMIT);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar("scr_" + level.gametype + "_numlives", 1);
    maps\mp\_utility::registernumlivesdvar(level.gametype, 1);

    level.ar_flagtime = getdvarfloat("scr_arena_flagtime", AR_FLAGTIME);
    if (level.ar_flagtime <= 0)
        level.ar_flagtime = AR_FLAGTIME;

    level.teambased = 1;
    level.objectivebased = 1;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.blockweapondrops = 0;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.ondeadevent = ::ondeadevent;
    level.onplayerkilled = ::onplayerkilled;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "arena";
    game["strings"]["overtime_hint"] = &"MP_FIRST_BLOOD";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_arena_timelimit", AR_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("arena", AR_TIMELIMIT);
    setdynamicdvar("scr_arena_winlimit", AR_WINLIMIT);
    maps\mp\_utility::registerwinlimitdvar("arena", AR_WINLIMIT);
    setdynamicdvar("scr_arena_roundlimit", 0);
    maps\mp\_utility::registerroundlimitdvar("arena", 0);
    setdynamicdvar("scr_arena_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("arena", 0);
    setdynamicdvar("scr_arena_numlives", 1);
    maps\mp\_utility::registernumlivesdvar("arena", 1);
    setdynamicdvar("scr_game_hardpoints", 0);
    maps\mp\_utility::setoverridewatchdvar("scorelimit", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    if (!isdefined(game["switchedsides"]))
        game["switchedsides"] = 0;

    if (game["switchedsides"])
    {
        oldattackers = game["attackers"];
        game["attackers"] = game["defenders"];
        game["defenders"] = oldattackers;
    }

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_ARENA");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_ARENA");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_ARENA");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_ARENA");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_ARENA_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_ARENA_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_ARENA_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_ARENA_HINT");

    initspawns();
    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level.ar_flagorigin = level.mapcenter + (0, 0, 16);
    precachemodel("h1_flag_mp_domination_default");

    level thread arenaflagtimer();
    level thread arenadownwatch();
    level thread arroundwatch();
}

// elimination round end that does not depend on updategameevents after the grace period
arroundwatch()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    for (;;)
    {
        wait 1;

        if (maps\mp\_utility::is_true(level.gameending) || level.ingraceperiod)
            continue;
        if (!isdefined(level.hasspawned) || level.hasspawned["allies"] + level.hasspawned["axis"] < 2)
            continue;

        if (level.alivecount["allies"] <= 0 && level.livescount["allies"] <= 0)
        {
            level thread arendround("axis");
            return;
        }

        if (level.alivecount["axis"] <= 0 && level.livescount["axis"] <= 0)
        {
            level thread arendround("allies");
            return;
        }
    }
}

initspawns()
{
    level.spawnmins = (0, 0, 0);
    level.spawnmaxs = (0, 0, 0);
    maps\mp\gametypes\_spawnlogic::addstartspawnpoints("mp_tdm_spawn_allies_start");
    maps\mp\gametypes\_spawnlogic::addstartspawnpoints("mp_tdm_spawn_axis_start");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("allies", "mp_tdm_spawn");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("axis", "mp_tdm_spawn");
    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter(level.spawnmins, level.spawnmaxs);
    setmapcenter(level.mapcenter);
}

getspawnpoint()
{
    if (game["switchedsides"])
        team = maps\mp\_utility::getotherteam(self.pers["team"]);
    else
        team = self.pers["team"];

    if (level.ingraceperiod)
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getspawnpointarray("mp_tdm_spawn_" + team + "_start");
        spawnpoint = maps\mp\gametypes\_spawnlogic::getspawnpoint_random(spawnpoints);
    }
    else
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getteamspawnpoints(team);
        spawnpoint = maps\mp\gametypes\_spawnscoring::getspawnpoint_awayfromenemies(spawnpoints, team);
    }

    maps\mp\gametypes\_spawnlogic::recon_set_spawnpoint(spawnpoint);
    return spawnpoint;
}

onspawnplayer()
{
    self thread arspawnfinished();
}

arspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");
}

// --- flag ---------------------------------------------------------------------------------

arenaflagtimer()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    wait level.ar_flagtime;

    if (!isdefined(level.ar_spawned))
        level thread spawnarenaflag();
}

arenadownwatch()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    for (;;)
    {
        wait 1;

        if (isdefined(level.ar_spawned))
            return;

        allies = 0;
        axis = 0;

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (player.team == "allies")
                allies++;
            else if (player.team == "axis")
                axis++;
        }

        if ((allies == 1 && axis > 0) || (axis == 1 && allies > 0))
        {
            level thread spawnarenaflag();
            return;
        }
    }
}

spawnarenaflag()
{
    level endon("game_ended");

    if (isdefined(level.ar_spawned))
        return;

    level.ar_spawned = 1;
    level.ar_flag = spawn("script_model", level.ar_flagorigin);
    level.ar_flag setmodel("h1_flag_mp_domination_default");
    level.ar_flag.angles = (0, 0, 0);
    level.ar_owner = "neutral";
    level.ar_progress = 0;
    level.ar_team = "none";

    iPrintLnBold(&"MWX_ARENA_FLAG_SPAWNED");
    level thread arenaflagwatcher();

    // the stock arena HUD string, if the build has it
    level thread arenasplash();
}

arenasplash()
{
    maps\mp\_utility::playsoundonplayers("mp_war_objective_taken", "allies");
    maps\mp\_utility::playsoundonplayers("mp_war_objective_taken", "axis");
}

arenaflagwatcher()
{
    level endon("game_ended");

    for (;;)
    {
        wait 0.5;

        if (!isdefined(level.ar_flag))
            return;

        allies = 0;
        axis = 0;

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (distancesquared(player.origin, level.ar_flagorigin) > AR_RADIUS * AR_RADIUS)
                continue;

            if (player.team == "allies")
                allies++;
            else if (player.team == "axis")
                axis++;
        }

        contesting = "none";
        if (allies > 0 && axis == 0)
            contesting = "allies";
        else if (axis > 0 && allies == 0)
            contesting = "axis";

        if (contesting == "none")
        {
            level.ar_progress = 0;
            level.ar_team = "none";
            continue;
        }

        if (level.ar_team != contesting)
        {
            level.ar_team = contesting;
            level.ar_progress = 0;
        }

        level.ar_progress = level.ar_progress + 0.5;

        if (level.ar_progress >= AR_CAPTURETIME)
        {
            level thread arenacaptured(contesting);
            return;
        }
    }
}

arenacaptured(team)
{
    level endon("game_ended");

    if (maps\mp\_utility::is_true(level.gameending))
        return;

    level.ar_owner = team;
    level.finalkillcam_winner = team;

    maps\mp\_utility::playsoundonplayers("mp_enemy_obj_captured", team);

    level thread arendround(team);
}

// test hook: spawn the flag without waiting for the clock
mwxarenaspawnflag()
{
    level thread spawnarenaflag();
}

// --- round end ----------------------------------------------------------------------------

ondeadevent(team)
{
    if (maps\mp\_utility::is_true(level.gameending))
        return;

    level.gameending = 1;

    if (team == game["attackers"])
        winner = game["defenders"];
    else if (team == game["defenders"])
        winner = game["attackers"];
    else
        winner = "allies";

    level.finalkillcam_winner = winner;
    level thread arendround(winner);
}

arendround(winner)
{
    level endon("game_ended");

    if (maps\mp\_utility::is_true(level.gameending))
        return;

    level.gameending = 1;
    level.finalkillcam_winner = winner;

    maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(2);

    lossteam = "allies";
    if (winner == "allies")
        lossteam = "axis";

    thread maps\mp\gametypes\_gamelogic::endgame(winner, game["end_reason"][lossteam + "_eliminated"]);
}

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, killid)
{
    level notify("player_eliminated", self);
}

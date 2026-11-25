// MWX: Reinforce for H1/HMW.
//
// Port of the IW6 siege.gsc idea (refs: COD-GSC-Source/IW6-GSC/maps/mp/gametypes/siege.gsc) to H1:
// team deathmatch with rounds, one life per round and a neutral capture point. Capturing the point
// respawns every dead teammate of the capturing team; eliminating the enemy team wins the round.
// First team with scr_reinforce_winlimit round wins takes the match. The flag is a scripted
// capture zone in the map center (dom's h1_flag_mp_domination_default model), with the stock TDM HUD.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

#define RF_TIMELIMIT 5
#define RF_WINLIMIT 3
#define RF_CAPTURETIME 3
#define RF_RADIUS 170

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, RF_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 0);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, RF_WINLIMIT);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0);
    // one life per round; the watched dvar is read by registernumlivesdvar
    setdynamicdvar("scr_" + level.gametype + "_numlives", 1);
    maps\mp\_utility::registernumlivesdvar(level.gametype, 1);

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

    game["dialog"]["gametype"] = "team_deathmtch";
    game["strings"]["overtime_hint"] = &"MP_FIRST_BLOOD";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_reinforce_timelimit", RF_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("reinforce", RF_TIMELIMIT);
    setdynamicdvar("scr_reinforce_winlimit", RF_WINLIMIT);
    maps\mp\_utility::registerwinlimitdvar("reinforce", RF_WINLIMIT);
    setdynamicdvar("scr_reinforce_roundlimit", 0);
    maps\mp\_utility::registerroundlimitdvar("reinforce", 0);
    setdynamicdvar("scr_reinforce_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("reinforce", 0);
    setdynamicdvar("scr_reinforce_numlives", 1);
    maps\mp\_utility::registernumlivesdvar("reinforce", 1);
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

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_REINFORCE");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_REINFORCE");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_REINFORCE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_REINFORCE");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_REINFORCE_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_REINFORCE_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_REINFORCE_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_REINFORCE_HINT");

    initspawns();
    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level.rf_flagorigin = level.mapcenter + (0, 0, 16);
    precachemodel("h1_flag_mp_domination_default");

    level thread createflag();
    level thread flagwatcher();
    level thread rfroundwatch();
}

// Round end by elimination. H1's updategameevents skips death events during the grace period and is
// only re-run on the next death, so a round whose last death happens there would never end; this
// watch waits for the grace period and then ends the round itself.
rfroundwatch()
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
            level thread rfendround("axis");
            return;
        }

        if (level.alivecount["axis"] <= 0 && level.livescount["axis"] <= 0)
        {
            level thread rfendround("allies");
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
    self thread rfspawnfinished();
}

rfspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");
}

// --- capture point ------------------------------------------------------------------------

createflag()
{
    level endon("game_ended");

    level.rf_flag = spawn("script_model", level.rf_flagorigin);
    level.rf_flag setmodel("h1_flag_mp_domination_default");
    level.rf_flag.angles = (0, 0, 0);
    level.rf_owner = "neutral";
    level.rf_progress = 0;
    level.rf_team = "none";
    level.rf_active = 1;
}

flagwatcher()
{
    level endon("game_ended");

    for (;;)
    {
        wait 0.5;

        if (!isdefined(level.rf_active) || !level.rf_active || !isdefined(level.rf_flag))
            continue;

        allies = 0;
        axis = 0;

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (distancesquared(player.origin, level.rf_flagorigin) > RF_RADIUS * RF_RADIUS)
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

        if (contesting == "none" || contesting == level.rf_owner)
        {
            level.rf_progress = 0;
            level.rf_team = "none";
            continue;
        }

        if (level.rf_team != contesting)
        {
            level.rf_team = contesting;
            level.rf_progress = 0;
        }

        level.rf_progress = level.rf_progress + 0.5;

        if (level.rf_progress >= RF_CAPTURETIME)
        {
            level.rf_progress = 0;
            level.rf_team = "none";
            level thread captured(contesting);
        }
    }
}

captured(team)
{
    level endon("game_ended");

    if (maps\mp\_utility::is_true(level.gameended))
        return;

    level.rf_owner = team;
    level.rf_active = 0;

    maps\mp\_utility::playsoundonplayers("mp_enemy_obj_captured", team);

    // Reinforce: a capture brings the team's dead players back
    level thread respawnteam(team);

    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != team)
            continue;
        player playlocalsound("mp_war_objective_taken");
    }

    wait 2;

    // re-arm the point after a short pause
    if (!maps\mp\_utility::is_true(level.gameended))
    {
        level.rf_owner = "neutral";
        level.rf_active = 1;
    }
}

respawnteam(team)
{
    level endon("game_ended");

    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != team)
            continue;
        if (isalive(player))
            continue;

        player thread rfrespawn();
    }
}

rfrespawn()
{
    self endon("disconnect");

    self maps\mp\gametypes\_playerlogic::incrementalivecount(self.team);
    self.alreadyaddedtoalivecount = 1;
    self.pers["lives"] = 1;
    maps\mp\gametypes\_playerlogic::spawnclient();
}

// test hook: the test cannot capture the zone with bots, so it calls the consequence directly
mwxreinforcecapture(team)
{
    level thread captured(team);
}

// --- round end ----------------------------------------------------------------------------

ondeadevent(team)
{

    if (maps\mp\_utility::is_true(level.gameending))
        return;

    if (team == game["attackers"])
        winner = game["defenders"];
    else if (team == game["defenders"])
        winner = game["attackers"];
    else
        winner = "allies";

    level thread rfendround(winner);
}

rfendround(winner)
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

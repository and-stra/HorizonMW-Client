// MWX: Survival prototype (R6c). NOT a full port - a feasibility spike for docs/survival-spike.md.
//
// Hidden party mode (only in the Party list when mwx_show_survival is 1). One or two players on
// mp_crash hold out against waves of H1's humanoid agents (maps\mp\agents\_agents.gsc, the framework
// HMW ships for zombie/agent modes):
//   wave 1 = 5 agents on team axis with the "class1" loadout, next wave 5 s after the last one dies,
//   wave counter on the server HUD. The match ends when every player is dead (one life each).
//
// The agents use H1's own spawn path (add_humanoid_agent -> spawn_agent_player -> bot_war_think), so
// movement, shooting, damage and kill attribution are the engine's.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

#define SURVIVAL_WAVE1 5
#define SURVIVAL_INTERMISSION 5

main()
{
    if (getdvar("mapname") == "mp_background")
        return;

    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::setupcallbacks();
    maps\mp\gametypes\_globallogic::setupcallbacks();

    maps\mp\_utility::registertimelimitdvar(level.gametype, 0);
    maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
    maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
    maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
    maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar("scr_" + level.gametype + "_numlives", 1);
    maps\mp\_utility::registernumlivesdvar(level.gametype, 1);

    level.teambased = 1;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.allowlatecomers = 1;
    level.autoassign = ::survivalautoassign;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.ondeadevent = ::ondeadevent;
    level.onplayerkilled = ::onplayerkilled;

    game["dialog"]["gametype"] = "team_deathmtch";
}

onstartgametype()
{
    setclientnamemode("auto_change");
    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_SURVIVAL");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_SURVIVAL");
    maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SURVIVAL_SCORE");
    maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SURVIVAL_SCORE");
    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_SURVIVAL_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_SURVIVAL_HINT");

    initspawns();
    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    // H1's agent framework (callbacks + agent slots); in MP its main() returns after setup
    maps\mp\agents\_agents::main();

    level.survival_wave = 0;
    level.survival_agents = [];
    level thread survivalhud();
    level thread wavemanager();
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
    team = self.pers["team"];
    if (!isdefined(team) || team == "axis")
        team = "axis";
    else
        team = "allies";

    if (level.ingraceperiod)
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getspawnpointarray("mp_tdm_spawn_" + team + "_start");
        spawnpoint = maps\mp\gametypes\_spawnlogic::getspawnpoint_random(spawnpoints);
    }
    else
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getteamspawnpoints(team);
        if (team == "axis")
            spawnpoint = maps\mp\gametypes\_spawnlogic::getspawnpoint_random(spawnpoints);
        else
            spawnpoint = maps\mp\gametypes\_spawnscoring::getspawnpoint_awayfromenemies(spawnpoints, team);
    }

    maps\mp\gametypes\_spawnlogic::recon_set_spawnpoint(spawnpoint);
    return spawnpoint;
}

onspawnplayer()
{
    if (isai(self))
        return;

    self thread survivalplayerspawn();
}

// human players defend as allies; AI (wave enemies) spawn on axis
survivalautoassign()
{
    if (isai(self))
    {
        thread maps\mp\gametypes\_menus::setteam("axis");
        return;
    }

    thread maps\mp\gametypes\_menus::setteam("allies");
    self.survival_player = 1;
}

survivalplayerspawn()
{
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");
}

// --- waves ---------------------------------------------------------------------------------

wavemanager()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    for (;;)
    {
        level.survival_wave++;
        level notify("survival_wave_started", level.survival_wave);
        spawnwave();
        logprint("mwx survival: wave " + level.survival_wave + " spawned, alive=" + aliveagents() +
            " fallback=" + isdefined(level.survival_fallback_bots));

        // let the wave spawn (engine bots join over the next frames)
        wait 3;

        for (;;)
        {
            wait 1;

            if (aliveagents() <= 0)
                break;
        }

        level notify("survival_wave_cleared", level.survival_wave);
        level.survival_cleared = level.survival_wave;
        logprint("mwx survival: wave " + level.survival_wave + " cleared");
        wait SURVIVAL_INTERMISSION;
    }
}

spawnwave()
{
    count = SURVIVAL_WAVE1 + (level.survival_wave - 1) * 2;
    level.survival_agents = [];

    // H1's agent framework: on HMW-MP getmaxagents() is 0 (the engine never allocates agent slots
    // in a multiplayer match), so add_humanoid_agent returns undefined. Fall back to engine bots
    // (SV_AddBot through the MWX executecommand builtin) so the wave structure is testable; see
    // docs/survival-spike.md.
    for (index = 0; index < count; index++)
    {
        agent = maps\mp\agents\_agents::add_humanoid_agent("player", "axis", "class1");
        if (isdefined(agent))
        {
            agent.survival_agent = 1;
            level.survival_agents[level.survival_agents.size] = agent;
        }
    }

    if (level.survival_agents.size < count)
    {
        missing = count - level.survival_agents.size;
        level.survival_fallback_bots = 1;
        executecommand("spawnBot " + missing);
    }
}

aliveagents()
{
    count = 0;

    foreach (player in level.players)
    {
        if (!isdefined(player) || !isai(player))
            continue;
        if (!isdefined(player.team) || player.team != "axis")
            continue;
        if (!isalive(player))
            continue;
        count++;
    }

    return count;
}

// --- HUD / round end -----------------------------------------------------------------------

survivalhud()
{
    level endon("game_ended");

    level.survival_hud = maps\mp\gametypes\_hud_util::createserverfontstring("objective", 1.2);
    level.survival_hud.label = &"MWX_SURVIVAL_WAVE";
    level.survival_hud maps\mp\gametypes\_hud_util::setpoint("TOPCENTER", "TOPCENTER", 0, 26);
    level.survival_hud.archived = 1;
    level.survival_hud.hidewheninmenu = 0;
    level.survival_hud.glowalpha = 0.5;
    level.survival_hud.alpha = 1;

    for (;;)
    {
        level.survival_hud setvalue(level.survival_wave);
        wait 1;
    }
}

ondeadevent(team)
{
    if (maps\mp\_utility::is_true(level.gameended) || level.gameending)
        return;

    if (team == "allies" || team == "all")
    {
        // all human players are out: the wave won
        level.gameending = 1;
        level.finalkillcam_winner = "axis";
        level thread survivalend();
    }
}

survivalend()
{
    level endon("game_ended");
    maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(2);
    thread maps\mp\gametypes\_gamelogic::endgame("axis", game["end_reason"]["time_limit_reached"]);
}

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, killid)
{
    level notify("player_eliminated", self);
}

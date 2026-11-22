// MWX: Infected for H1/HMW.
// Port of the AW/S1 infect.gsc (COD-GSC-Source/S1X-GSC/maps/mp/gametypes/infect.gsc) to H1 + HMW:
// exo abilities, adrenaline, extra health, battery and hazmat models removed; H1 has no infected
// events in maps\mp\_events, so they are implemented below with H1 functions; HMW weapon names.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

#define FIRST_INFECTED_TIMER 15
#define INFECTED_MOVE_SCALAR 1.2

// HMW weapons (MW3-style Infected)
#define SURVIVOR_PRIMARY "h2_spas12"
#define SURVIVOR_SECONDARY "h2_usp"
#define SURVIVOR_LETHAL "h1_fraggrenade_mp"
#define SURVIVOR_TACTICAL "h1_flashgrenade_mp"
#define INFECTED_INITIAL_PRIMARY "h2_usp"
#define INFECTED_PRIMARY "iw5_combatknife"
#define INFECTED_LETHAL "iw9_throwknife_mp"

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
        level thread reinitializematchrulesonmigration();
    }
    else
    {
        registertimelimitdvar(level.gametype, 10);
        setoverridewatchdvar("scorelimit", 0);
        registerroundlimitdvar(level.gametype, 1);
        registerwinlimitdvar(level.gametype, 1);
        registernumlivesdvar(level.gametype, 0);
        registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
    }

    setspecialloadouts();

    level.teambased = 1;
    level.doprematch = 1;
    level.disableforfeit = 1;
    level.nobuddyspawns = 1;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.onplayerkilled = ::onplayerkilled;
    level.ondeadevent = ::ondeadevent;
    level.ontimelimit = ::ontimelimit;
    level.autoassign = ::infectautoassign;
    level.bypassclasschoicefunc = ::infectedclass;

    if (level.matchrules_damagemultiplier)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "inf_intro";
    if (getdvarint("g_hardcore"))
        game["dialog"]["gametype"] = "hc_" + game["dialog"]["gametype"];

    game["dialog"]["offense_obj"] = "inf_survive";
    game["dialog"]["defense_obj"] = "inf_survive";
    game["dialog"]["first_infected"] = "inf_patientzero";
    game["dialog"]["time_extended"] = "inf_extratime";
    game["dialog"]["lone_survivor"] = "inf_lonesurvivor";
    game["dialog"]["been_infected"] = "inf_been_infected";
}

initializematchrules()
{
    setcommonrulesfrommatchrulesdata();

    setdynamicdvar("scr_" + level.gametype + "_numLives", 0);
    registernumlivesdvar(level.gametype, 0);

    setoverridewatchdvar("scorelimit", 0);
    setdynamicdvar("scr_infect_roundswitch", 0);
    registerroundswitchdvar("infect", 0, 0, 9);
    setdynamicdvar("scr_infect_roundlimit", 1);
    registerroundlimitdvar("infect", 1);
    setdynamicdvar("scr_infect_winlimit", 1);
    registerwinlimitdvar("infect", 1);
    setdynamicdvar("scr_infect_halftime", 0);
    registerhalftimedvar("infect", 0);

    setdynamicdvar("scr_infect_playerrespawndelay", 0);
    setdynamicdvar("scr_infect_waverespawndelay", 0);
    setdynamicdvar("scr_player_forcerespawn", 1);
    setdynamicdvar("scr_team_fftype", 0);
    setdynamicdvar("scr_game_hardpoints", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    setobjectivetext("allies", &"OBJECTIVES_INFECT");
    setobjectivetext("axis", &"OBJECTIVES_INFECT");

    if (level.splitscreen)
    {
        setobjectivescoretext("allies", &"OBJECTIVES_INFECT");
        setobjectivescoretext("axis", &"OBJECTIVES_INFECT");
    }
    else
    {
        setobjectivescoretext("allies", &"OBJECTIVES_INFECT_SCORE");
        setobjectivescoretext("axis", &"OBJECTIVES_INFECT_SCORE");
    }

    setobjectivehinttext("allies", &"OBJECTIVES_INFECT_HINT");
    setobjectivehinttext("axis", &"OBJECTIVES_INFECT_HINT");

    initspawns();

    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level.quickmessagetoall = 1;
    level.blockweapondrops = 1;
    level.infect_allowsuicide = 0;

    level.infect_chosefirstinfected = 0;
    level.infect_choosingfirstinfected = 0;
    level.infect_countdowninprogress = 0;

    level.infect_teamscores["axis"] = 0;
    level.infect_teamscores["allies"] = 0;
    level.infect_players = [];

    level thread onplayerconnect();
    level thread gametimer();
}

gametimer()
{
    level endon("game_ended");

    setdynamicdvar("scr_infect_timelimit", 0);
    playtimevo = 0;

    for (;;)
    {
        level waittill("update_game_time", newgametime);

        if (!isdefined(newgametime))
            newgametime = ((gettimepassed() + 1500) / (60 * 1000)) + 2;

        setdynamicdvar("scr_infect_timelimit", newgametime);
        level thread watchhostmigration(newgametime);

        if (playtimevo)
            level thread leaderdialogbothteams("time_extended", "axis", "time_extended", "allies", "status");

        playtimevo = 1;
    }
}

watchhostmigration(newgametime)
{
    level notify("watchHostMigration");
    level endon("watchHostMigration");
    level endon("game_ended");

    level waittill("host_migration_begin");
    setdynamicdvar("scr_infect_timelimit", 0);
    waittillframeend;
    setdynamicdvar("scr_infect_timelimit", 0);
    level waittill("host_migration_end");
    level notify("update_game_time", newgametime);
}

onplayerconnect()
{
    for (;;)
    {
        level waittill("connected", player);

        player.infectedrejoined = 0;
        player.killsasinfected = 0;

        if (gameflag("prematch_done"))
        {
            if (isdefined(level.infect_chosefirstinfected) && level.infect_chosefirstinfected)
                player.survivalstarttime = gettime();
        }

        if (isdefined(level.infect_players[player.name]))
            player.infectedrejoined = 1;

        player thread monitorsurvivaltime();
    }
}

initspawns()
{
    level.spawnmins = (0, 0, 0);
    level.spawnmaxs = (0, 0, 0);

    maps\mp\gametypes\_spawnlogic::addspawnpoints("allies", "mp_tdm_spawn");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("axis", "mp_tdm_spawn");

    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter(level.spawnmins, level.spawnmaxs);
    setmapcenter(level.mapcenter);
}

infectautoassign()
{
    teamchoice = "allies";
    if (self.infectedrejoined)
        teamchoice = "axis";

    self thread maps\mp\gametypes\_menus::setteam(teamchoice);
}

getspawnpoint()
{
    if (level.ingraceperiod)
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getspawnpointarray("mp_tdm_spawn");
        spawnpoint = maps\mp\gametypes\_spawnlogic::getspawnpoint_random(spawnpoints);
    }
    else
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getteamspawnpoints(self.pers["team"]);
        spawnpoint = maps\mp\gametypes\_spawnscoring::getspawnpoint_nearteam(spawnpoints);
    }

    self maps\mp\gametypes\_spawnlogic::recon_set_spawnpoint(spawnpoint);
    return spawnpoint;
}

infectedclass()
{
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "";
    self.pers["gamemodeLoadout"] = level.infect_loadouts[self.pers["team"]];
    self.class = self.pers["class"];
    self.lastclass = self.pers["lastClass"];
}

onspawnplayer()
{
    if (isdefined(self.teamchangedthisframe))
    {
        self.pers["gamemodeLoadout"] = level.infect_loadouts[self.pers["team"]];
        self maps\mp\gametypes\_class::giveloadout(self.team, self.class);
        self thread monitordisconnect();
    }

    self.teamchangedthisframe = undefined;

    updateteamscores();

    if (!level.infect_choosingfirstinfected)
    {
        level.infect_choosingfirstinfected = 1;
        level thread choosefirstinfected();
    }

    if (self.infectedrejoined)
    {
        if (!level.infect_allowsuicide)
        {
            level notify("infect_stopCountdown");
            level.infect_chosefirstinfected = 1;
            level.infect_allowsuicide = 1;

            foreach (player in level.players)
            {
                if (isdefined(player.infect_isbeingchosen))
                    player.infect_isbeingchosen = undefined;
            }
        }

        foreach (player in level.players)
        {
            if (isdefined(player.isinitialinfected))
                player thread setinitialtonormalinfected();
        }

        if (level.infect_teamscores["axis"] == 1)
            self.isinitialinfected = 1;

        self clearsurvivaltime();
    }

    if (isdefined(self.isinitialinfected))
    {
        self.pers["gamemodeLoadout"] = level.infect_loadouts["axis_initial"];
        self maps\mp\gametypes\_class::giveloadout(self.team, self.class);
    }

    self thread onspawnfinished();
    level notify("spawned_player");
}

onspawnfinished()
{
    self endon("death");
    self endon("disconnect");

    self waittill("applyLoadout");
    self updateloadouts();
}

updateloadouts()
{
    if (self.pers["team"] == "axis")
    {
        self thread setinfectedmsg();
        // HMW gives the tactical insertion (flare_mp) through this perk
        self giveperk("specialty_tacticalinsertion", 0);
        self setmovespeedscale(INFECTED_MOVE_SCALAR);
    }
}

setinfectedmsg()
{
    if (!isdefined(self.showninfected) || !self.showninfected)
    {
        self thread gotinfectedevent();
        self playsoundtoplayer("mp_inf_got_infected", self);
        self leaderdialogonplayer("been_infected", "status");
        self.showninfected = 1;
    }
}

choosefirstinfected()
{
    level endon("game_ended");
    level endon("infect_stopCountdown");

    level.infect_allowsuicide = 0;
    gameflagwait("prematch_done");

    level.infect_countdowninprogress = 1;
    maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(1.0);

    counttime = FIRST_INFECTED_TIMER;

    setomnvar("ui_match_countdown_title", 7);
    setomnvar("ui_match_countdown_toggle", 1);

    while (counttime > 0 && !level.gameended)
    {
        counttime--;
        setomnvar("ui_match_countdown", counttime + 1);
        maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(1.0);
    }

    setomnvar("ui_match_countdown", 1);
    setomnvar("ui_match_countdown_title", 0);
    setomnvar("ui_match_countdown_toggle", 0);

    level.infect_countdowninprogress = 0;

    possibleinfected = [];
    ignoredhostplayer = undefined;

    foreach (player in level.players)
    {
        if (matchmakinggame() && level.players.size > 1 && player ishost())
        {
            ignoredhostplayer = player;
            continue;
        }

        if (player.team == "spectator")
            continue;

        if (!player.hasspawned)
            continue;

        possibleinfected[possibleinfected.size] = player;
    }

    if (!possibleinfected.size && isdefined(ignoredhostplayer))
        possibleinfected[possibleinfected.size] = ignoredhostplayer;

    if (!possibleinfected.size)
    {
        // nobody spawned yet: try again once someone spawns
        level.infect_choosingfirstinfected = 0;
        return;
    }

    firstinfectedplayer = possibleinfected[randomint(possibleinfected.size)];
    firstinfectedplayer setfirstinfected(1);

    foreach (player in level.players)
    {
        if (player == firstinfectedplayer)
            continue;

        player.survivalstarttime = gettime();
    }
}

prepareforclasschange()
{
    while (!isreallyalive(self) || self isusingremote())
        wait 0.05;

    if (isdefined(self.iscarrying) && self.iscarrying == 1)
    {
        self notify("force_cancel_placement");
        wait 0.05;
    }

    while (self ismeleeing())
        wait 0.05;

    while (self ismantling())
        wait 0.05;

    while (!self isonground() && !self isonladder())
        wait 0.05;

    if (self isjuggernaut())
    {
        self notify("lost_juggernaut");
        wait 0.05;
    }

    wait 0.05;

    while (!isreallyalive(self))
        wait 0.05;
}

setfirstinfected(waschosen)
{
    self endon("disconnect");

    self prepareforclasschange();

    if (waschosen)
    {
        self.infect_isbeingchosen = 1;
        self maps\mp\gametypes\_menus::addtoteam("axis", undefined, 1);
        self thread monitordisconnect();
        level.infect_chosefirstinfected = 1;
        self.infect_isbeingchosen = undefined;

        level notify("update_game_time");
        updateteamscores();

        level.infect_allowsuicide = 1;
        level.infect_players[self.name] = 1;
    }

    self.isinitialinfected = 1;
    self.showninfected = 1;

    self notify("faux_spawn");
    self.pers["gamemodeLoadout"] = level.infect_loadouts["axis_initial"];
    self giveandapplyloadout(self.team, "gamemode");
    self updateloadouts();

    self thread firstinfectedevent();
    self playsoundtoplayer("mp_inf_got_infected", self);
    self leaderdialogonplayer("first_infected", "status");

    self clearsurvivaltime();
}

setinitialtonormalinfected()
{
    level endon("game_ended");

    self.isinitialinfected = undefined;
    self prepareforclasschange();

    self notify("faux_spawn");
    self.pers["gamemodeLoadout"] = level.infect_loadouts["axis"];
    self thread onspawnfinished();
    self giveandapplyloadout(self.team, "gamemode");
}

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, lifeid)
{
    if (!isdefined(attacker))
        return;

    if (self.team == "axis")
        return;

    wassuicide = (attacker == self) || !isplayer(attacker);

    if (wassuicide && !level.infect_allowsuicide)
        return;

    level notify("update_game_time");

    self.teamchangedthisframe = 1;
    self maps\mp\gametypes\_menus::addtoteam("axis");
    self setsurvivaltime(1);

    updateteamscores();
    playsoundonplayers("mp_enemy_obj_captured", "allies");
    playsoundonplayers("mp_war_objective_taken", "axis");

    level.infect_players[self.name] = 1;
    level thread teamplayercardsplash("callout_got_infected", self, "allies");

    if (!wassuicide)
    {
        attacker thread infectedsurvivorevent();
        attacker playsoundtoplayer("mp_inf_infection_kill", attacker);
        attacker.killsasinfected++;

        if (attacker.killsasinfected == 3)
        {
            attacker thread plagueevent();
            attacker.killsasinfected = 0;
        }
    }

    if (level.infect_teamscores["axis"] == 2)
    {
        foreach (player in level.players)
        {
            if (isdefined(player.isinitialinfected))
                player thread setinitialtonormalinfected();
        }
    }

    if (level.infect_teamscores["allies"] == 0)
    {
        onsurvivorseliminated();
        return;
    }

    if (level.infect_teamscores["allies"] == 1)
    {
        onfinalsurvivor();
        return;
    }
}

onfinalsurvivor()
{
    foreach (player in level.players)
    {
        if (!isdefined(player))
            continue;

        if (player.team != "allies")
            continue;

        if (isdefined(player.awardedfinalsurvivor))
            continue;

        player.awardedfinalsurvivor = 1;
        player thread finalsurvivorevent();
        player thread leaderdialogonplayer("lone_survivor", "status");
        level thread finalsurvivoruav(player);
        break;
    }
}

finalsurvivoruav(finalplayer)
{
    level endon("game_ended");
    finalplayer endon("disconnect");
    finalplayer endon("eliminated");
    level endon("infect_lateJoiner");
    level thread enduavonlatejoiner(finalplayer);

    removeuav = 0;
    level.radarmode["axis"] = "normal_radar";

    foreach (player in level.players)
    {
        if (player.team == "axis")
            player.radarmode = "normal_radar";
    }

    setteamradarstrength("axis", 1);

    for (;;)
    {
        prevpos = finalplayer.origin;

        wait 4;
        if (removeuav)
        {
            setteamradar("axis", 0);
            removeuav = 0;
        }

        wait 6;
        if (distance(prevpos, finalplayer.origin) < 200)
        {
            setteamradar("axis", 1);
            removeuav = 1;
        }
    }
}

enduavonlatejoiner(finalplayer)
{
    level endon("game_ended");
    finalplayer endon("disconnect");
    finalplayer endon("eliminated");

    for (;;)
    {
        if (level.infect_teamscores["allies"] > 1)
        {
            level notify("infect_lateJoiner");
            wait 0.05;
            setteamradar("axis", 0);
            break;
        }

        wait 0.05;
    }
}

monitordisconnect()
{
    level endon("game_ended");
    self endon("eliminated");

    self notify("infect_monitor_disconnect");
    self endon("infect_monitor_disconnect");

    team = self.team;
    if (!isdefined(team) && isdefined(self.bot_team))
        team = self.bot_team;

    self waittill("disconnect");

    updateteamscores();

    if (isdefined(self.infect_isbeingchosen) || level.infect_chosefirstinfected)
    {
        if (level.infect_teamscores["axis"] && level.infect_teamscores["allies"])
        {
            if (team == "allies" && level.infect_teamscores["allies"] == 1)
            {
                onfinalsurvivor();
            }
            else if (team == "axis" && level.infect_teamscores["axis"] == 1)
            {
                foreach (player in level.players)
                {
                    if (player != self && player.team == "axis")
                        player setfirstinfected(0);
                }
            }
        }
        else if (level.infect_teamscores["allies"] == 0)
        {
            onsurvivorseliminated();
        }
        else if (level.infect_teamscores["axis"] == 0)
        {
            if (level.infect_teamscores["allies"] == 1)
            {
                level.finalkillcam_winner = "allies";
                level thread maps\mp\gametypes\_gamelogic::endgame("allies", game["end_reason"]["infected_eliminated"]);
            }
            else if (level.infect_teamscores["allies"] > 1)
            {
                level.infect_chosefirstinfected = 0;
                level thread choosefirstinfected();
            }
        }
    }
    else if (level.infect_countdowninprogress && level.infect_teamscores["allies"] == 0 && level.infect_teamscores["axis"] == 0)
    {
        level notify("infect_stopCountdown");
        level.infect_choosingfirstinfected = 0;
        setomnvar("ui_match_countdown_toggle", 0);
    }

    self.isinitialinfected = undefined;
}

ondeadevent(team)
{
}

ontimelimit()
{
    level.finalkillcam_winner = "allies";
    level thread maps\mp\gametypes\_gamelogic::endgame("allies", game["end_reason"]["time_limit_reached"]);
}

onsurvivorseliminated()
{
    level.finalkillcam_winner = "axis";
    level thread maps\mp\gametypes\_gamelogic::endgame("axis", game["end_reason"]["survivors_eliminated"]);
}

getteamsize(team)
{
    size = 0;

    foreach (player in level.players)
    {
        if (player.sessionstate == "spectator" && !player.spectatekillcam)
            continue;

        if (player.team == team)
            size++;
    }

    return size;
}

updateteamscores()
{
    level.infect_teamscores["allies"] = getteamsize("allies");
    game["teamScores"]["allies"] = level.infect_teamscores["allies"];
    setteamscore("allies", level.infect_teamscores["allies"]);

    level.infect_teamscores["axis"] = getteamsize("axis");
    game["teamScores"]["axis"] = level.infect_teamscores["axis"];
    setteamscore("axis", level.infect_teamscores["axis"]);
}

setspecialloadouts()
{
    // fixed classic loadouts (no match rules classes)
    level.infect_loadouts["allies"] = maps\mp\gametypes\_class::getemptyloadout();
    level.infect_loadouts["allies"]["loadoutPrimary"] = SURVIVOR_PRIMARY;
    level.infect_loadouts["allies"]["loadoutSecondary"] = SURVIVOR_SECONDARY;
    level.infect_loadouts["allies"]["loadoutEquipment"] = SURVIVOR_LETHAL;
    level.infect_loadouts["allies"]["loadoutOffhand"] = SURVIVOR_TACTICAL;

    level.infect_loadouts["axis_initial"] = maps\mp\gametypes\_class::getemptyloadout();
    level.infect_loadouts["axis_initial"]["loadoutPrimary"] = INFECTED_INITIAL_PRIMARY;
    level.infect_loadouts["axis_initial"]["loadoutEquipment"] = INFECTED_LETHAL;

    level.infect_loadouts["axis"] = maps\mp\gametypes\_class::getemptyloadout();
    level.infect_loadouts["axis"]["loadoutPrimary"] = INFECTED_PRIMARY;
    level.infect_loadouts["axis"]["loadoutEquipment"] = INFECTED_LETHAL;
}

monitorsurvivaltime()
{
    self endon("death");
    self endon("disconnect");
    self endon("infected");
    level endon("game_ended");

    survivorcount = 0;

    for (;;)
    {
        if (!level.infect_chosefirstinfected || !isdefined(self.survivalstarttime) || !isalive(self))
        {
            wait 0.05;
            continue;
        }

        self setsurvivaltime(0);
        survivorcount++;
        maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(1.0);

        if (survivorcount == 30)
        {
            self thread survivorevent();
            survivorcount = 0;
        }
    }
}

clearsurvivaltime()
{
    self setextrascore0(0);
    self notify("infected");
    self setextrascore1(1);
}

setsurvivaltime(infected)
{
    if (!isdefined(self.survivalstarttime))
        self.survivalstarttime = self.spawntime;

    timesurvived = int((gettime() - self.survivalstarttime) / 1000);
    if (timesurvived > 999)
        timesurvived = 999;

    self setextrascore0(timesurvived);

    if (isdefined(infected) && infected)
    {
        self notify("infected");
        self setextrascore1(1);
    }
}

// Infected events (S1 maps\mp\_events, not in H1). Splash and XP event names as in S1; the
// strings SPLASHES_*INFECTED* exist in H1. If an event name is unknown to H1's tables, the test
// will show it and the call gets removed.

firstinfectedevent()
{
    playsoundonplayers("mp_enemy_obj_captured");
    level thread teamplayercardsplash("callout_first_infected", self);
    level thread maps\mp\gametypes\_rank::awardgameevent("first_infected", self);
}

finalsurvivorevent()
{
    level thread teamplayercardsplash("callout_final_survivor", self);
    level thread maps\mp\gametypes\_rank::awardgameevent("final_survivor", self);
}

gotinfectedevent()
{
    level thread maps\mp\gametypes\_rank::awardgameevent("got_infected", self);
}

plagueevent()
{
    level thread maps\mp\gametypes\_rank::awardgameevent("plague", self);
}

infectedsurvivorevent()
{
    level thread maps\mp\gametypes\_rank::awardgameevent("infected_survivor", self);
}

survivorevent()
{
    level thread maps\mp\gametypes\_rank::awardgameevent("survivor", self);
}

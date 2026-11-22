// MWX: Cranked for H1/HMW.
// Logic ported from IW6 (Ghosts) maps/mp/gametypes/cranked.gsc
// (COD-GSC-Source/IW6-GSC). H1 has no ui_cranked_* omnvars / bomb timer HUD, so the timer is a
// _hud_util createTimer element; team structure from H1 war.gsc. Custom classes stay enabled.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

#define CRANKED_TIME 30
#define CRANKED_MOVE_SCALAR 1.1
#define CRANKED_EXPLOSION_RADIUS 200
#define CRANKED_EXPLOSION_DAMAGE 300

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
        maps\mp\_utility::registerroundswitchdvar(level.gametype, 0, 0, 9);
        maps\mp\_utility::registertimelimitdvar(level.gametype, 10);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 75);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        maps\mp\_utility::registernumlivesdvar(level.gametype, 0);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0); // no killstreaks

    level.teambased = 1;
    level.classicgamemode = 1;
    level.onstartgametype = ::onstartgametype;
    level.getspawnpoint = ::getspawnpoint;
    level.onnormaldeath = ::onnormaldeath;
    level.onsuicidedeath = ::onsuicidedeath;
    level.onplayerscore = ::onplayerscore;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "team_deathmtch";
    game["strings"]["overtime_hint"] = &"MP_FIRST_BLOOD";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata();

    setdynamicdvar("scr_cranked_roundswitch", 0);
    maps\mp\_utility::registerroundswitchdvar("cranked", 0, 0, 9);
    setdynamicdvar("scr_cranked_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("cranked", 1);
    setdynamicdvar("scr_cranked_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("cranked", 1);
    setdynamicdvar("scr_cranked_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("cranked", 0);

    setdynamicdvar("scr_game_hardpoints", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    if (!isdefined(game["switchedsides"]))
        game["switchedsides"] = 0;

    if (game["switchedsides"])
    {
        attackers = game["attackers"];
        defenders = game["defenders"];
        game["attackers"] = defenders;
        game["defenders"] = attackers;
    }

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_CRANKED");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_CRANKED");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_CRANKED");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_CRANKED");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_CRANKED_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_CRANKED_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_CRANKED_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_CRANKED_HINT");

    initspawns();

    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    // the Cranked explosion must not cost score (H1's suicide tweakable is 0 by default)
    if (isdefined(level.gametweaks) && isdefined(level.gametweaks["suicidepointloss"]))
        level.gametweaks["suicidepointloss"].value = 0;
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
    spawnteam = self.pers["team"];

    if (game["switchedsides"])
        spawnteam = maps\mp\_utility::getotherteam(spawnteam);

    if (level.usestartspawns && level.ingraceperiod)
        spawnpoint = maps\mp\gametypes\_spawnlogic::getbeststartspawn("mp_tdm_spawn_" + spawnteam + "_start");
    else
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getteamspawnpoints(spawnteam);
        spawnpoint = maps\mp\gametypes\_spawnscoring::getspawnpoint_awayfromenemies(spawnpoints, spawnteam);
    }

    maps\mp\gametypes\_spawnlogic::recon_set_spawnpoint(spawnpoint);
    return spawnpoint;
}

onnormaldeath(victim, attacker, inflictor)
{
    if (isdefined(victim) && isplayer(victim))
        victim cleanupcranked();

    if (!isdefined(attacker) || !isplayer(attacker) || attacker == victim)
        return;

    // cranked kills score double for the team (IW6 onNormalDeath)
    if (isdefined(attacker.cranked))
    {
        level maps\mp\gametypes\_gamescore::giveteamscoreforobjective(attacker.pers["team"], 2);
        attacker thread crankedkill();
    }
    else
    {
        level maps\mp\gametypes\_gamescore::giveteamscoreforobjective(attacker.pers["team"], 1);
        attacker thread makecranked();
    }

    if (game["state"] == "postgame" && game["teamScores"][attacker.team] > game["teamScores"][level.otherteam[attacker.team]])
        attacker.finalkill = 1;
}

onsuicidedeath(victim)
{
    if (isdefined(victim) && isplayer(victim))
        victim cleanupcranked();
}

// player score: double for the "kill" event while cranked (IW6 onPlayerScore)
onplayerscore(event, player, victim)
{
    if (event != "kill")
        return undefined;

    value = maps\mp\gametypes\_rank::getscoreinfovalue(event);

    if (isdefined(player.cranked))
        value = value * 2;

    return value;
}

makecranked()
{
    self endon("disconnect");
    level endon("game_ended");

    if (isdefined(self.cranked))
        return;

    self.cranked = 1;
    self.cranked_end_time = gettime() + CRANKED_TIME * 1000;

    maps\mp\_utility::giveperk("specialty_fastreload", 0);
    maps\mp\_utility::giveperk("specialty_quickdraw", 0);
    maps\mp\_utility::giveperk("specialty_longersprint", 0);
    self setmovespeedscale(CRANKED_MOVE_SCALAR);

    self thread maps\mp\gametypes\_hud_message::hintmessage(&"MWX_CRANKED");
    self thread crankedhud();
}

crankedkill()
{
    self endon("disconnect");
    level endon("game_ended");

    if (!isdefined(self.cranked))
        return;

    // every further kill resets the timer to 30 s
    self.cranked_end_time = gettime() + CRANKED_TIME * 1000;

    if (isdefined(self.crankedhud))
    {
        self.crankedhud setTimer(CRANKED_TIME);
        self.crankedhud.color = (1, 1, 1);
    }
}

crankedhud()
{
    self endon("disconnect");

    if (isdefined(self.crankedhud))
        self.crankedhud maps\mp\gametypes\_hud_util::destroyelem();

    self.crankedhud = self maps\mp\gametypes\_hud_util::createtimer("hudbig", 1.4);
    self.crankedhud maps\mp\gametypes\_hud_util::setpoint("CENTER", "CENTER", 0, 64);
    self.crankedhud.alignx = "center";
    self.crankedhud.aligny = "middle";
    self.crankedhud.horzalign = "center_adjustable";
    self.crankedhud.vertalign = "middle";
    self.crankedhud.archived = 0;
    self.crankedhud.hidewheninmenu = 1;
    self.crankedhud.glowalpha = 0.6;
    self.crankedhud.color = (1, 1, 1);
    self.crankedhud setTimer(CRANKED_TIME);

    while (isdefined(self.cranked) && isalive(self) && !level.gameended)
    {
        if (gettime() >= self.cranked_end_time)
        {
            self crankedexplode();
            break;
        }

        if (self.cranked_end_time - gettime() <= 5000)
            self.crankedhud.color = (1, 0.15, 0.15);
        else
            self.crankedhud.color = (1, 1, 1);

        wait 0.1;
    }

    if (isdefined(self.crankedhud))
    {
        self.crankedhud maps\mp\gametypes\_hud_util::destroyelem();
        self.crankedhud = undefined;
    }
}

crankedexplode()
{
    if (!isalive(self))
        return;

    playfx(level.mine_explode, self.origin + (0, 0, 32));
    radiusdamage(self.origin + (0, 0, 32), CRANKED_EXPLOSION_RADIUS, CRANKED_EXPLOSION_DAMAGE, CRANKED_EXPLOSION_DAMAGE, self, "MOD_EXPLOSIVE");

    if (isalive(self))
        self maps\mp\_utility::_suicide();
}

cleanupcranked()
{
    if (isdefined(self.crankedhud))
    {
        self.crankedhud maps\mp\gametypes\_hud_util::destroyelem();
        self.crankedhud = undefined;
    }

    if (!isdefined(self.cranked))
        return;

    self.cranked = undefined;
    self.cranked_end_time = undefined;

    maps\mp\_utility::_unsetperk("specialty_fastreload");
    maps\mp\_utility::_unsetperk("specialty_quickdraw");
    maps\mp\_utility::_unsetperk("specialty_longersprint");
    self setmovespeedscale(1.0);
}

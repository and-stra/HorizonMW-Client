// MWX: Sharpshooter for H1/HMW.
//
// Port of the MW3 playlist mode (weapon rotation from maps/mp/gametypes/gun.gsc, refs/iw5-scripts):
// team deathmatch, everyone carries the same weapon, it rotates every scr_sharpshooter_rotatetime
// seconds (45 by default), and kills at 5/10/15 give a perk (Sleight of Hand, Stopping Power,
// Juggernaut). No class choice, no killstreaks, H1 TDM HUD.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

#define SS_TIMELIMIT 10
#define SS_SCORELIMIT 75
#define SS_ROTATE 45

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, SS_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, SS_SCORELIMIT);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        maps\mp\_utility::registernumlivesdvar(level.gametype, 0);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar("scr_" + level.gametype + "_numlives", 0);

    level.ss_rotatetime = getdvarfloat("scr_sharpshooter_rotatetime", SS_ROTATE);
    if (level.ss_rotatetime <= 0)
        level.ss_rotatetime = SS_ROTATE;

    setguns();
    level.ss_weaponindex = 0;
    level.ss_rotation = 0;

    level.teambased = 1;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.assists_disabled = 0;
    level.blockweapondrops = 1;
    level.quickmessagetoall = 1;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.onplayerkilled = ::onplayerkilled;
    level.bypassclasschoicefunc = ::ssclass;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "team_deathmtch";
    game["strings"]["overtime_hint"] = &"MP_FIRST_BLOOD";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_sharpshooter_timelimit", SS_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("sharpshooter", SS_TIMELIMIT);
    setdynamicdvar("scr_sharpshooter_scorelimit", SS_SCORELIMIT);
    maps\mp\_utility::registerscorelimitdvar("sharpshooter", SS_SCORELIMIT);
    setdynamicdvar("scr_sharpshooter_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("sharpshooter", 1);
    setdynamicdvar("scr_sharpshooter_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("sharpshooter", 1);
    setdynamicdvar("scr_sharpshooter_numlives", 0);
    maps\mp\_utility::registernumlivesdvar("sharpshooter", 0);
    setdynamicdvar("scr_sharpshooter_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("sharpshooter", 0);
    setdynamicdvar("scr_game_hardpoints", 0);
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

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_SHARPSHOOTER");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_SHARPSHOOTER");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SHARPSHOOTER");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SHARPSHOOTER");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SHARPSHOOTER_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SHARPSHOOTER_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_SHARPSHOOTER_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_SHARPSHOOTER_HINT");

    initspawns();
    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level thread rotateweapons();
    level thread sharpshooterhud();
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

// everyone gets the gamemode loadout; the current rotation weapon is applied after the spawn
ssclass()
{
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "";
    self.pers["gamemodeLoadout"] = maps\mp\gametypes\_class::getemptyloadout();
    self.class = self.pers["class"];
    self.lastclass = self.pers["lastClass"];
}

onspawnplayer()
{
    self thread ssspawnfinished();
}

ssspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    // _playerlogic notifies spawned_player right after _class::applyloadout
    self waittill("spawned_player");
    thread ssgivecurrentgun();
}

ssgivecurrentgun()
{
    weapon = level.ss_guns[level.ss_weaponindex];

    // a weapon that is not in the zone yet has to be streamed in first (see H1 gun.gsc)
    while (!self loadweapons(weapon))
        waitframe();

    self takeallweapons();
    self giveweapon(weapon);
    self switchtoweapon(weapon);
    self setspawnweapon(weapon);
    self givestartammo(weapon);

    self.pers["gamemodeLoadout"] = maps\mp\gametypes\_class::getemptyloadout();
    self.pers["gamemodeLoadout"]["loadoutPrimary"] = "h1_ak47"; // class ref only, the engine weapon is set above
    self.ss_weapon = weapon;
}

// 45 s rotation, same weapon for everyone alive (dead players get it on their next spawn)
rotateweapons()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    for (;;)
    {
        wait level.ss_rotatetime;

        level.ss_weaponindex++;
        if (level.ss_weaponindex >= level.ss_guns.size)
            level.ss_weaponindex = 0;
        level.ss_rotation++;

        level notify("ss_rotate");

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            player thread ssgivecurrentgun();
        }

        level thread ssannounce();
    }
}

ssannounce()
{
    foreach (player in level.players)
    {
        if (!isdefined(player))
            continue;
        player playlocalsound("mp_war_objective_taken");
    }
}

// kill milestones give a perk (MW3 sharpshooter reward track)
onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, killid)
{
    if (!isdefined(attacker) || !isplayer(attacker) || attacker == self)
        return;
    if (!isdefined(self.team) || !isdefined(attacker.team) || self.team == attacker.team)
        return;

    if (!isdefined(attacker.ss_kills))
        attacker.ss_kills = 0;

    attacker.ss_kills++;

    if (attacker.ss_kills == 5)
        attacker maps\mp\_utility::giveperk("specialty_fastreload", 1);
    else if (attacker.ss_kills == 10)
        attacker maps\mp\_utility::giveperk("specialty_bulletdamage", 1);
    else if (attacker.ss_kills == 15)
        attacker maps\mp\_utility::giveperk("specialty_armorvest", 1);
}

// small HUD line: "WEAPON <n>  <seconds>s" using the stock font strings
sharpshooterhud()
{
    level endon("game_ended");

    level.ss_hud = maps\mp\gametypes\_hud_util::createserverfontstring("objective", 1.0);
    level.ss_hud.label = &"MWX_SHRP_WEAPON";
    level.ss_hud maps\mp\gametypes\_hud_util::setpoint("TOPCENTER", "TOPCENTER", 0, 30);
    level.ss_hud.alignx = "center";
    level.ss_hud.aligny = "middle";
    level.ss_hud.horzalign = "center_adjustable";
    level.ss_hud.vertalign = "top_adjustable";
    level.ss_hud.archived = 1;
    level.ss_hud.hidewheninmenu = 0;
    level.ss_hud.glowalpha = 0.4;
    level.ss_hud.alpha = 1;

    for (;;)
    {
        level.ss_hud setvalue(level.ss_weaponindex + 1);
        wait 1;
    }
}

setguns()
{
    level.ss_guns = [];

    ssgun("h2_colt45");
    ssgun("h2_ak74u");
    ssgun("h2_m16");
    ssgun("h2_m240");
    ssgun("h2_m40a3");
    ssgun("h2_m9");
    ssgun("h2_p90");
    ssgun("h2_masada");
    ssgun("h2_spas12");
    ssgun("h2_wa2000");
    ssgun("h2_deserteagle");
    ssgun("h2_kriss");
    ssgun("h2_scar");
    ssgun("h2_mg4");
    ssgun("h2_cheytac");
    ssgun("h2_fal");
    ssgun("h2_mp5k");
    ssgun("h2_fn2000");
}

ssgun(ref)
{
    level.ss_guns[level.ss_guns.size] = maps\mp\gametypes\_class::buildweaponname(ref, "none", "none", "none", []);
}

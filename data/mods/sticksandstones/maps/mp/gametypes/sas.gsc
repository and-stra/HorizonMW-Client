// MWX mod: Sticks and Stones for H1/HMW (proof of concept for mod support).
// Rules from Black Ops 2 maps/mp/gametypes/sas.gsc (COD-GSC-Source/BO2-GSC), FFA structure from H1 dm.gsc:
// - crossbow (Advanced Warfare's iw5_exocrossbow, built into this mod's mod.ff) as the primary
// - a melee weapon instead of BO's ballistic knife (HMW has none)
// - the throwing knife replaces the tomahawk: a throwing knife kill bankrupts the victim (score 0)
// - a suicide bankrupts the player too
// - one point per kill, no score limit, 10 minutes, highest score wins
// Test without mod.ff: set sas_weapon to any HMW weapon (e.g. h2_m21_mp) before the map loads.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

#define SAS_TIMELIMIT 10
#define SAS_CROSSBOW "iw5_exocrossbow_mp"
#define SAS_MELEE "h2_hatchet"
#define SAS_TOMAHAWK "iw9_throwknife_mp"

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, SAS_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        maps\mp\_utility::registernumlivesdvar(level.gametype, 0);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0); // no killstreaks

    if (getdvar("sas_weapon") == "")
        setdvar("sas_weapon", SAS_CROSSBOW);

    setspecialloadouts();

    level.teambased = 0;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.killstreakrewards = 0;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.onplayerkilled = ::onplayerkilled;
    level.onplayerscore = ::onplayerscore;
    level.bypassclasschoicefunc = ::sasclass;
    level.assists_disabled = 1;

    setteammode("ffa");
    game["dialog"]["gametype"] = "freeforall";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_sas_timelimit", SAS_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("sas", SAS_TIMELIMIT);
    setdynamicdvar("scr_sas_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("sas", 1);
    setdynamicdvar("scr_sas_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("sas", 1);
    setdynamicdvar("scr_sas_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("sas", 0);
    maps\mp\_utility::registernumlivesdvar("sas", 0);
    setdynamicdvar("scr_game_hardpoints", 0);

    // no score limit: highest score at the time limit wins
    maps\mp\_utility::setoverridewatchdvar("scorelimit", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_SAS");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_SAS");
    maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SAS_SCORE");
    maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SAS_SCORE");
    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_SAS_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_SAS_HINT");

    level.spawnmins = (0, 0, 0);
    level.spawnmaxs = (0, 0, 0);
    maps\mp\gametypes\_spawnlogic::addspawnpoints("allies", "mp_dm_spawn");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("axis", "mp_dm_spawn");
    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter(level.spawnmins, level.spawnmaxs);
    setmapcenter(level.mapcenter);

    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level.quickmessagetoall = 1;
    level.blockweapondrops = 1;
}

getspawnpoint()
{
    if (level.ingraceperiod)
        spawnpoint = maps\mp\gametypes\_spawnlogic::getstartspawnffa(self.pers["team"]);
    else
    {
        spawnpoints = maps\mp\gametypes\_spawnlogic::getteamspawnpoints(self.pers["team"]);
        spawnpoint = maps\mp\gametypes\_spawnscoring::getspawnpoint_freeforall(spawnpoints);
    }

    maps\mp\gametypes\_spawnlogic::recon_set_spawnpoint(spawnpoint);
    return spawnpoint;
}

sasclass()
{
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "";
    self.pers["gamemodeLoadout"] = level.sas_loadout;
    self.class = self.pers["class"];
    self.lastclass = self.pers["lastClass"];
}

onspawnplayer()
{
    self.pers["gamemodeLoadout"] = level.sas_loadout;
    self thread sasspawnfinished();
}

// BO2 sas.gsc onspawnplayerunified: crossbow (3 + 3), ballistic knife, tomahawk (1), knife
sasspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");

    crossbow = getdvar("sas_weapon");
    melee = maps\mp\gametypes\_class::buildweaponname(SAS_MELEE, "none", "none", "none", []);

    self takeallweapons();
    self giveweapon(crossbow);
    self giveweapon(melee);
    self giveweapon(SAS_TOMAHAWK);
    self setlethalweapon(SAS_TOMAHAWK);

    self setweaponammoclip(crossbow, weaponclipsize(crossbow));
    self setweaponammostock(crossbow, 6);
    self setweaponammoclip(SAS_TOMAHAWK, 1);

    self setspawnweapon(crossbow);
    self switchtoweapon(crossbow);

    if (isbot(self))
        self botsetflag("encourage_grenade_use", 1);
}

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, lifeid)
{
    // suicide or world death: bankrupt yourself (BO2 sas.gsc)
    if (!isdefined(attacker) || !isplayer(attacker) || attacker == self)
    {
        self thread bankrupt();
        return;
    }

    if (isdefined(sweapon) && sweapon == SAS_TOMAHAWK)
    {
        self thread bankrupt();
        attacker thread maps\mp\gametypes\_hud_message::hintmessage(&"MWX_SAS_BANKRUPT_ENEMY");
        attacker playlocalsound("mp_war_objective_taken");
    }
}

bankrupt()
{
    if (self.pers["score"] > 0)
        maps\mp\gametypes\_gamescore::_setplayerscore(self, 0);

    self thread maps\mp\gametypes\_hud_message::hintmessage(&"MWX_SAS_BANKRUPTED");
    self playlocalsound("mp_enemy_obj_captured");
}

// FFA scoring as in dm.gsc: one point per kill
onplayerscore(event, player, victim)
{
    value = maps\mp\gametypes\_rank::getscoreinfovalue(event);
    player maps\mp\_utility::setextrascore0(player.extrascore0 + value);
    player maps\mp\gametypes\_gamescore::updatescorestatsffa(player, value);

    if (event == "kill")
        return 1;

    return 0;
}

// the real weapons are given in sasspawnfinished; this only skips the class menu
setspecialloadouts()
{
    level.sas_loadout = maps\mp\gametypes\_class::getemptyloadout();
    level.sas_loadout["loadoutPrimary"] = "h2_usp";
    level.sas_loadout["loadoutSecondary"] = "none";
    level.sas_loadout["loadoutEquipment"] = "specialty_null";
    level.sas_loadout["loadoutOffhand"] = "none";
    level.sas_loadout["loadoutMelee"] = "none";
}

// MWX: All or Nothing for H1/HMW.
// IW5 has no aon.gsc in the Plutonium dump; rules from the MW3 game mode and the Plutonium IW5
// recreation (refs/plutonium-iw5-scripts/gamemodes/all_or_nothing.gsc): FFA, USP with no ammo,
// throwing knife, scavenger, 20 kills, 10 minutes. FFA structure from H1 dm.gsc.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

// HMW weapons (same names as in the Infected port)
#define AON_WEAPON "h2_usp"
#define AON_LETHAL "iw9_throwknife_mp"
#define AON_SCORELIMIT 20
#define AON_TIMELIMIT 10

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, AON_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, AON_SCORELIMIT);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        maps\mp\_utility::registernumlivesdvar(level.gametype, 0);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_player_maxhealth", 100);
    setdynamicdvar("scr_game_onlyheadshots", 0);
    setdynamicdvar("scr_game_hardpoints", 0); // no killstreaks

    setspecialloadouts();

    // the 20th kill is ended in onnormaldeath so the "never died" bonus can be given first
    level.scorelimitoverride = 1;

    level.teambased = 0;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.killstreakrewards = 0;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.onnormaldeath = ::onnormaldeath;
    level.ontimelimit = ::ontimelimit;
    level.onplayerscore = ::onplayerscore;
    level.bypassclasschoicefunc = ::aonclass;
    level.assists_disabled = 1;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    setteammode("ffa");
    game["dialog"]["gametype"] = "freeforall";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_aon_timelimit", AON_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("aon", AON_TIMELIMIT);
    setdynamicdvar("scr_aon_scorelimit", AON_SCORELIMIT);
    maps\mp\_utility::registerscorelimitdvar("aon", AON_SCORELIMIT);
    setdynamicdvar("scr_aon_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("aon", 1);
    setdynamicdvar("scr_aon_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("aon", 1);
    setdynamicdvar("scr_aon_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("aon", 0);
    maps\mp\_utility::registernumlivesdvar("aon", 0);

    setdynamicdvar("scr_player_maxhealth", 100);
    setdynamicdvar("scr_game_onlyheadshots", 0);
    setdynamicdvar("scr_game_hardpoints", 0);

    maps\mp\_utility::setoverridewatchdvar("scorelimit", AON_SCORELIMIT);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_AON");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_AON");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_AON");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_AON");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_AON_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_AON_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_AON_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_AON_HINT");

    initspawns();

    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    level.quickmessagetoall = 1;
    level.blockweapondrops = 1;
}

initspawns()
{
    level.spawnmins = (0, 0, 0);
    level.spawnmaxs = (0, 0, 0);
    maps\mp\gametypes\_spawnlogic::addspawnpoints("allies", "mp_dm_spawn");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("axis", "mp_dm_spawn");
    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter(level.spawnmins, level.spawnmaxs);
    setmapcenter(level.mapcenter);
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

// no class choice: everyone gets the gamemode loadout
aonclass()
{
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "";
    self.pers["gamemodeLoadout"] = level.aon_loadout;
    self.class = self.pers["class"];
    self.lastclass = self.pers["lastClass"];
}

onspawnplayer()
{
    self.pers["gamemodeLoadout"] = level.aon_loadout;
    self thread aonspawnfinished();
}

aonspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");

    // empty pistol, the throwing knife is the only way to get the first kill
    // the loadout gave the full weapon name (h2_usp_mp...); the bare ref is not a weapon
    weapon = self.primaryweapon;
    if (isdefined(weapon) && weapon != "none" && self hasweapon(weapon))
    {
        self setweaponammoclip(weapon, 0);
        self setweaponammostock(weapon, 0);
    }
}

onnormaldeath(victim, attacker, inflictor)
{
    if (!isdefined(attacker) || !isplayer(attacker) || attacker == victim)
        return;

    level notify("update_game_time");

    // count the kills in the gametype itself (the score award runs in its own thread)
    if (!isdefined(attacker.aon_kills))
        attacker.aon_kills = 0;

    attacker.aon_kills++;

    // "1 kill left"
    if (attacker.aon_kills == AON_SCORELIMIT - 1 && !isdefined(attacker.aon_onekillsplash))
    {
        attacker.aon_onekillsplash = 1;
        level thread aononekillsplash(attacker);
    }

    if (attacker.aon_kills >= AON_SCORELIMIT && !isdefined(level.aon_ending))
    {
        level.aon_ending = 1;
        level thread aonend(attacker, game["end_reason"]["score_limit_reached"]);
    }
}

ontimelimit()
{
    if (isdefined(level.aon_ending))
        return;

    winner = maps\mp\gametypes\_gamescore::gethighestscoringplayer();
    level.aon_ending = 1;
    level thread aonend(winner, game["end_reason"]["time_limit_reached"]);
}

aononekillsplash(player)
{
    if (level.gameended)
        return;

    // only for the player himself ("1 KILL LEFT" for everyone would read as their own count)
    player thread maps\mp\gametypes\_hud_message::hintmessage(&"MWX_AON_ONE_KILL");
}

// the winner that never died gets the "ALL OR NOTHING!" bonus and splash before the end
aonend(winner, reason)
{
    if (level.gameended)
        return;

    if (isdefined(winner) && isplayer(winner) && winner.deaths == 0)
    {
        level thread splashtoplayers(&"MWX_AON_BONUS");

        // register at award time: _rank::init()/_events::init() rebuild the table during match start
        if (!maps\mp\gametypes\_rank::isregisteredevent("mwx_allornothing"))
            maps\mp\gametypes\_rank::registerxpeventinfo("mwx_allornothing", 500);

        level thread maps\mp\gametypes\_rank::awardgameevent("mwx_allornothing", winner);
        wait 1.5;
    }

    if (level.gameended)
        return;

    level.finalkillcam_winner = "none";
    level thread maps\mp\gametypes\_gamelogic::endgame(winner, reason);
}

// custom text splash (splashTable.csv has no rows for MWX strings; the notify text is a HUD font)
splashtoplayers(text)
{
    foreach (player in level.players)
    {
        if (!isdefined(player) || !isplayer(player))
            continue;

        player thread maps\mp\gametypes\_hud_message::hintmessage(text);
    }
}

// FFA scoring as in dm.gsc: one point per kill (score limit 20 = 20 kills)
onplayerscore(event, player, victim)
{
    value = maps\mp\gametypes\_rank::getscoreinfovalue(event);
    player maps\mp\_utility::setextrascore0(player.extrascore0 + value);
    player maps\mp\gametypes\_gamescore::updatescorestatsffa(player, value);

    if (event == "kill")
        return 1;

    return 0;
}

setspecialloadouts()
{
    level.aon_loadout = maps\mp\gametypes\_class::getemptyloadout();
    level.aon_loadout["loadoutPrimary"] = AON_WEAPON;
    level.aon_loadout["loadoutSecondary"] = "none";
    level.aon_loadout["loadoutEquipment"] = AON_LETHAL;
    level.aon_loadout["loadoutOffhand"] = "none";
    level.aon_loadout["loadoutMelee"] = "none";
    level.aon_loadout["loadoutPerks"][0] = "specialty_scavenger";
    level.aon_loadout["loadoutPerks"][1] = "specialty_fastreload";
    level.aon_loadout["loadoutPerks"][2] = "specialty_longersprint";
}

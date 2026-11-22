// MWX: One in the Chamber for H1/HMW.
// Port of IW5 maps/mp/gametypes/oic.gsc (Plutonium IW5 GSC dump, refs/iw5-scripts) to H1 + HMW:
// FFA structure from H1 dm.gsc, fixed HMW loadout (colt anaconda, 1 round), 3 lives, H1 HUD.
// IW5 match rules data (oicData), gun attachments and the survivor/elimination score events are
// removed; a kill now gives one round to the killer's revolver (IW5 giveammo logic).

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_class;

// HMW weapon name (same prefix scheme as h2_usp / h2_spas12 in the HMW statstable)
#define OIC_WEAPON "h2_coltanaconda"
#define OIC_TIMELIMIT 10
#define OIC_NUMLIVES 3

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, OIC_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        // the watched dvar is read by registernumlivesdvar, so set it first
        setdynamicdvar("scr_oic_numlives", OIC_NUMLIVES);
        maps\mp\_utility::registernumlivesdvar(level.gametype, OIC_NUMLIVES);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_player_maxhealth", 100);
    setdynamicdvar("scr_game_onlyheadshots", 0);
    setdynamicdvar("scr_game_hardpoints", 0); // no killstreaks

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
    level.bypassclasschoicefunc = ::oicclass;
    level.assists_disabled = 1;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    setteammode("ffa");
    game["dialog"]["gametype"] = "freeforall";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_oic_timelimit", OIC_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("oic", OIC_TIMELIMIT);
    setdynamicdvar("scr_oic_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("oic", 1);
    setdynamicdvar("scr_oic_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("oic", 1);
    setdynamicdvar("scr_oic_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("oic", 0);

    // 3 lives: set the dvar before the watched dvar is registered
    setdynamicdvar("scr_oic_numlives", OIC_NUMLIVES);
    maps\mp\_utility::registernumlivesdvar("oic", OIC_NUMLIVES);

    setdynamicdvar("scr_player_maxhealth", 100);
    setdynamicdvar("scr_game_onlyheadshots", 0);
    setdynamicdvar("scr_game_hardpoints", 0);

    // no score limit (win by elimination or most kills at the time limit)
    maps\mp\_utility::setoverridewatchdvar("scorelimit", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_OIC");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_OIC");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_OIC");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_OIC");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_OIC_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_OIC_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_OIC_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_OIC_HINT");

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
oicclass()
{
    self.pers["class"] = "gamemode";
    self.pers["lastClass"] = "";
    self.pers["gamemodeLoadout"] = level.oic_loadout;
    self.class = self.pers["class"];
    self.lastclass = self.pers["lastClass"];
}

onspawnplayer()
{
    self.pers["gamemodeLoadout"] = level.oic_loadout;
    self thread oicspawnfinished();
}

oicspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    // _playerlogic notifies spawned_player right after _class::applyloadout
    self waittill("spawned_player");

    // one revolver, one round in the clip, no stock, nothing else. The loadout gave the full weapon name
    // (h2_coltanaconda_mp...); the bare ref is not a weapon.
    weapon = self.primaryweapon;
    if (!isdefined(weapon) || weapon == "none")
        weapon = maps\mp\gametypes\_class::buildweaponname(OIC_WEAPON, "none", "none", "none", []);
    self.oic_weapon = weapon;

    self takeallweapons();
    self giveweapon(weapon);
    self switchtoweapon(weapon);
    self setspawnweapon(weapon);
    self setweaponammoclip(weapon, 1);
    self setweaponammostock(weapon, 0);

    self thread oicliveshud();
}

// any kill (gun, knife, equipment) gives the killer one round
onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, lifeid)
{
    if (!isdefined(attacker) || !isplayer(attacker) || attacker == self)
        return;

    attacker thread oicgiveammo();
}

oicgiveammo()
{
    if (!isdefined(self) || !isdefined(self.oic_weapon) || !self hasweapon(self.oic_weapon))
        return;

    weapon = self.oic_weapon;

    level endon("game_ended");
    self endon("death");
    self endon("disconnect");

    clip = self getweaponammoclip(weapon);
    stock = self getweaponammostock(weapon);
    maxclip = weaponclipsize(weapon);

    // IW5 oic.gsc giveammo(): clip first, the rest to the stock
    total = clip + stock + 1;

    if (total > maxclip)
    {
        clip = maxclip;
        stock = total - maxclip;
    }
    else
    {
        clip = total;
        stock = 0;
    }

    self setweaponammoclip(weapon, clip);
    self setweaponammostock(weapon, stock);

    self playlocalsound("wpn_ammo_pickup_plr");
}

oicliveshud()
{
    self endon("disconnect");

    if (isdefined(self.oic_liveshud))
        self.oic_liveshud maps\mp\gametypes\_hud_util::destroyelem();

    self.oic_liveshud = self maps\mp\gametypes\_hud_util::createfontstring("objective", 1.2);
    self.oic_liveshud maps\mp\gametypes\_hud_util::setpoint("TOPCENTER", "TOPCENTER", 0, 52);
    self.oic_liveshud.alignx = "center";
    self.oic_liveshud.aligny = "middle";
    self.oic_liveshud.horzalign = "center_adjustable";
    self.oic_liveshud.vertalign = "top_adjustable";
    self.oic_liveshud.archived = 0;
    self.oic_liveshud.hidewheninmenu = 1;
    self.oic_liveshud.glowalpha = 0.5;
    self.oic_liveshud.alpha = 1;

    // pers["lives"] was already decremented for this spawn, so +1 = lives including this one
    lives = self.pers["lives"] + 1;

    switch (lives)
    {
        case 1:
            self.oic_liveshud.label = &"MWX_OIC_LIVES_1";
            break;
        case 2:
            self.oic_liveshud.label = &"MWX_OIC_LIVES_2";
            break;
        default:
            self.oic_liveshud.label = &"MWX_OIC_LIVES_3";
            break;
    }

    while (!level.gameended && isalive(self) && isdefined(self.oic_liveshud))
        wait 0.5;

    if (isdefined(self.oic_liveshud))
    {
        self.oic_liveshud maps\mp\gametypes\_hud_util::destroyelem();
        self.oic_liveshud = undefined;
    }
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

setspecialloadouts()
{
    level.oic_loadout = maps\mp\gametypes\_class::getemptyloadout();
    level.oic_loadout["loadoutPrimary"] = OIC_WEAPON;
    level.oic_loadout["loadoutSecondary"] = "none";
    level.oic_loadout["loadoutEquipment"] = "specialty_null";
    level.oic_loadout["loadoutOffhand"] = "none";
    level.oic_loadout["loadoutMelee"] = "none";
}

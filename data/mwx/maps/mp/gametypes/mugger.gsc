// MWX: Mugger for H1/HMW.
//
// Port of the IW6 mugger.gsc tag economy (refs: COD-GSC-Source/IW6-GSC/maps/mp/gametypes/mugger.gsc)
// to H1/HMW: free-for-all. A killed player drops a tag at the death spot; anyone who reaches it banks
// it (+1). A melee kill steals every tag the victim has banked. Tags are the score. 10 minutes, 30 tags.
//
// The tag visual is a placeholder (no dog tag model in H1/HMW zones): the universal Mad Props crate.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

#define MG_TIMELIMIT 10
#define MG_SCORELIMIT 30
#define MG_TAGLIFE 30
#define MG_TAGRADIUS 90

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, MG_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, MG_SCORELIMIT);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 1);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, 1);
        maps\mp\_utility::registernumlivesdvar(level.gametype, 0);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar("scr_" + level.gametype + "_numlives", 0);

    level.teambased = 0;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.assists_disabled = 1;
    level.blockweapondrops = 0;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.onplayerkilled = ::onplayerkilled;
    level.onplayerscore = ::onplayerscore;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    setteammode("ffa");
    game["dialog"]["gametype"] = "freeforall";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata(1);

    setdynamicdvar("scr_mugger_timelimit", MG_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("mugger", MG_TIMELIMIT);
    setdynamicdvar("scr_mugger_scorelimit", MG_SCORELIMIT);
    maps\mp\_utility::registerscorelimitdvar("mugger", MG_SCORELIMIT);
    setdynamicdvar("scr_mugger_winlimit", 1);
    maps\mp\_utility::registerwinlimitdvar("mugger", 1);
    setdynamicdvar("scr_mugger_roundlimit", 1);
    maps\mp\_utility::registerroundlimitdvar("mugger", 1);
    setdynamicdvar("scr_mugger_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("mugger", 0);
    setdynamicdvar("scr_mugger_numlives", 0);
    maps\mp\_utility::registernumlivesdvar("mugger", 0);
    setdynamicdvar("scr_game_hardpoints", 0);
}

onstartgametype()
{
    setclientnamemode("auto_change");

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_MUGGER");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_MUGGER");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_MUGGER");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_MUGGER");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_MUGGER_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_MUGGER_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_MUGGER_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_MUGGER_HINT");

    initspawns();
    allowed[0] = "dm";
    maps\mp\gametypes\_gameobjects::main(allowed);

    precachemodel("com_cardboardbox06");
    level.quickmessagetoall = 1;
    level.mugger_tags = [];
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

onspawnplayer()
{
    if (!isdefined(self.mugger_banked))
        self.mugger_banked = 0;
}

// --- tags ----------------------------------------------------------------------------------

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, killid)
{
    if (!isdefined(attacker) || !isplayer(attacker) || attacker == self)
    {
        self thread mgdroptag();
        return;
    }

    // melee kill: the attacker takes the victim's bank permanently
    if (maps\mp\_utility::ismeleemod(smeansofdeath))
    {
        if (!isdefined(attacker.mugger_banked))
            attacker.mugger_banked = 0;
        if (!isdefined(self.mugger_banked))
            self.mugger_banked = 0;

        stolen = self.mugger_banked;
        if (stolen > 0)
        {
            self.mugger_banked = 0;
            attacker.mugger_banked = attacker.mugger_banked + stolen;
            attacker maps\mp\gametypes\_gamescore::updatescorestatsffa(attacker, stolen);
            attacker maps\mp\_utility::leaderdialogonplayer("steal", "status");
            self maps\mp\_utility::leaderdialogonplayer("lose_tags", "status");
        }
    }

    self thread mgdroptag();
}

mgdroptag()
{
    self endon("disconnect");
    level endon("game_ended");

    wait 0.5;

    if (isalive(self))
        return;

    guid = self.guid + "_" + gettime();
    pos = self.origin + (0, 0, 16);

    tag = spawn("script_model", pos);
    tag setmodel("com_cardboardbox06");
    tag.angles = (0, 0, 0);

    data = spawnstruct();
    data.tag = tag;
    data.expire = gettime() + MG_TAGLIFE * 1000;
    level.mugger_tags[guid] = data;

    playsoundatpos(pos, "mp_killconfirm_tags_drop");
    level thread mgtagwatch(guid);
}

mgtagwatch(guid)
{
    level endon("game_ended");

    for (;;)
    {
        wait 0.25;

        if (!isdefined(level.mugger_tags[guid]))
            return;

        data = level.mugger_tags[guid];

        if (gettime() > data.expire)
        {
            mgtagdelete(guid);
            return;
        }

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (distancesquared(player.origin, data.tag.origin) > MG_TAGRADIUS * MG_TAGRADIUS)
                continue;

            level thread mgbank(guid, player);
            return;
        }
    }
}

mgtagdelete(guid)
{
    if (!isdefined(level.mugger_tags[guid]))
        return;

    data = level.mugger_tags[guid];

    if (isdefined(data.tag))
    {
        playsoundatpos(data.tag.origin, "mp_killconfirm_tags_pickup");
        data.tag delete();
    }

    level.mugger_tags[guid] = undefined;
}

mgbank(guid, player)
{
    if (!isdefined(level.mugger_tags[guid]))
        return;

    if (!isdefined(player.mugger_banked))
        player.mugger_banked = 0;

    player.mugger_banked = player.mugger_banked + 1;
    player maps\mp\gametypes\_gamescore::updatescorestatsffa(player, 1);
    player playlocalsound("mp_killconfirm_tags_pickup");
    player notify("objective", "captured");

    mgtagdelete(guid);
}

// test hook: bots do not walk to tags on their own
mwxmugger_pickup(player)
{
    foreach (guid, data in level.mugger_tags)
    {
        if (!isdefined(data))
            continue;
        level thread mgbank(guid, player);
        return 1;
    }

    return 0;
}

onplayerscore(event, player, victim)
{
    value = maps\mp\gametypes\_rank::getscoreinfovalue(event);
    player maps\mp\_utility::setextrascore0(player.extrascore0 + value);
    player maps\mp\gametypes\_gamescore::updatescorestatsffa(player, value);

    if (event == "kill")
        return 1;

    return 0;
}

// MWX: Search & Rescue for H1/HMW.
//
// Port of the S1X sr.gsc tag mechanic (refs: COD-GSC-Source/S1X-GSC/maps/mp/gametypes/sr.gsc) and
// H1's sd round rules (common_sd_sr.gsc) to H1/HMW: round based, one life. A killed player drops a
// tag at the death spot. A teammate who reaches it revives the player (respawn in the same round);
// an enemy who reaches it confirms the death. A round ends when a team has no living players and no
// unconfirmed tags left. First team with scr_srescue_winlimit round wins takes the match.
//
// The tag visual is a placeholder: H1/HMW zones have no dog tag model (only tag_origin), so the
// universal Mad Props crate model is used until a real asset is found. The tag carries a HUD-less
// 25 s lifetime; every touch is distance-based (no use-object).

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

#define SR_TIMELIMIT 5
#define SR_WINLIMIT 3
#define SR_TAGLIFE 25
#define SR_TAGRADIUS 90

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
        maps\mp\_utility::registertimelimitdvar(level.gametype, SR_TIMELIMIT);
        maps\mp\_utility::registerscorelimitdvar(level.gametype, 0);
        maps\mp\_utility::registerroundlimitdvar(level.gametype, 0);
        maps\mp\_utility::registerwinlimitdvar(level.gametype, SR_WINLIMIT);
        maps\mp\_utility::registerhalftimedvar(level.gametype, 0);
        level.matchrules_damagemultiplier = 0;
        level.matchrules_vampirism = 0;
    }

    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar("scr_" + level.gametype + "_numlives", 1);
    maps\mp\_utility::registernumlivesdvar(level.gametype, 1);

    level.teambased = 1;
    level.objectivebased = 1;
    level.classicgamemode = 1;
    level.doprematch = 1;
    level.allowlatecomers = 0;
    level.onstartgametype = ::onstartgametype;
    level.onspawnplayer = ::onspawnplayer;
    level.getspawnpoint = ::getspawnpoint;
    level.ondeadevent = ::ondeadevent;
    level.onplayerkilled = ::onplayerkilled;
    level.ontimelimit = ::ontimelimit;

    if (level.matchrules_damagemultiplier || level.matchrules_vampirism)
        level.modifyplayerdamage = maps\mp\gametypes\_damage::gamemodemodifyplayerdamage;

    game["dialog"]["gametype"] = "searchanddestroy";
    game["dialog"]["revived"] = "sr_rev";
    game["strings"]["overtime_hint"] = &"MP_FIRST_BLOOD";
}

initializematchrules()
{
    maps\mp\_utility::setcommonrulesfrommatchrulesdata();

    setdynamicdvar("scr_srescue_timelimit", SR_TIMELIMIT);
    maps\mp\_utility::registertimelimitdvar("srescue", SR_TIMELIMIT);
    setdynamicdvar("scr_srescue_winlimit", SR_WINLIMIT);
    maps\mp\_utility::registerwinlimitdvar("srescue", SR_WINLIMIT);
    setdynamicdvar("scr_srescue_roundlimit", 0);
    maps\mp\_utility::registerroundlimitdvar("srescue", 0);
    setdynamicdvar("scr_srescue_halftime", 0);
    maps\mp\_utility::registerhalftimedvar("srescue", 0);
    setdynamicdvar("scr_srescue_numlives", 1);
    maps\mp\_utility::registernumlivesdvar("srescue", 1);
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

    maps\mp\_utility::setobjectivetext("allies", &"OBJECTIVES_SRESCUE");
    maps\mp\_utility::setobjectivetext("axis", &"OBJECTIVES_SRESCUE");

    if (level.splitscreen)
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SRESCUE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SRESCUE");
    }
    else
    {
        maps\mp\_utility::setobjectivescoretext("allies", &"OBJECTIVES_SRESCUE_SCORE");
        maps\mp\_utility::setobjectivescoretext("axis", &"OBJECTIVES_SRESCUE_SCORE");
    }

    maps\mp\_utility::setobjectivehinttext("allies", &"OBJECTIVES_SRESCUE_HINT");
    maps\mp\_utility::setobjectivehinttext("axis", &"OBJECTIVES_SRESCUE_HINT");

    initspawns();
    allowed[0] = level.gametype;
    maps\mp\gametypes\_gameobjects::main(allowed);

    precachemodel("com_cardboardbox06");

    level.sr_tags = [];
    level thread srroundwatch();
}

initspawns()
{
    level.spawnmins = (0, 0, 0);
    level.spawnmaxs = (0, 0, 0);
    maps\mp\gametypes\_spawnlogic::addstartspawnpoints("mp_sd_spawn_attacker");
    maps\mp\gametypes\_spawnlogic::addstartspawnpoints("mp_sd_spawn_defender");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("allies", "mp_tdm_spawn");
    maps\mp\gametypes\_spawnlogic::addspawnpoints("axis", "mp_tdm_spawn");
    level.mapcenter = maps\mp\gametypes\_spawnlogic::findboxcenter(level.spawnmins, level.spawnmaxs);
    setmapcenter(level.mapcenter);
}

getspawnpoint()
{
    team = self.pers["team"];

    if (level.ingraceperiod)
    {
        if (team == "allies")
            spawnpoints = maps\mp\gametypes\_spawnlogic::getspawnpointarray("mp_sd_spawn_attacker");
        else
            spawnpoints = maps\mp\gametypes\_spawnlogic::getspawnpointarray("mp_sd_spawn_defender");

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
    self thread srspawnfinished();
}

srspawnfinished()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");
    self.tagavailable = 0;
}

// --- tags ----------------------------------------------------------------------------------

onplayerkilled(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime, deathanimduration, killid)
{
    if (level.ingraceperiod)
        return;
    if (isdefined(attacker) && isplayer(attacker) && attacker != self && isdefined(self.team) && isdefined(attacker.team) && attacker.team == self.team)
        return;

    self thread srdroptag(attacker);
}

srdroptag(attacker)
{
    self endon("disconnect");
    level endon("game_ended");

    wait 0.5; // let the body settle

    if (isalive(self))
        return;

    guid = self.guid;
    if (!isdefined(guid))
        return;

    pos = self.origin + (0, 0, 16);

    tag = spawn("script_model", pos);
    tag setmodel("com_cardboardbox06");
    tag.angles = (0, 0, 0);
    tag.owner = self;

    data = spawnstruct();
    data.tag = tag;
    data.victim = self;
    data.team = self.team;
    data.expire = gettime() + SR_TAGLIFE * 1000;
    level.sr_tags[guid] = data;

    self.tagavailable = 1;
    playsoundatpos(pos, "mp_killconfirm_tags_drop");

    level thread srtagwatch(guid);
}

srtagwatch(guid)
{
    level endon("game_ended");

    for (;;)
    {
        wait 0.25;

        if (!isdefined(level.sr_tags[guid]))
            return;

        data = level.sr_tags[guid];

        if (gettime() > data.expire)
        {
            srtagdelete(guid, 0);
            return;
        }

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (distancesquared(player.origin, data.tag.origin) > SR_TAGRADIUS * SR_TAGRADIUS)
                continue;

            if (player.team == data.team)
            {
                level thread srrevive(guid, player, data.tag.origin);
                return;
            }

            srtagdelete(guid, 1);
            return;
        }
    }
}

srtagdelete(guid, confirmed)
{
    if (!isdefined(level.sr_tags[guid]))
        return;

    data = level.sr_tags[guid];

    if (isdefined(data.tag))
    {
        playsoundatpos(data.tag.origin, "mp_killconfirm_tags_pickup");
        data.tag delete();
    }

    level.sr_tags[guid] = undefined;

    if (isdefined(data.victim))
        data.victim.tagavailable = 0;

    if (confirmed)
        level notify("sr_tag_confirmed", data.victim);
}

srrevive(guid, rescuer, pos)
{
    level endon("game_ended");

    if (!isdefined(level.sr_tags[guid]))
        return;

    data = level.sr_tags[guid];

    if (!isdefined(data.victim) || isalive(data.victim))
    {
        srtagdelete(guid, 0);
        return;
    }

    victim = data.victim;
    srtagdelete(guid, 0);

    playsoundatpos(pos, "mp_snd_ally_revive");
    level notify("sr_tag_revived", victim);
    victim.tagavailable = 0;

    victim thread srrespawn();
}

srrespawn()
{
    self endon("disconnect");

    self maps\mp\gametypes\_playerlogic::incrementalivecount(self.team);
    self.alreadyaddedtoalivecount = 1;
    self.pers["lives"] = 1;
    maps\mp\gametypes\_playerlogic::spawnclient();
}

// test hooks (bots cannot walk to a tag on their own)
mwxrescue_revive(player)
{
    level thread srrevive(player.guid, player, player.origin);
}

// test hook: a bot cannot pick a tag up on its own, and the test drives the end deterministically
mwxrescue_confirm(team)
{
    foreach (guid, data in level.sr_tags)
    {
        if (!isdefined(data) || data.team != team)
            continue;
        srtagdelete(guid, 1);
    }
}

mwxrescue_endround(team)
{
    logprint("mwx srescue: end hook called for " + team + " gameending=" + isdefined(level.gameending) +
        " gameended=" + isdefined(level.gameended));
    level thread srendround(team);
}

// --- round end ----------------------------------------------------------------------------

srroundwatch()
{
    level endon("game_ended");
    maps\mp\_utility::gameflagwait("prematch_done");

    for (;;)
    {
        wait 1;

        if (maps\mp\_utility::is_true(level.gameending))
            return;

        allies_alive = 0;
        axis_alive = 0;
        allies_tags = 0;
        axis_tags = 0;

        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (player.team == "allies")
                allies_alive++;
            else if (player.team == "axis")
                axis_alive++;
        }

        if (isdefined(level.sr_tags))
        {
            foreach (guid, data in level.sr_tags)
            {
                if (!isdefined(data))
                    continue;
                if (data.team == "allies")
                    allies_tags++;
                else if (data.team == "axis")
                    axis_tags++;
            }
        }

        if (allies_alive <= 0 && allies_tags <= 0)
        {
            if (getdvarint("mwx_debug_gamemodes", 0))
                logprint("mwx srescue: allies out (alive=0 tags=0), axis wins the round");
            level thread srendround("axis");
            return;
        }

        if (axis_alive <= 0 && axis_tags <= 0)
        {
            if (getdvarint("mwx_debug_gamemodes", 0))
                logprint("mwx srescue: axis out (alive=0 tags=0), allies wins the round");
            level thread srendround("allies");
            return;
        }

        if (getdvarint("mwx_debug_gamemodes", 0))
            logprint("mwx srescue watch: allies alive=" + allies_alive + " tags=" + allies_tags +
                " axis alive=" + axis_alive + " tags=" + axis_tags + " grace=" + level.ingraceperiod +
                " ending=" + isdefined(level.gameending));
    }
}

// a fallback when the time limit hits: most living players wins the round
ontimelimit()
{
    if (maps\mp\_utility::is_true(level.gameending))
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

    if (allies >= axis)
        level thread srendround("allies");
    else
        level thread srendround("axis");
}

ondeadevent(team)
{
    // the round watch decides when a team is really out (tags can revive)
    return;
}

srendround(winner)
{
    level endon("game_ended");

    if (maps\mp\_utility::is_true(level.gameending))
    {
        logprint("mwx srescue: srendround(" + winner + ") skipped, ending=" + isdefined(level.gameending) +
            " ended=" + isdefined(level.gameended));
        return;
    }

    level.gameending = 1;
    level.finalkillcam_winner = winner;

    logprint("mwx srescue: round end, winner=" + winner);

    maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause(2);

    lossteam = "allies";
    if (winner == "allies")
        lossteam = "axis";

    thread maps\mp\gametypes\_gamelogic::endgame(winner, game["end_reason"][lossteam + "_eliminated"]);
}

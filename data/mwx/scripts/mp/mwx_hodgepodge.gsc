// MWX: fixes for the MWR "hodgepodge" party modes in private matches.
// Slasher (hodgepodge 2), which MWR only ran from a playlist:
// - one life: initmmmode sets scr_war_numLives 1 in onstartgametype, after war.gsc already read the
//   private match rules (unlimited lives). Survivors respawned, the survivor count never reached 0, the
//   match never ended and the "final survivor" slasher powers went to several players.
// - match end: the team counters are only counted up on spawn and down on kills, so any extra spawn
//   (respawn, the slasher's class change) left them too high and "all survivors dead" was never
//   detected. The kill handler now recounts the living players of each team.
// - survivor bots: MWR disables firing for all bots (allowfire 0) and makes them flee while the slasher
//   looks at them. Survivor bots may now shoot, and flee only while the slasher is still far away.
//
// The mode is only known after the gametype main() ran (level.hodgepodgemode is set by
// _hodgepodge::init inside war.gsc); this script's init() runs before that in the load pass, so the
// fixes are installed from a thread that waits for the mode.

#define SLASHER_FIGHT_DIST 600

init()
{
    level thread install();
}

install()
{
    waited = 0;
    while (waited < 60 && !isdefined(level.hodgepodgemode))
    {
        wait 0.1;
        waited = waited + 0.1;
    }

    if (!isdefined(level.hodgepodgemode))
        return;

    if (level.hodgepodgemode == 9)
    {
        install_ph();
        return;
    }

    if (level.hodgepodgemode != 2)
        return;

    install_slasher();
}

// Prop Hunt (hodgepodge 9). The stock onspawnplayer starts handleprop() for the defenders and
// handleprop waits for "applyLoadout" to build the prop; the mode class is applied in the same
// frame as the spawn, so on this build the notify arrives before the thread waits and no prop is
// ever created (mp_crash: proplist 25, defenders alive with the hunter weapon, self.prop never
// defined). Repeating the notify after the spawn is the same path a class change uses.
install_ph()
{
    // ph_init() runs inside onstartgametype; wait until its globals exist (proplist from the CSV)
    waited = 0;
    while (waited < 10 && !isdefined(level.proplist))
    {
        wait 0.1;
        waited = waited + 0.1;
    }

    if (!isdefined(level.proplist))
        return;

    // The party ref is level.gametype ("ph"/"mprops"), but MWR's hodgepodge code was written
    // for g_gametype "war": its setupdvars only sets scr_war_* and the watched dvars are
    // scr_<gametype>_*, so getgametypenumlives() stayed 0 (unlimited lives: dead props respawned,
    // the round could never end by elimination). The watched-dvar table is filled before the
    // party ref is known, so override the getter itself.
    replacefunc(maps\mp\_utility::getgametypenumlives, ::ph_numlives_stub);

    if (level.madpropsmode)
    {
        level.numlives = 4;
    }
    else
    {
        level.numlives = 1;
    }

    level.mwx_ph_fix = 1;

    // the lives machinery stays ineffective with the party-ref gametype (see above); MWR asks
    // level.gamemodemayspawn() before every spawn, so one life per round is enforced there
    level.gamemodemayspawn = ::ph_mayspawn;
    level thread ph_onconnect();

    foreach (player in level.players)
        player thread ph_ensure_prop();
}

ph_numlives_stub()
{
    if (level.madpropsmode)
        return 4;
    return 1;
}

// One life per round for the props (see install_ph). `ph_dead_this_round` is stamped by
// ph_watch_death on the player's "death" notify and compared with game["roundsPlayed"], so a
// new round spawns again without depending on the broken lives dvar.
ph_mayspawn(shouldspawn)
{
    if (level.madpropsmode)
        return 1;
    if (!isdefined(self.team) || self.team != game["defenders"])
        return 1;
    if (!maps\mp\_utility::gamehasstarted())
        return 1;
    if (!isdefined(self.ph_dead_this_round))
        return 1;

    rounds = 0;
    if (isdefined(game["roundsPlayed"]))
        rounds = game["roundsPlayed"];

    if (self.ph_dead_this_round == rounds)
        return 0;

    return 1;
}

ph_watch_death()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("death");

        rounds = 0;
        if (isdefined(game["roundsPlayed"]))
            rounds = game["roundsPlayed"];
        self.ph_dead_this_round = rounds;
    }
}

ph_onconnect()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread ph_ensure_prop();
    }
}

ph_ensure_prop()
{
    self endon("disconnect");

    if (!isdefined(self.ph_deathwatch))
    {
        self.ph_deathwatch = 1;
        thread ph_watch_death();
    }

    for (;;)
    {
        wait 0.25;

        if (!isdefined(game["defenders"]) || self.team != game["defenders"])
            continue;

        // this build starts the props with pers["lives"] 0 (the watched numlives dvar was
        // registered before the party ref was known), which made every dead prop respawn and
        // kept the round from ending. Prop Hunt gives the props one life.
        if (!level.madpropsmode && isalive(self) && isdefined(self.pers["lives"]) && self.pers["lives"] <= 0)
            self.pers["lives"] = 1;

        if (isdefined(self.prop))
            continue;
        if (!isalive(self))
            continue;

        self notify("applyLoadout");
    }
}

install_slasher()
{
    // initmmmode() runs in onstartgametype, after the mode is known; it assigns the stock kill
    // handler, so the stub is installed after it
    waited = 0;
    while (waited < 10 && !isdefined(level.mm_chooseslasher))
    {
        wait 0.1;
        waited = waited + 0.1;
    }

    // now that the gametype script is loaded and running, patch its kill/targeting functions
    replacefunc(maps\mp\gametypes\_hodgepodge::botslasheristargetingme, ::botslasheristargetingme_stub);
    replacefunc(maps\mp\gametypes\_hodgepodge::onmmplayerkilled, ::onmmplayerkilled_stub);
    level.onplayerkilled = ::onmmplayerkilled_stub;

    level.numlives = 1;
    setdynamicdvar("scr_war_numlives", 1);
    level.mwx_slasher_fix = 1;
    level thread slasher_onconnect();

    // bots that are already connected
    foreach (player in level.players)
    {
        if (isai(player))
            player thread slasher_botfire();
    }
}

slasher_onconnect()
{
    for (;;)
    {
        level waittill("connected", player);
        if (isai(player))
            player thread slasher_botfire();
    }
}

slasher_botfire()
{
    self endon("disconnect");

    for (;;)
    {
        // onmmspawnplayer ran allowfire(0) for every bot; survivors may shoot. Record it: GSC has
        // no allowfire getter, the game mode test checks mwx_botfire.
        if (self.team == "allies")
        {
            self allowfire(1);
            self.mwx_botfire = 1;
        }

        self waittill("spawned_player");
        waittillframeend;
        if (self.team == "allies")
        {
            self allowfire(1);
            self.mwx_botfire = 1;
        }
    }
}

botslasheristargetingme_stub()
{
    if (!isdefined(level.slasher))
        return 0;

    if (distance(level.slasher.origin, self.origin) < SLASHER_FIGHT_DIST)
    {
        // botmmlogic only clears ignoreall on its 30 s hide timer
        self.ignoreall = 0;
        return 0;
    }

    if (isai(level.slasher))
        return isdefined(level.slasher.enemy) && level.slasher.enemy == self && level.slasher botcanseeentity(self);

    return common_scripts\utility::within_fov(level.slasher geteye(), level.slasher getplayerangles(), self geteye(), 0.422618) && sighttracepassed(level.slasher geteye(), self geteye(), 0, self);
}

alive_on_team(team, ignore)
{
    count = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player) || player == ignore || player.team != team)
            continue;
        if (maps\mp\_utility::isreallyalive(player))
            count++;
    }
    return count;
}

onmmplayerkilled_stub(einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, timeoffset, deathanimduration, killid)
{
    // a death without a player attacker (falling, the world, a suicide) counts once the slasher is
    // chosen; before that the vanilla rule (no attacker = ignored) kept the survivor counts too high
    if ((!isdefined(attacker) || attacker == self || !isplayer(attacker)) && !level.mm_allowsuicide)
        return;

    level notify("update_game_time");
    level.mm_teamscores["allies"] = alive_on_team("allies", self);
    level.mm_teamscores["axis"] = alive_on_team("axis", self);
    maps\mp\gametypes\_hodgepodge::updateteamscores();

    if (self.team == "allies")
    {
        maps\mp\_utility::playsoundonplayers("mp_enemy_obj_captured", "allies");
        maps\mp\_utility::playsoundonplayers("mp_war_objective_taken", "axis");
    }

    level thread maps\mp\_utility::teamplayercardsplash("callout_eliminated", self, self.team);

    if (level.mm_teamscores["allies"] == 0)
    {
        maps\mp\gametypes\_hodgepodge::onsurvivorseliminated();
        return;
    }

    if (level.mm_teamscores["axis"] == 0)
    {
        maps\mp\gametypes\_hodgepodge::onslashereliminated();
        return;
    }

    if (level.mm_teamscores["allies"] == 1)
        maps\mp\gametypes\_hodgepodge::onfinalsurvivor();
}

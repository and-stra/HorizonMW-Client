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
// handleprop()/givecustomloadout() wait for "applyLoadout" to build the prop. HMW's _class only
// notifies "applyloadout" (lower case) on this build, and GSC notifies are case-sensitive, so the
// camel-case wait never fires and no prop is created (mp_crash: proplist 25, defenders alive with
// the hunter weapon, self.prop never defined).
//
// Fix: an event bridge - one thread per player that turns every "applyloadout" into the
// "applyLoadout" the H1 scripts wait for. (ph_notify_probe logs the case behaviour of the build.)
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

    level.mwx_ph_fix = 1;

    // log the notify case behaviour of this build once per match
    level thread ph_notify_probe();

    // Lives/limits: gamemodes.cpp sets the scr_<ref>_* defaults before the map loads (war.gsc
    // registers its watched dvars from them). Keep the host migration path working: the stock
    // setupdvars() hard-codes scr_war_*, this copy writes scr_<level.gametype>_*.
    replacefunc(maps\mp\gametypes\_hodgepodge_ph::setupdvars, ::ph_setupdvars_stub);

    level thread ph_onconnect();

    foreach (player in level.players)
    {
        player thread ph_bridge();
        player thread ph_spawn_kick();
    }

    logprint("mwx ph: install done (bridge + limits), proplist=" + level.proplist.size +
        " madprops=" + level.madpropsmode + " debug=" + getdvarint("mwx_debug_gamemodes", 0));

    if (getdvarint("mwx_debug_gamemodes", 0))
        level thread ph_diag();
}

// mwx_debug_gamemodes 1: every 2 s, the counters the round end depends on (see the ph test)
ph_diag()
{
    level endon("game_ended");
    logprint("mwx ph diag: started");

    for (;;)
    {
        wait 2;

        numlives = -1;
        key = "scr_" + level.gametype + "_numlives";
        if (isdefined(level.watchdvars) && isdefined(level.watchdvars[key]))
            numlives = level.watchdvars[key].value;

        rounds = -1;
        if (isdefined(game["roundsPlayed"]))
            rounds = game["roundsPlayed"];

        ending = -1;
        if (isdefined(level.gameending))
            ending = level.gameending;

        allies_alive = -1;
        axis_alive = -1;
        allies_lives = -1;
        axis_lives = -1;
        if (isdefined(level.alivecount))
        {
            allies_alive = level.alivecount["allies"];
            axis_alive = level.alivecount["axis"];
        }
        if (isdefined(level.livescount))
        {
            allies_lives = level.livescount["allies"];
            axis_lives = level.livescount["axis"];
        }

        text = "mwx ph diag: gt=" + level.gametype + " numlives=" + numlives +
            " alive=" + allies_alive + "/" + axis_alive + " lives=" + allies_lives + "/" + axis_lives +
            " rounds=" + rounds + " ending=" + ending;

        foreach (player in level.players)
        {
            if (!isdefined(player.team))
                continue;

            lives = -1;
            if (isdefined(player.pers) && isdefined(player.pers["lives"]))
                lives = player.pers["lives"];

            text = text + " | " + player.name + " " + player.team + " alive=" + isalive(player) + " lives=" + lives;
        }

        logprint(text);
    }
}

// same values as maps\mp\gametypes\_hodgepodge_ph.gsc setupdvars(), with the mode's dvar prefix
ph_setupdvars_stub()
{
    prefix = "scr_" + level.gametype + "_";
    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar(prefix + "timelimit", 4);
    setdynamicdvar(prefix + "scorelimit", 0);
    setdynamicdvar(prefix + "roundlimit", 4);
    setdynamicdvar(prefix + "winlimit", 3);
    maps\mp\_utility::registerwinlimitdvar(level.gametype, 3);
    setdynamicdvar(prefix + "roundswitch", 1);
    maps\mp\_utility::registerroundswitchdvar(level.gametype, 1, 0, 9);
    setdynamicdvar(prefix + "halftime", 0);

    if (level.madpropsmode)
    {
        setdynamicdvar(prefix + "numlives", 4);
        return;
    }

    setdynamicdvar(prefix + "numlives", 1);
    setdynamicdvar("scr_player_healthregen", 0);
    level.roundswitch = getdvarint(prefix + "roundswitch");

    if (maps\mp\_utility::getmapname() == "mp_shipment")
    {
        setdynamicdvar("g_oldschool", 1);
        setdynamicdvar(prefix + "timelimit", 2.2);
    }
}

// R1a: prove the notify case in the log. Two waits on the same name in different case, one
// notify: both counters 1 = case-insensitive (then the bridge is not the fix), camel 1 / lower 0
// = case-sensitive (the reason HMW's lower-case notify never reached handleprop).
ph_notify_probe()
{
    level endon("game_ended");
    level.mwx_ph_case_camel = 0;
    level.mwx_ph_case_lower = 0;

    level thread ph_case_wait_camel();
    level thread ph_case_wait_lower();

    wait 0.1;
    level notify("mwxphcaseprobeCamel");
    wait 0.3;

    logprint("mwx ph: notify case probe: notify camel -> camelWait=" + level.mwx_ph_case_camel +
        " lowerWait=" + level.mwx_ph_case_lower);
}

ph_case_wait_camel()
{
    level waittill("mwxphcaseprobeCamel");
    level.mwx_ph_case_camel = 1;
}

ph_case_wait_lower()
{
    level waittill("mwxphcaseprobelower");
    level.mwx_ph_case_lower = 1;
}

// Event bridge: HMW's _class notifies "applyloadout" (lower case) after it applied the class;
// H1's handleprop()/givecustomloadout() wait for "applyLoadout". One thread per player.
ph_bridge()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("applyloadout");
        self notify("applyLoadout");
        level.mwx_ph_bridge = 1;
    }
}

ph_onconnect()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("connected", player);
        player thread ph_bridge();
        player thread ph_spawn_kick();
    }
}

// The engine's first "applyloadout" of a spawn is notified before onspawnplayer's handleprop()
// thread reaches its waittill on this build (measured: bridge=1, prop undefined). One notify after
// the spawn - when handleprop is definitely waiting - gives the initial prop its loadout event.
ph_spawn_kick()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("spawned_player");
        waittillframeend;
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

    // Lives/limits: same root fix as Prop Hunt - gamemodes.cpp sets scr_slasher_* before the map
    // loads, setupdvarsmm() runs later and hard-codes scr_war_*. The copy writes level.gametype's
    // prefix so host migration and later reads see the mode's values.
    replacefunc(maps\mp\gametypes\_hodgepodge::setupdvarsmm, ::mm_setupdvars_stub);

    level.mwx_slasher_fix = 1;
    level thread slasher_onconnect();

    // bots that are already connected
    foreach (player in level.players)
    {
        if (isai(player))
            player thread slasher_botfire();
    }
}

// maps\mp\gametypes\_hodgepodge.gsc setupdvarsmm() with the mode's own dvar prefix
mm_setupdvars_stub()
{
    prefix = "scr_" + level.gametype + "_";
    setdynamicdvar("scr_game_hardpoints", 0);
    setdynamicdvar(prefix + "timelimit", 10);
    setdynamicdvar(prefix + "numlives", 1);
    setdynamicdvar("g_oldschool", 1);
    setdynamicdvar("scr_game_mmUavTime", 30);
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

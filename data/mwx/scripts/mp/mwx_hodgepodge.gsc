// MWX: fixes for the MWR "hodgepodge" party modes in private matches.
// - Snipers Only: MWR only restricted classes through the playlist; in a private match any class
//   could be used. Non-sniper primaries are replaced with a sniper rifle.
// - Slasher: survivor bots set ignoreall while the slasher looks at them, so they only ran and never
//   shot back. They now flee only while the slasher is still far away, and fight once it is close.

#define SNIPERS_DEFAULT "h2_cheytac"
#define SLASHER_FIGHT_DIST 600

main()
{
    replacefunc(maps\mp\gametypes\_hodgepodge::botslasheristargetingme, ::botslasheristargetingme_stub);
}

init()
{
    if (!isdefined(level.hodgepodgemode) || level.hodgepodgemode != 4)
        return;

    level thread snipers_onconnect();
}

snipers_onconnect()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread snipers_watchloadout();
    }
}

snipers_watchloadout()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("applyLoadout");
        // _hodgepodge::giveprimaryonlynomelee runs on the same notify; let it finish first
        waittillframeend;

        if (!isdefined(self.primaryweapon) || weaponclass(self.primaryweapon) == "sniper")
            continue;

        weapon = maps\mp\gametypes\_class::buildweaponname(SNIPERS_DEFAULT, "none", "none", "none", []);
        self takeallweapons();
        self allowmelee(0);
        self giveweapon(weapon);
        self givestartammo(weapon);
        self setspawnweapon(weapon);
        self switchtoweapon(weapon);
        self.primaryweapon = weapon;
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

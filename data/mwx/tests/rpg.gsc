// MWX test: RPG Only (hodgepodge mode 6 on top of war.gsc: h1_rpg_mp only, unlimited ammo).
//
// The mode's refill loop sets the stock to 2 and refills after every reload (mode 6 keeps a small
// stock; mode 7 refills the clip after every shot).

#include mwx\tests\_test;

main()
{
    test_step("wait for the players");

    players = test_wait_players(4, 120);
    test_assert(players >= 4, "players spawned", ">=4", players);

    test_step("loadout");

    first = undefined;
    badloadout = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (!isdefined(first))
            first = player;

        if (!(player hasweapon("h1_rpg_mp")))
            badloadout++;

        // only the RPG (and HMW's default offhands)
        primaries = player getweaponslistprimaries();
        if (primaries.size != 1 || primaries[0] != "h1_rpg_mp")
            badloadout++;
    }

    test_assert(badloadout == 0, "everyone has only the RPG", "0", badloadout);
    test_assert(level.rpgonlyreload == 1, "rpg mode 6 (stock refill)", "1", level.rpgonlyreload);

    if (isdefined(first))
    {
        test_assert(test_has_perk(first, "specialty_fastreload"), "fast reload perk", "1",
            test_has_perk(first, "specialty_fastreload"));

        test_step("unlimited ammo");

        first setweaponammostock("h1_rpg_mp", 0);
        wait 0.2;
        test_assert(first getweaponammostock("h1_rpg_mp") == 0, "stock emptied", "0",
            first getweaponammostock("h1_rpg_mp"));

        // the refill loop waits for the reload notify and sets the stock back to 2
        first notify("reload");
        wait 0.5;

        ammo = first getweaponammostock("h1_rpg_mp");
        test_assert(ammo == 2, "reload refills the stock", "2", ammo);
    }
    else
    {
        test_assert(0, "a living player", "player", "none");
    }

    test_done(1);
}

// MWX test mod: proves the mod system loads a mod's scripts without any weapons or zones.
// The loader runs scripts/mp/*.gsc from the mod folder like the game's own scripts.

main()
{
    level thread mwx_test_mod_main();
}

mwx_test_mod_main()
{
    wait 0.5;
    print("[test_mod] loaded");
    setdvar("mwx_test_mod_loaded", 1);
}

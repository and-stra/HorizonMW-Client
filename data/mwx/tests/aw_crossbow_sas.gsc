// MWX test: Sticks and Stones still gives its crossbow with hmw_aw_weapons loaded (T1).
//
// The mod's sas gametype gives iw5_exocrossbow_mp; the mod.ff only references the weapon, so
// this test fails if the mod or the zone reference is broken.

#include tests\aw_weapon;

main()
{
    aw_sas_test("iw5_exocrossbow_mp");
}

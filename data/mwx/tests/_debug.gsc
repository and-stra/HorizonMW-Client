// MWX test interface: game-side helpers (see docs/mcp.md and docs/testing.md).
//
// This script is NOT loaded in a normal match: the debug interface loads it on demand with
// Scr_LoadScript("mwx/tests/_debug") the first time one of the RPCs needs server state.
// Parameters are passed in the string dvars mwx_debug_arg0..5, results come back through the
// MWX builtin mwx_result(<string>) as JSON text.
// (No #include: everything used here is a builtin, so the file cannot fail to link.)

// escape a string for the JSON strings we build by hand (names can contain quotes)
mwx_debug_escape(value)
{
    if (!isdefined(value))
        return "";

    text = "" + value;
    result = "";
    length = text.size;

    for (index = 0; index < length; index++)
    {
        // H1: getsubstr(string, start, end), end exclusive
        character = getsubstr(text, index, index + 1);
        if (character == "\"" || character == "\\")
            result = result + "\\" + character;
        else if (character == "\n" || character == "\r" || character == "\t")
            result = result + " ";
        else
            result = result + character;
    }

    return result;
}

mwx_debug_json_string(value)
{
    return "\"" + mwx_debug_escape(value) + "\"";
}

mwx_debug_number(value)
{
    if (!isdefined(value))
        return "0";

    return "" + value;
}

mwx_debug_bool(value)
{
    if (isdefined(value) && value)
        return "true";

    return "false";
}

mwx_debug_weapons(player)
{
    result = "[";
    first = 1;

    weapons = player getweaponslistall();
    if (isdefined(weapons))
    {
        foreach (weapon in weapons)
        {
            if (!first)
                result = result + ",";
            first = 0;

            result = result + "{\"name\":" + mwx_debug_json_string(weapon);
            result = result + ",\"clip\":" + mwx_debug_number(player getweaponammoclip(weapon));
            result = result + ",\"stock\":" + mwx_debug_number(player getweaponammostock(weapon)) + "}";
        }
    }

    return result + "]";
}

mwx_debug_perks(player)
{
    result = "[";
    first = 1;

    if (isdefined(player.perks))
    {
        foreach (perk, value in player.perks)
        {
            if (!isdefined(value) || !value)
                continue;

            if (!first)
                result = result + ",";
            first = 0;
            result = result + mwx_debug_json_string(perk);
        }
    }

    return result + "]";
}

mwx_debug_players()
{
    result = "[";
    first = 1;

    foreach (player in level.players)
    {
        if (!isdefined(player))
            continue;

        if (!first)
            result = result + ",";
        first = 0;

        team = "";
        if (isdefined(player.team))
            team = player.team;

        playerclass = "";
        if (isdefined(player.class))
            playerclass = player.class;

        currentweapon = player getcurrentweapon();
        if (!isdefined(currentweapon))
            currentweapon = "";

        number = player getentitynumber();

        result = result + "{";
        result = result + "\"num\":" + mwx_debug_number(number);
        result = result + ",\"name\":" + mwx_debug_json_string(player.name);
        result = result + ",\"bot\":" + mwx_debug_bool(isbot(player));
        result = result + ",\"team\":" + mwx_debug_json_string(team);
        result = result + ",\"alive\":" + mwx_debug_bool(isalive(player));
        result = result + ",\"health\":" + mwx_debug_number(player.health);
        result = result + ",\"score\":" + mwx_debug_number(player.score);
        result = result + ",\"kills\":" + mwx_debug_number(player.kills);
        result = result + ",\"deaths\":" + mwx_debug_number(player.deaths);
        result = result + ",\"origin\":[" + mwx_debug_number(player.origin[0]) + "," +
            mwx_debug_number(player.origin[1]) + "," + mwx_debug_number(player.origin[2]) + "]";
        result = result + ",\"angles\":[" + mwx_debug_number(player.angles[0]) + "," +
            mwx_debug_number(player.angles[1]) + "," + mwx_debug_number(player.angles[2]) + "]";
        result = result + ",\"current_weapon\":" + mwx_debug_json_string(currentweapon);
        result = result + ",\"weapons\":" + mwx_debug_weapons(player);
        result = result + ",\"perks\":" + mwx_debug_perks(player);
        result = result + ",\"class\":" + mwx_debug_json_string(playerclass);
        result = result + "}";
    }

    mwx_result(result + "]");
}

mwx_debug_entities()
{
    classname = getdvar("mwx_debug_arg0");
    targetname = getdvar("mwx_debug_arg1");
    limit = int(getdvar("mwx_debug_arg2"));
    origin_text = getdvar("mwx_debug_arg3");
    radius = float(getdvar("mwx_debug_arg4"));
    uses_origin = origin_text != "" && radius > 0;

    origin = (0, 0, 0);
    if (uses_origin)
    {
        parts = strtok(origin_text, " ");
        origin = (float(parts[0]), float(parts[1]), float(parts[2]));
    }

    result = "[";
    first = 1;
    count = 0;

    entities = getentarray();
    if (isdefined(entities))
    {
        foreach (entity in entities)
        {
            if (!isdefined(entity))
                continue;

            if (classname != "" && (!isdefined(entity.classname) || entity.classname != classname))
                continue;

            if (targetname != "" && (!isdefined(entity.targetname) || entity.targetname != targetname))
                continue;

            if (uses_origin && distance(origin, entity.origin) > radius)
                continue;

            if (!first)
                result = result + ",";
            first = 0;

            model = "";
            if (isdefined(entity.model))
                model = entity.model;

            target = "";
            if (isdefined(entity.targetname))
                target = entity.targetname;

            number = entity getentitynumber();

            result = result + "{";
            result = result + "\"num\":" + mwx_debug_number(number);
            result = result + ",\"classname\":" + mwx_debug_json_string(entity.classname);
            result = result + ",\"targetname\":" + mwx_debug_json_string(target);
            result = result + ",\"model\":" + mwx_debug_json_string(model);
            result = result + ",\"origin\":[" + mwx_debug_number(entity.origin[0]) + "," +
                mwx_debug_number(entity.origin[1]) + "," + mwx_debug_number(entity.origin[2]) + "]";
            result = result + "}";

            count++;
            if (count >= limit)
                break;
        }
    }

    mwx_result(result + "]");
}

mwx_debug_bots()
{
    action = getdvar("mwx_debug_arg0");
    num = int(getdvar("mwx_debug_arg1"));

    entity = getentbynum(num);
    if (!isdefined(entity))
    {
        mwx_result("error: entity " + num + " does not exist");
        return;
    }

    if (action == "freeze")
    {
        entity freezecontrols(true);
        mwx_result("frozen " + num);
    }
    else if (action == "unfreeze")
    {
        entity freezecontrols(false);
        mwx_result("unfrozen " + num);
    }
    else
    {
        mwx_result("error: unknown bot action " + action);
    }
}

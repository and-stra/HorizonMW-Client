// MWX game mode test helpers (see docs/testing.md).
//
// Test scripts #include this file and report through mwx_event(); the MCP bridge collects the
// events and builds the summary (passed / failed / failures).

mwx_test_escape(value)
{
    if (!isdefined(value))
        return "";

    text = "" + value;
    result = "";

    for (index = 0; index < text.size; index++)
    {
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

test_step(name)
{
    mwx_event("test_step", "{\"step\":\"" + mwx_test_escape(name) + "\"}", "test");
    mwx_test_log("step: " + name);
}

test_log(text)
{
    mwx_test_log("" + text);
}

test_assert(condition, name, expected, actual)
{
    ok = 0;
    if (isdefined(condition) && condition)
        ok = 1;

    mwx_event("test_assert", "{\"ok\":" + ok +
        ",\"name\":\"" + mwx_test_escape(name) +
        "\",\"expected\":\"" + mwx_test_escape(expected) +
        "\",\"actual\":\"" + mwx_test_escape(actual) + "\"}", "test");

    mwx_test_log((ok ? "PASS " : "FAIL ") + name + " (expected " + expected + ", got " + actual + ")");
    return ok;
}

test_done(ok)
{
    mwx_event("test_done", "{\"ok\":" + (ok ? 1 : 0) + "}", "test");
    mwx_test_log("done");
}

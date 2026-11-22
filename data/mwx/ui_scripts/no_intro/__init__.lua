-- MWX: skip HMW's startup video ("main_attract") and go straight to the main menu.
if not Engine.InFrontend() or not Engine.IsMultiplayer() then
    return
end

Engine.Exec("set startup_video_played 1")

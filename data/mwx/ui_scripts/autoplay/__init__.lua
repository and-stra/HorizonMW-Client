if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
if not Engine.GetDvarBool("mwx_autoplay") then return end
Engine.Exec("set startup_video_played 1")
local hmw_main_menu = LUI.MenuBuilder.m_types_build["mp_main_menu"]
if hmw_main_menu then
  LUI.MenuBuilder.m_types_build["mp_main_menu"] = function(menu, event)
    local m = hmw_main_menu(menu, event)
    if Engine.GetDvarBool("mwx_autoplay") and not Engine.GetDvarBool("mwx_autoplay_done") then
      m:registerEventHandler("mwx_autoplay", function(element, ev)
        Engine.Exec("set mwx_autoplay_done 1")
        OnPlayButton(element, { controller = 0 })
      end)
      m:addElement(LUI.UITimer.new(250, "mwx_autoplay", nil, true))
    end
    return m
  end
end

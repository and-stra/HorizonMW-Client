-- MWX: show HMW's own loading animation (material "hmw_loading_animation", an 8x8 flipbook in
-- hmw_patch_code_post_gfx_mp) instead of the MW2 one, like the official HMW client does.
if CoD and CoD.Material then
    CoD.Material.LoadingAnim = "hmw_loading_animation"
end

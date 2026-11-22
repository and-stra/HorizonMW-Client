#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "scheduler.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include <utils/string.hpp>

#include <algorithm>
#include <cmath>

// MWX: m_ads_sensitivity_scale, the behaviour of the current official HMW client (see docs/hmw-diff.md):
// while aiming down sights, sensitivity = normal * lerp(1, scale, ads fraction). The normal value is
// restored when cgame is not running, so the saved config never keeps an ADS value. Not on exit: at
// pre_destroy the dvar system is already gone and writing the dvar crashed (17:19 dump,
// ads_sensitivity.cpp restore -> Dvar_SetFromStringByNameFromSource).
namespace ads_sensitivity
{
	namespace
	{
		constexpr auto ads_fraction_offset = 0x39C; // float in cg_s, 0 = hip, 1 = fully aimed

		bool active = false;
		float base_value = 0.0f;
		float last_written = 0.0f;

		void write_sensitivity(const float value)
		{
			game::Dvar_SetFromStringByNameFromSource("sensitivity", utils::string::va("%f", value),
				game::DVAR_SOURCE_INTERNAL);
			last_written = value;
		}

		void restore()
		{
			if (active)
			{
				write_sensitivity(base_value);
				active = false;
			}
		}

		void frame()
		{
			const auto* sensitivity = game::Dvar_FindVar("sensitivity");
			const auto* scale = game::Dvar_FindVar("m_ads_sensitivity_scale");
			if (!sensitivity || !scale)
			{
				return;
			}

			if (!game::CL_IsCgameInitialized())
			{
				restore();
				return;
			}

			auto* cg = game::getCGArray();
			if (!cg)
			{
				return;
			}

			auto fraction = *reinterpret_cast<float*>(reinterpret_cast<char*>(cg) + ads_fraction_offset);
			if (!std::isfinite(fraction))
			{
				fraction = 0.0f;
			}
			fraction = std::clamp(fraction, 0.0f, 1.0f);

			const auto current = sensitivity->current.value;
			if (!active)
			{
				base_value = current;
				last_written = current;
				active = true;
			}
			else if (fraction <= 0.0f && std::abs(current - last_written) > 0.001f)
			{
				// the user changed the sensitivity while not aiming
				base_value = current;
				last_written = current;
			}

			const auto target = base_value * (1.0f + (scale->current.value - 1.0f) * fraction);
			if (std::abs(current - target) > 0.001f)
			{
				write_sensitivity(target);
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			scheduler::once([]()
			{
				dvars::register_float("m_ads_sensitivity_scale", 1.0f, 0.0f, 5.0f, game::DVAR_FLAG_SAVED,
					"Mouse sensitivity multiplier when aiming down sights (1.0 = same as hip fire)");
			}, scheduler::pipeline::main);

			scheduler::loop(frame, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(ads_sensitivity::component)

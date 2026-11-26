#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "load_timing.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"

#include <utils/io.hpp>
#include <utils/string.hpp>

// MWX: measures where startup and map load time goes.
// Every fastfile the game starts reading is logged with the time since the process started
// and how long the previous one took (zones are read one after another, so a zone's time
// runs until the next one starts). Milestones (database ready, main menu, server up) are
// logged too. Output: console + mwx-logs\load_times.log (appended, one block per start).

namespace load_timing
{
	namespace
	{
		using clock = std::chrono::steady_clock;
		const auto process_start = clock::now();

		std::mutex mutex;
		std::atomic_bool console_ready{false};
		std::string last_zone;
		clock::time_point last_zone_start{};

		std::mutex startup_lock_mutex;
		HANDLE startup_lock_handle = nullptr;
		bool startup_lock_owned = false;

		double since_start_ms(const clock::time_point t)
		{
			return std::chrono::duration<double, std::milli>(t - process_start).count();
		}

		void write_line(const std::string& line)
		{
			if (console_ready)
			{
				console::info("[load_timing] %s\n", line.data());
			}
			utils::io::write_file("mwx-logs/load_times.log", line + "\n", true);
		}

		// closes the running zone (if any); mutex must be held
		void finish_last_zone(const clock::time_point now, const char* reason)
		{
			if (last_zone.empty())
			{
				return;
			}

			const auto took = std::chrono::duration<double, std::milli>(now - last_zone_start).count();
			write_line(utils::string::va("%10.0f ms  done   %-40s %8.0f ms (%s)",
				since_start_ms(now), last_zone.data(), took, reason));
			last_zone.clear();
		}
	}

	void zone_start(const char* name)
	{
		const auto now = clock::now();
		std::lock_guard _(mutex);

		finish_last_zone(now, "next zone started");

		last_zone = name ? name : "?";
		last_zone_start = now;
		write_line(utils::string::va("%10.0f ms  start  %s", since_start_ms(now), last_zone.data()));
	}

	void begin(const bool dedicated)
	{
		utils::io::write_file("mwx-logs/load_times.log",
			utils::string::va("\n==== MWX start (%s) ====\n", dedicated ? "dedicated" : "client"), true);
	}

	void acquire_startup_lock()
	{
		// HMW's engine init cannot overlap with another instance's early init: a second
		// process started while the first is still loading its zones exits silently (no
		// console output, no crash dump). The window is short (~15 s), so serialize only
		// the init phase; map load and the running server/game stay concurrent. The mutex
		// is released on the first main-thread frame. A crashing process abandons it and
		// Windows hands it to the next waiter (WAIT_ABANDONED).
		startup_lock_handle = CreateMutexA(nullptr, FALSE, "Local\\mwx-startup-lock");
		if (!startup_lock_handle)
		{
			mark("startup lock: CreateMutex failed");
			return;
		}

		const auto start = clock::now();
		const auto wait = WaitForSingleObject(startup_lock_handle, 180000);
		if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED)
		{
			{
				std::lock_guard _guard(startup_lock_mutex);
				startup_lock_owned = true;
			}

			const auto waited = std::chrono::duration<double, std::milli>(clock::now() - start).count();
			if (waited >= 200.0)
			{
				mark(utils::string::va("startup lock acquired after %.0f ms", waited));
			}

			// Fallback: if the game never reaches its first frame (failed load, a mod that
			// skips the scheduler), do not block the next instance forever.
			std::thread([]()
				{
					std::this_thread::sleep_for(std::chrono::seconds(45));
					release_startup_lock();
				}).detach();
			return;
		}

		// Timeout or wait failure: let this instance start anyway; the runner also retries.
		CloseHandle(startup_lock_handle);
		startup_lock_handle = nullptr;
		mark(utils::string::va("startup lock wait failed (%lu)", wait));
	}

	void release_startup_lock()
	{
		std::lock_guard _guard(startup_lock_mutex);
		if (startup_lock_owned)
		{
			ReleaseMutex(startup_lock_handle);
			startup_lock_owned = false;
		}
		if (startup_lock_handle)
		{
			CloseHandle(startup_lock_handle);
			startup_lock_handle = nullptr;
		}
	}

	void mark(const std::string& event)
	{
		const auto now = clock::now();
		std::lock_guard _(mutex);

		finish_last_zone(now, event.data());
		write_line(utils::string::va("%10.0f ms  ---- %s ----", since_start_ms(now), event.data()));
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			console_ready = true;
			mark("client hooks installed");

			// first frame of the game's main thread
			scheduler::once([]()
			{
				mark("first main-thread frame");
				release_startup_lock();
			}, scheduler::pipeline::main);

			if (game::environment::is_dedi())
			{
				scheduler::schedule([]()
				{
					const auto* sv_running = game::Dvar_FindVar("sv_running");
					if (sv_running && sv_running->current.enabled)
					{
						mark("server running");
						return scheduler::cond_end;
					}
					return scheduler::cond_continue;
				}, scheduler::pipeline::main, 50ms);
				return;
			}

			// main menu: the virtual lobby (the 3D room behind the menu) is up
			scheduler::schedule([]()
			{
				if (game::VirtualLobby_Loaded())
				{
					mark("main menu (virtual lobby loaded)");
					return scheduler::cond_end;
				}
				return scheduler::cond_continue;
			}, scheduler::pipeline::main, 50ms);

			// every map load: log when the client's game (cgame) is up
			scheduler::loop([]()
			{
				static bool was_ingame = false;
				const auto ingame = game::CL_IsCgameInitialized() && !game::VirtualLobby_Loaded();
				if (ingame && !was_ingame)
				{
					const auto* mapname = game::Dvar_FindVar("mapname");
					mark(utils::string::va("in game on %s", mapname ? mapname->current.string : "?"));
				}
				was_ingame = ingame;
			}, scheduler::pipeline::main, 50ms);
		}
	};
}

REGISTER_COMPONENT(load_timing::component)

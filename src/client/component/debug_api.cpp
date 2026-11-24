#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "console.hpp"
#include "debug_api.hpp"
#include "debug_server.hpp"
#include "dvars.hpp"
#include "fps.hpp"
#include "logfile.hpp"
#include "scheduler.hpp"
#include "scripting.hpp"
#include "ui_debug.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"
#include "game/scripting/execution.hpp"
#include "game/scripting/script_value.hpp"

#include "component/gsc/script_extension.hpp"
#include "component/gsc/script_loading.hpp"

#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/string.hpp>

#include <algorithm>
#include <cctype>
#include <cstdlib>

// MWX: implementation of the test interface RPC methods (see docs/mcp.md and docs/testing.md).
//
// Game state is read on the game's threads; the debug server hands the calls over with
// debug_server::run_on. GSC access goes through small helper functions in
// data/mwx/tests/_debug.gsc, which are only loaded when the interface is used (never in a
// normal match).

namespace debug_api
{
	namespace
	{
		using json = nlohmann::json;
		const auto process_start = std::chrono::steady_clock::now();

		// ---------------------------------------------------------------- events

		struct event_t
		{
			std::uint64_t id{};
			std::uint64_t time_ms{};
			std::string type;
			std::string source;
			json data{};
		};

		std::mutex events_mutex;
		std::deque<event_t> event_buffer;
		std::uint64_t next_event_id = 1;
		constexpr std::size_t max_events = 5000;

		std::uint64_t last_event_id()
		{
			std::lock_guard _(events_mutex);
			return next_event_id - 1;
		}

		json event_since(const std::uint64_t id, const std::string& type_filter, const int limit)
		{
			std::lock_guard _(events_mutex);

			json result = json::array();
			for (const auto& event : event_buffer)
			{
				if (event.id <= id)
				{
					continue;
				}

				if (!type_filter.empty() && event.type != type_filter)
				{
					continue;
				}

				result.emplace_back(json{{"id", event.id}, {"time_ms", event.time_ms}, {"type", event.type},
					{"source", event.source}, {"data", event.data}});

				if (limit > 0 && static_cast<int>(result.size()) >= limit)
				{
					break;
				}
			}

			return result;
		}

		std::uint64_t process_time_ms()
		{
			return std::chrono::duration_cast<std::chrono::milliseconds>(
				std::chrono::steady_clock::now() - process_start).count();
		}

		void event_from_gsc(const std::string& type, const std::string& source, const std::string& data)
		{
			json parsed{};
			if (!data.empty())
			{
				try
				{
					parsed = json::parse(data);
				}
				catch (...)
				{
					parsed = json{{"text", data}};
				}
			}

			push_event(type, source, std::move(parsed));
		}

		std::vector<std::string> split_fields(const std::string& line, const char separator)
		{
			std::vector<std::string> fields;
			std::string current;
			for (const auto c : line)
			{
				if (c == separator)
				{
					fields.push_back(current);
					current.clear();
				}
				else
				{
					current.push_back(c);
				}
			}
			fields.push_back(current);
			return fields;
		}

		// games_mp.log lines: K;attacker;client;team;name;victim;client;team;name;weapon;damage;mod;hitloc
		void parse_game_log(const std::string& line)
		{
			if (line.size() < 2 || line[1] != ';')
			{
				return;
			}

			const auto fields = split_fields(line, ';');
			const auto at = [&](const std::size_t index) -> std::string
			{
				if (index >= fields.size())
				{
					return {};
				}

				auto value = fields[index];
				while (!value.empty() && (value.back() == '\n' || value.back() == '\r' || value.back() == ' '))
				{
					value.pop_back();
				}
				return value;
			};

			switch (line[0])
			{
			case 'K':
				push_event("kill", "game", json{
					{"attacker", {{"id", at(1)}, {"num", at(2)}, {"team", at(3)}, {"name", at(4)}}},
					{"victim", {{"id", at(5)}, {"num", at(6)}, {"team", at(7)}, {"name", at(8)}}},
					{"weapon", at(9)}, {"damage", at(10)}, {"means_of_death", at(11)}, {"hit_location", at(12)}
				});
				break;
			case 'D':
				push_event("damage", "game", json{
					{"victim", {{"id", at(1)}, {"num", at(2)}, {"team", at(3)}, {"name", at(4)}}},
					{"attacker", {{"id", at(5)}, {"num", at(6)}, {"team", at(7)}, {"name", at(8)}}},
					{"weapon", at(9)}, {"damage", at(10)}, {"means_of_death", at(11)}, {"hit_location", at(12)}
				});
				break;
			case 'J':
				push_event("join", "game", json{{"id", at(1)}, {"num", at(2)}, {"name", at(3)}});
				break;
			case 'Q':
				push_event("quit", "game", json{{"id", at(1)}, {"num", at(2)}, {"name", at(3)}});
				break;
			default:
				break;
			}
		}

		std::string variable_value_string(const scripting::script_value& value)
		{
			try
			{
				return value.to_string();
			}
			catch (...)
			{
				return {};
			}
		}

		void on_script_notify(const std::string& name, const unsigned int entity,
			const std::vector<scripting::script_value>& arguments)
		{
			json data{};
			data["entity"] = entity;

			if (!arguments.empty())
			{
				json args = json::array();
				for (const auto& argument : arguments)
				{
					args.emplace_back(variable_value_string(argument));
				}
				data["arguments"] = std::move(args);
			}

			if (name == "game_ended")
			{
				data["winner"] = arguments.empty() ? "" : variable_value_string(arguments.front());
				push_event("match_end", "script", std::move(data));
				return;
			}

			if (name == "joined_team")
			{
				push_event("team_change", "script", std::move(data));
				return;
			}

			if (name == "spawned_player" || name == "spawned")
			{
				push_event("spawn", "script", std::move(data));
				return;
			}

			if (name == "connected" || name == "disconnect")
			{
				push_event(name == "connected" ? "connect" : "disconnect", "script", std::move(data));
			}
		}

		void on_console(const int type, const std::string& message)
		{
			auto text = message;
			while (!text.empty() && (text.back() == '\n' || text.back() == '\r'))
			{
				text.pop_back();
			}

			if (text.empty())
			{
				return;
			}

			const auto lower = utils::string::to_lower(text);

			// test results are printed as "[mwx-test] {json}"
			if (text.starts_with("[mwx-test] "))
			{
				json data{};
				try
				{
					data = json::parse(text.substr(11));
				}
				catch (...)
				{
					data = json{{"text", text}};
				}

				if (data.is_object() && data.contains("event"))
				{
					const auto event_name = data.value("event", "test");
					data.erase("event");
					push_event(event_name, "test", std::move(data));
				}
				else
				{
					push_event("test_log", "test", std::move(data));
				}
				return;
			}

			if (lower.find("script error") != std::string::npos || lower.find("script runtime error") != std::string::npos)
			{
				push_event("script_error", "console", json{{"text", text}});
				return;
			}

			if (type == console::con_type_error)
			{
				push_event("console_error", "console", json{{"text", text}});
			}
			else if (type == console::con_type_warning)
			{
				push_event("console_warning", "console", json{{"text", text}});
			}
		}

		// ---------------------------------------------------------------- game state

		std::string dvar_string(const char* name)
		{
			auto* dvar = game::Dvar_FindVar(name);
			if (!dvar)
			{
				return {};
			}

			const auto* value = game::Dvar_ValueToString(dvar, true, dvar->current);
			return value ? value : "";
		}

		int player_count()
		{
			const auto* clients = *game::svs_clients;
			if (!clients || !*game::svs_numclients)
			{
				return 0;
			}

			auto count = 0;
			const auto max = std::min(*game::svs_numclients, 32);
			for (auto i = 0; i < max; ++i)
			{
				if (clients[i].header.state >= 5)
				{
					++count;
				}
			}

			return count;
		}

		bool in_game()
		{
			return !game::environment::is_dedi() && game::CL_IsCgameInitialized() && !game::VirtualLobby_Loaded();
		}

		bool main_menu()
		{
			if (game::environment::is_dedi())
			{
				return false;
			}

			const auto vlobby = game::VirtualLobby_Loaded();
			const auto lui = *game::hks::lua_state != nullptr;
			const auto db_ready = game::Sys_IsDatabaseReady2();
			return !in_game() && (vlobby || game::Com_InFrontend() || (lui && db_ready));
		}

		bool server_running()
		{
			const auto* dvar = game::Dvar_FindVar("sv_running");
			return dvar && dvar->current.enabled;
		}

		// ---------------------------------------------------------------- GSC access

		std::mutex gsc_call_mutex;
		std::mutex gsc_result_mutex;
		std::vector<std::string> gsc_results;
		std::string gsc_error;

		std::unordered_map<std::string, unsigned int> gsc_scripts;

		void reset_gsc_state()
		{
			std::lock_guard _(gsc_call_mutex);
			gsc_scripts.clear();

			std::lock_guard _2(gsc_result_mutex);
			gsc_results.clear();
			gsc_error.clear();
		}

		bool ensure_script_loaded(const std::string& script)
		{
			if (gsc_scripts.contains(script))
			{
				return true;
			}

			// Scr_LoadScript only knows scripts from fastfiles; ProcessScript (0x50E340) is the
			// engine path that runs our find_script hook (which compiles the file from disk) and
			// registers its functions in scripting::script_function_table.
			// The compiler context only exists between Scr_BeginLoadScripts/Scr_EndLoadScripts,
			// so a runtime load needs its own begin/end around it.
			gsc::begin_runtime_compile();
			utils::hook::invoke<void>(0x50E340_b, script.data());
			gsc::end_runtime_compile();

			if (!scripting::script_function_table.contains(script))
			{
				return false;
			}

			gsc_scripts[script] = 1;
			return true;
		}

		// Runs <script>::<function>() and returns the strings it passed to mwx_result().
		bool run_gsc_function(const std::string& script, const std::string& function, std::vector<std::string>* results)
		{
			std::lock_guard _(gsc_call_mutex);

			{
				std::lock_guard _2(gsc_result_mutex);
				gsc_results.clear();
				gsc_error.clear();
			}

			if (!ensure_script_loaded(script))
			{
				std::lock_guard _2(gsc_result_mutex);
				gsc_error = "could not load the script '" + script + "' (compile error? see the console)";
				return false;
			}

			try
			{
				const scripting::entity level{*game::levelEntityId};
				scripting::call_script_function(level, script, function, {});
			}
			catch (const std::exception& e)
			{
				std::lock_guard _2(gsc_result_mutex);
				gsc_error = e.what();
				return false;
			}

			std::lock_guard _2(gsc_result_mutex);
			if (!gsc_error.empty())
			{
				if (results) *results = gsc_results;
				return false;
			}

			if (results) *results = gsc_results;
			return true;
		}

		std::string get_gsc_error()
		{
			std::lock_guard _(gsc_result_mutex);
			return gsc_error;
		}

		// The GSC helper functions read their parameters from these string dvars (registered in
		// scheduler::once below): GSC has no way to take a variable argument list from C++.
		void set_arg(const int index, const std::string& value)
		{
			const auto name = "mwx_debug_arg" + std::to_string(index);
			game::Dvar_SetFromStringByNameFromSource(name.data(), value.data(), game::DVAR_SOURCE_INTERNAL);
		}

		// turns "return X;" into "mwx_result(X);", everything else is used as a function body
		std::string transform_eval_code(const std::string& code)
		{
			auto trimmed = code;
			while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.front())))
			{
				trimmed.erase(trimmed.begin());
			}
			while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.back())))
			{
				trimmed.pop_back();
			}

			if (trimmed.starts_with("return "))
			{
				auto expression = trimmed.substr(7);
				if (!expression.empty() && expression.back() == ';')
				{
					expression.pop_back();
				}
				return "mwx_result(" + expression + ");";
			}

			return code;
		}

		// ---------------------------------------------------------------- input

		struct look_override_t
		{
			bool active = false;
			float pitch = 0.f;
			float yaw = 0.f;
			std::chrono::steady_clock::time_point until{};
		};

		look_override_t look_override;
		std::mutex look_mutex;

		void apply_look_override()
		{
			look_override_t copy{};
			{
				std::lock_guard _(look_mutex);
				if (!look_override.active)
				{
					return;
				}

				if (std::chrono::steady_clock::now() >= look_override.until)
				{
					look_override.active = false;
					return;
				}

				copy = look_override;
			}

			if (game::environment::is_dedi())
			{
				return;
			}

			auto* client = game::g_entities[0].client;
			if (client)
			{
				client->ps.viewangles[0] = copy.pitch;
				client->ps.viewangles[1] = copy.yaw;
			}

			if (*game::playerState)
			{
				(*game::playerState)->viewangles[0] = copy.pitch;
				(*game::playerState)->viewangles[1] = copy.yaw;
			}
		}

		std::string negate_command(const std::string& cmd)
		{
			if (!cmd.empty() && cmd.front() == '+')
			{
				return "-" + cmd.substr(1);
			}
			if (!cmd.empty() && cmd.front() == '-')
			{
				return "+" + cmd.substr(1);
			}
			return {};
		}

		// The key that is bound to `command` (-1 when there is none). Injected key events take the
		// same path as real keyboard input (CL_KeyEvent), so they also work without focus, while
		// Cbuf commands are only executed by the active client.
		int find_key_for_command(const std::string& command)
		{
			const auto binding = game::Key_GetBindingForCmd(command.data());
			if (!binding)
			{
				return -1;
			}

			for (auto i = 0; i < 256; ++i)
			{
				if (game::playerKeys[0].keys[i].binding == binding)
				{
					return i;
				}
			}

			return -1;
		}

		void send_key(const int key, const bool down)
		{
			utils::hook::invoke<void>(0x135A70_b, 0, key, down ? 1 : 0); // CL_KeyEvent
		}
	}

	// -------------------------------------------------------------------- events

	void push_event(const std::string& type, const std::string& source, json data)
	{
		{
			std::lock_guard _(events_mutex);
			event_t event{};
			event.id = next_event_id++;
			event.time_ms = process_time_ms();
			event.type = type;
			event.source = source;
			event.data = std::move(data);

			event_buffer.emplace_back(std::move(event));
			while (event_buffer.size() > max_events)
			{
				event_buffer.pop_front();
			}
		}
	}

	json events(const json& params)
	{
		const auto since = params.value("since", static_cast<std::uint64_t>(0));
		const auto type = params.value("type", "");
		const auto limit = params.value("limit", 0);

		return json{{"cursor", last_event_id()}, {"events", event_since(since, type, limit)}};
	}

	// -------------------------------------------------------------------- wait

	namespace
	{
		bool evaluate_condition(const json& params, const std::uint64_t cursor, json* details)
		{
			const auto state = params.value("state", "");
			const auto argument = params.value("value", params.value("name", ""));
			const auto timeout_ignored = params.value("timeout_s", 120);
			(void)timeout_ignored;

			if (state == "running")
			{
				*details = json{{"reached", true}};
				return true;
			}

			if (state == "main_menu")
			{
				*details = json{{"reached", main_menu()}};
				return main_menu();
			}

			if (state == "in_game")
			{
				*details = json{{"reached", in_game()}};
				return in_game();
			}

			if (state == "server_running")
			{
				*details = json{{"reached", server_running()}};
				return server_running();
			}

			if (state == "map_loaded")
			{
				const auto map = dvar_string("mapname");
				const auto loaded = !map.empty() && (game::environment::is_dedi() ? server_running() : (in_game() || game::CL_IsCgameInitialized()));
				const auto reached = loaded && (argument.empty() || map == argument);
				*details = json{{"reached", reached}, {"map", map}};
				return reached;
			}

			if (state == "player_count")
			{
				const auto wanted = params.value("count", 1);
				const auto clients = player_count();
				const auto reached = params.contains("op") && params["op"] == "==" ? clients == wanted : clients >= wanted;
				*details = json{{"reached", reached}, {"players", clients}};
				return reached;
			}

			if (state == "dvar")
			{
				const auto name = params.value("name", "");
				const auto value = dvar_string(name.data());
				const auto expected = params.value("value", "");
				*details = json{{"name", name}, {"value", value}};
				return value == expected;
			}

			if (state == "event")
			{
				const auto type = params.value("type", "");
				const auto filter = params.value("filter", "");
				const auto new_events = event_since(cursor, type, 100);
				for (const auto& event : new_events)
				{
					if (filter.empty())
					{
						*details = event;
						return true;
					}

					const auto text = event["data"].dump();
					if (text.find(filter) != std::string::npos)
					{
						*details = event;
						return true;
					}
				}

				*details = json{{"reached", false}, {"new_events", static_cast<int>(new_events.size())}};
				return false;
			}

			*details = json{{"error", "unknown wait state: " + state}};
			return false;
		}
	}

	json wait(const json& params)
	{
		const auto timeout = std::clamp(params.value("timeout_s", 120), 1, 3600);
		const auto start = std::chrono::steady_clock::now();
		const auto cursor = last_event_id();
		const auto is_menu_condition = params.value("state", "") == "menu_open";
		const auto menu_name = params.value("name", params.value("value", ""));

		while (std::chrono::steady_clock::now() - start < std::chrono::seconds(timeout))
		{
			json details{};
			bool reached = false;

			if (is_menu_condition)
			{
				const auto answer = debug_server::run_on([menu_name]
				{
					return json{{"reached", ui_debug::is_menu_open(menu_name)}};
				}, scheduler::pipeline::lui, 3000ms);

				reached = answer.value("reached", false);
				details = answer;
			}
			else
			{
				// the lambda outlives a timeout in run_on, so everything it uses is copied
				const auto answer = debug_server::run_on([params, cursor]
				{
					json inner{};
					const auto ok = evaluate_condition(params, cursor, &inner);
					return json{{"reached", ok}, {"details", inner}};
				}, scheduler::pipeline::main, 3000ms);

				if (answer.contains("error"))
				{
					return answer;
				}

				reached = answer.value("reached", false);
				details = answer.contains("details") ? answer["details"] : json::object();
			}

			if (reached)
			{
				const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - start).count();
				return json{{"reached", true}, {"state", params.value("state", "")}, {"waited_ms", took},
					{"details", details}};
			}

			if (details.contains("error"))
			{
				return json{{"error", details["error"]}};
			}

			std::this_thread::sleep_for(100ms);
		}

		return json{{"error", "timeout waiting for " + params.value("state", "")}};
	}

	// -------------------------------------------------------------------- players / entities

	json players()
	{
		std::vector<std::string> results;
		if (!run_gsc_function("mwx/tests/_debug", "mwx_debug_players", &results) || results.empty())
		{
			return json{{"error", get_gsc_error().empty() ? "could not read the players (is a server running?)" : get_gsc_error()}};
		}

		auto parsed = json::parse(results[0], nullptr, false);
		if (parsed.is_discarded())
		{
			return json{{"error", "bad answer from _debug.gsc"}, {"raw", results[0]}};
		}

		return json{{"players", parsed}};
	}

	json entities(const json& params)
	{
		const auto classname = params.value("classname", "");
		const auto targetname = params.value("targetname", "");
		const auto limit = std::clamp(params.value("limit", 64), 1, 1024);
		const auto origin = params.contains("origin") && params["origin"].is_array() && params["origin"].size() == 3;

		set_arg(0, classname);
		set_arg(1, targetname);
		set_arg(2, std::to_string(limit));

		if (origin)
		{
			set_arg(3, utils::string::va("%f %f %f", params["origin"][0].get<double>(),
				params["origin"][1].get<double>(), params["origin"][2].get<double>()));
			set_arg(4, std::to_string(params.value("radius", 500.f)));
		}
		else
		{
			set_arg(3, "");
			set_arg(4, "0");
		}

		std::vector<std::string> results;
		if (!run_gsc_function("mwx/tests/_debug", "mwx_debug_entities", &results) || results.empty())
		{
			return json{{"error", get_gsc_error().empty() ? "could not read the entities" : get_gsc_error()}};
		}

		auto parsed = json::parse(results[0], nullptr, false);
		if (parsed.is_discarded())
		{
			return json{{"error", "bad answer from _debug.gsc"}, {"raw", results[0]}};
		}

		return json{{"entities", parsed}};
	}

	json bots(const json& params)
	{
		const auto action = params.value("action", "");
		const auto count = std::clamp(params.value("count", 1), 1, 31);
		const auto num = params.value("num", -1);

		if (action == "spawn")
		{
			command::execute(utils::string::va("spawnBot %d", count), false);
			return json{{"queued", "spawnBot " + std::to_string(count)}};
		}

		if (action == "kick")
		{
			if (num < 0)
			{
				return json{{"error", "num is required for kick"}};
			}
			command::execute(utils::string::va("kick %d", num), false);
			return json{{"queued", "kick " + std::to_string(num)}};
		}

		if (action == "team")
		{
			if (num < 0)
			{
				return json{{"error", "num is required for team"}};
			}

			const auto team = params.value("team", "allies");
			const auto team_number = team == "axis" ? 2 : (team == "allies" ? 1 : (team == "spectator" ? 0 : 3));
			const game::scr_entref_t entref{static_cast<std::uint16_t>(num), 0};

			scheduler::once([entref, team_number]
			{
				scripting::notify(entref, "luinotifyserver", {"team_select", team_number});
			}, scheduler::pipeline::server);

			return json{{"queued", team}, {"num", num}};
		}

		if (action == "freeze" || action == "unfreeze")
		{
			set_arg(0, action);
			set_arg(1, std::to_string(num));

			std::vector<std::string> results;
			if (!run_gsc_function("mwx/tests/_debug", "mwx_debug_bots", &results) || results.empty())
			{
				return json{{"error", get_gsc_error().empty() ? "bot action failed" : get_gsc_error()}};
			}
			return json{{"result", results[0]}};
		}

		return json{{"error", "unknown bot action: " + action}};
	}

	// -------------------------------------------------------------------- gsc eval

	json gsc_eval(const json& params)
	{
		auto code = params.value("code", "");
		if (code.empty())
		{
			return json{{"error", "code is required"}};
		}

		if (!game::SV_Loaded() && !game::CL_IsCgameInitialized())
		{
			return json{{"error", "no script VM running (start a map first)"}};
		}

		static std::atomic<std::uint32_t> eval_counter{0};
		const auto name = "mwx/tests/_eval_" + std::to_string(eval_counter++);

		const auto script = "mwx_eval()\n{\n" + transform_eval_code(code) + "\n}\n";

		utils::io::create_directory("mwx/tests");
		const auto path = name + ".gsc";
		if (!utils::io::write_file(path, script))
		{
			return json{{"error", "could not write " + path}};
		}

		std::vector<std::string> results;
		const auto ok = run_gsc_function(name, "mwx_eval", &results);

		utils::io::remove_file(path);

		if (!ok)
		{
			return json{{"ok", false}, {"error", get_gsc_error().empty() ? "the script did not run" : get_gsc_error()},
				{"script", script}};
		}

		json value{};
		if (results.empty())
		{
			value = nullptr;
		}
		else if (results.size() == 1)
		{
			value = results[0];
		}
		else
		{
			value = results;
		}

		return json{{"ok", true}, {"result", value}};
	}

	json perf()
	{
		json result{};
		result["uptime_ms"] = process_time_ms();
		result["fps"] = fps::get_fps();
		result["frame_ms"] = fps::get_fps() > 0 ? 1000.0 / fps::get_fps() : 0.0;
		result["map"] = dvar_string("mapname");
		result["gametype"] = dvar_string("g_gametype");
		result["players"] = player_count();
		result["in_game"] = in_game();
		result["server_running"] = server_running();

		PROCESS_MEMORY_COUNTERS counters{};
		counters.cb = sizeof(counters);
		if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)))
		{
			result["working_set_mb"] = static_cast<double>(counters.WorkingSetSize) / (1024.0 * 1024.0);
			result["private_mb"] = static_cast<double>(counters.PagefileUsage) / (1024.0 * 1024.0);
		}

		std::string load_log{};
		utils::io::read_file("mwx-logs/load_times.log", &load_log);
		if (const auto pos = load_log.rfind("==== MWX start"); pos != std::string::npos)
		{
			load_log = load_log.substr(pos);
		}
		result["load_times"] = load_log;

		return result;
	}

	json last_crash()
	{
		json result{};
		result["found"] = false;

		if (!utils::io::directory_exists("minidumps"))
		{
			return result;
		}

		std::string newest{};
		std::filesystem::file_time_type newest_time{};
		for (const auto& file : utils::io::list_files("minidumps"))
		{
			if (!file.ends_with(".zip"))
			{
				continue;
			}

			const auto path = std::filesystem::path(file);
			const auto time = std::filesystem::last_write_time(path);
			if (newest.empty() || time > newest_time)
			{
				newest = file;
				newest_time = time;
			}
		}

		if (newest.empty())
		{
			return result;
		}

		result["found"] = true;
		result["dump"] = newest;
		result["size"] = static_cast<std::uint64_t>(utils::io::file_size(newest));

		const auto time = std::chrono::system_clock::now() +
			(newest_time - std::filesystem::file_time_type::clock::now());
		const auto time_t = std::chrono::system_clock::to_time_t(time);
		std::tm local{};
		localtime_s(&local, &time_t);
		result["time"] = utils::string::va("%04d-%02d-%02d %02d:%02d:%02d", local.tm_year + 1900,
			local.tm_mon + 1, local.tm_mday, local.tm_hour, local.tm_min, local.tm_sec);

		// the crash handler also writes the info text next to the dump (see exception.cpp)
		std::string info{};
		if (utils::io::read_file("mwx-logs/last_crash.txt", &info))
		{
			// only if it belongs to the newest dump
			if (info.find(newest) != std::string::npos)
			{
				result["info"] = info;
			}
		}

		return result;
	}

	// -------------------------------------------------------------------- input

	json input(const json& params)
	{
		const auto action = params.value("action", "");
		auto cmd = params.value("command", "");
		const auto duration = std::clamp(params.value("ms", 200), 1, 60000);

		if (action == "press" || action == "tap")
		{
			if (cmd.empty())
			{
				return json{{"error", "command is required"}};
			}

			const auto key = find_key_for_command(cmd);
			if (key >= 0)
			{
				send_key(key, true);
				scheduler::once([key] { send_key(key, false); }, scheduler::pipeline::main,
					std::chrono::milliseconds(duration));
				return json{{"queued", cmd}, {"key", key}};
			}

			command::execute(cmd, false);
			const auto release = negate_command(cmd);
			if (!release.empty())
			{
				scheduler::once([release] { command::execute(release, false); }, scheduler::pipeline::main,
					std::chrono::milliseconds(duration));
			}
			return json{{"queued", cmd}};
		}

		if (action == "hold" || action == "move")
		{
			if (cmd.empty())
			{
				cmd = action == "move" ? "+forward" : "";
			}
			if (cmd.empty())
			{
				return json{{"error", "command is required"}};
			}

			const auto key = find_key_for_command(cmd);
			if (key >= 0)
			{
				send_key(key, true);
				scheduler::once([key] { send_key(key, false); }, scheduler::pipeline::main,
					std::chrono::milliseconds(duration));
				return json{{"held", cmd}, {"key", key}, {"ms", duration}};
			}

			command::execute(cmd, false);
			const auto release = negate_command(cmd);
			if (!release.empty())
			{
				scheduler::once([release] { command::execute(release, false); }, scheduler::pipeline::main,
					std::chrono::milliseconds(duration));
			}
			return json{{"held", cmd}, {"ms", duration}};
		}

		if (action == "release")
		{
			if (cmd.empty())
			{
				return json{{"error", "command is required"}};
			}

			const auto key = find_key_for_command(cmd);
			if (key >= 0)
			{
				send_key(key, false);
				return json{{"released", cmd}, {"key", key}};
			}

			command::execute(cmd, false);
			return json{{"released", cmd}};
		}

		if (action == "look")
		{
			auto pitch = static_cast<float>(params.value("pitch", 0.0));
			auto yaw = static_cast<float>(params.value("yaw", 0.0));

			if (params.contains("look_at") && params["look_at"].is_array() && params["look_at"].size() == 3)
			{
				auto* client = game::g_entities[0].client;
				if (!client)
				{
					return json{{"error", "no local player"}};
				}

				const auto x = params["look_at"][0].get<double>() - client->ps.origin[0];
				const auto y = params["look_at"][1].get<double>() - client->ps.origin[1];
				const auto z = params["look_at"][2].get<double>() - client->ps.origin[2];
				const auto distance = std::sqrt(x * x + y * y);

				yaw = static_cast<float>(std::atan2(y, x) * 180.0 / 3.14159265358979323846);
				pitch = static_cast<float>(-std::atan2(z, distance) * 180.0 / 3.14159265358979323846);
			}

			{
				std::lock_guard _(look_mutex);
				look_override.active = true;
				look_override.pitch = pitch;
				look_override.yaw = yaw;
				look_override.until = std::chrono::steady_clock::now() +
					std::chrono::milliseconds(params.value("ms", 250));
			}

			apply_look_override();
			return json{{"look", true}, {"pitch", pitch}, {"yaw", yaw}};
		}

		if (action == "stop")
		{
			{
				std::lock_guard _(look_mutex);
				look_override.active = false;
			}
			command::execute("-forward", false);
			command::execute("-back", false);
			command::execute("-moveleft", false);
			command::execute("-moveright", false);
			command::execute("-attack", false);
			command::execute("-speed", false);
			return json{{"stopped", true}};
		}

		return json{{"error", "unknown input action: " + action}};
	}

	// -------------------------------------------------------------------- component

	namespace
	{
		void mwx_result(const gsc::function_args& args)
		{
			std::lock_guard _(gsc_result_mutex);
			for (auto i = 0u; i < args.size(); ++i)
			{
				gsc_results.push_back(args[i].to_string());
			}
		}

		void mwx_event(const gsc::function_args& args)
		{
			const auto type = args.size() > 0 ? args[0].as<std::string>() : "event";
			const auto data = args.size() > 1 ? args[1].as<std::string>() : "";
			const auto source = args.size() > 2 ? args[2].as<std::string>() : "gsc";
			event_from_gsc(type, source, data);
		}

		void mwx_test_log(const gsc::function_args& args)
		{
			// GSC side prints test state; this keeps it structured in the event stream too
			const auto data = args.size() > 0 ? args[0].as<std::string>() : "";
			event_from_gsc("test_log", "gsc", data);
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			console::add_sink(on_console);
			scripting::add_notify_callback(on_script_notify);
			scripting::on_shutdown([](bool, bool post_shutdown)
			{
				if (post_shutdown)
				{
					reset_gsc_state();
				}
			});

			// the builtins do not exist in H1: they can only be added after the GSC compiler
			// context was initialised (once per script load)
			gsc::on_context_ready([]
			{
				gsc::function::add("mwx_result", [](const gsc::function_args& args)
				{
					mwx_result(args);
					return scripting::script_value{};
				});

				// the move speed scale of a player (playerState.moveSpeedScaleMultiplier), which
				// setmovespeedscale writes and GSC cannot read back otherwise
				gsc::function::add("mwx_movespeedscale", [](const gsc::function_args& args) -> scripting::script_value
				{
					if (args.size() < 1)
					{
						return scripting::script_value{0.f};
					}

					const scripting::entity entity{args[0].as<scripting::entity>()};
					const auto ref = entity.get_entity_reference();
					if (ref.classnum != 0 || ref.entnum >= 32)
					{
						return scripting::script_value{0.f};
					}

					const auto& client = (*game::svs_clients)[ref.entnum];
					if (!client.gentity || !client.gentity->client)
					{
						return scripting::script_value{0.f};
					}

					return scripting::script_value{client.gentity->client->ps.moveSpeedScaleMultiplier};
				});

				gsc::function::add("mwx_event", [](const gsc::function_args& args)
				{
					mwx_event(args);
					return scripting::script_value{};
				});

				gsc::function::add("mwx_test_log", [](const gsc::function_args& args)
				{
					mwx_test_log(args);
					return scripting::script_value{};
				});
			});

			logfile::add_line_callback([](const std::string& line)
			{
				parse_game_log(line);
			});

			scheduler::loop(apply_look_override, scheduler::pipeline::main);

			scheduler::once([]
			{
				dvars::register_string("mwx_test", "", game::DVAR_FLAG_NONE,
					"Run the test script mwx/tests/<name>.gsc at map start (see docs/testing.md)");

				for (auto i = 0; i < 6; ++i)
				{
					const auto name = "mwx_debug_arg" + std::to_string(i);
					dvars::register_string(name.data(), "", game::DVAR_FLAG_NONE,
						"Parameter of the MWX debug interface (internal)");
				}
			}, scheduler::pipeline::main);
		}

		void pre_destroy() override
		{
		}
	};
}

REGISTER_COMPONENT(debug_api::component)

#include <std_include.hpp>

#include "mcp.hpp"
#include "component/debug_server.hpp"
#include "version.hpp"

#include <utils/http.hpp>
#include <utils/string.hpp>

// MWX MCP bridge (stdio, newline-delimited JSON-RPC 2.0).
//
// Add to an MCP client, e.g. Claude desktop (claude_desktop_config.json):
//   "mcpServers": { "mwx": { "command": "C:\\...\\mwx.exe", "args": ["-mcp"] } }
// or opencode (opencode.json):
//   "mcp": { "mwx": { "type": "local", "command": ["C:\\...\\mwx.exe", "-mcp"] } }
//
// Nothing of the game is loaded in this mode; it only forwards to the debug server of a
// running mwx.exe (client: 127.0.0.1:27099, dedicated server: 127.0.0.1:27098).

namespace mcp
{
	namespace
	{
		using json = nlohmann::json;
		constexpr auto protocol_version = "2025-06-18";

		std::mutex output_mutex;

		struct launched_process
		{
			PROCESS_INFORMATION info{};
			std::string args;
		};

		std::unordered_map<std::string, launched_process> launched; // "client" / "server"

		void send(const json& message)
		{
			std::lock_guard _(output_mutex);
			const auto line = message.dump(-1, ' ', false, json::error_handler_t::replace) + "\n";
			fwrite(line.data(), 1, line.size(), stdout);
			fflush(stdout);
		}

		std::filesystem::path get_exe_path()
		{
			wchar_t path[MAX_PATH]{};
			GetModuleFileNameW(nullptr, path, MAX_PATH);
			return path;
		}

		std::uint16_t port_for(const std::string& target)
		{
			return target == "server" ? debug_server::default_server_port : debug_server::default_client_port;
		}

		json rpc(const std::string& target, const std::string& method, const json& params = json::object(), const int timeout_s = 5)
		{
			const auto url = utils::string::va("http://127.0.0.1:%u/rpc", port_for(target));
			const json request{{"method", method}, {"params", params}};

			const auto result = utils::http::get_data(url, request.dump(), {{"Content-Type", "application/json"}}, {}, timeout_s);
			if (!result.has_value() || result->code != CURLE_OK)
			{
				return json{{"error", utils::string::va("mwx %s is not running (no answer on 127.0.0.1:%u)",
					target.data(), port_for(target))}, {"not_running", true}};
			}

			try
			{
				return json::parse(result->buffer);
			}
			catch (const std::exception& e)
			{
				return json{{"error", std::string("bad answer from the game: ") + e.what()}};
			}
		}

		bool is_running(const std::string& target)
		{
			const auto it = launched.find(target);
			if (it == launched.end())
			{
				return false;
			}

			DWORD code{};
			return GetExitCodeProcess(it->second.info.hProcess, &code) && code == STILL_ACTIVE;
		}

		json start_game(const json& args)
		{
			const auto dedicated = args.value("dedicated", false);
			const std::string target = dedicated ? "server" : "client";

			if (!rpc(target, "status", json::object(), 2).contains("not_running"))
			{
				return json{{"error", "mwx " + target + " is already running"}};
			}

			std::string extra = args.value("args", "");
			if (dedicated && extra.empty())
			{
				extra = "+exec server_default.cfg +set net_port 27016 +map_rotate";
			}

			const auto exe = get_exe_path();
			const auto dir = exe.parent_path();
			std::string command_line = utils::string::va("\"%s\" %s%s", exe.string().data(),
				dedicated ? "-dedicated -memoryfix " : "", extra.data());

			STARTUPINFOA startup{};
			startup.cb = sizeof(startup);
			launched_process process{};
			process.args = command_line;

			// own console for the game (it must not write into our stdout, that's the MCP channel)
			if (!CreateProcessA(nullptr, command_line.data(), nullptr, nullptr, FALSE, CREATE_NEW_CONSOLE,
				nullptr, dir.string().data(), &startup, &process.info))
			{
				return json{{"error", utils::string::va("CreateProcess failed (%lu)", GetLastError())}};
			}

			if (const auto old = launched.find(target); old != launched.end())
			{
				CloseHandle(old->second.info.hProcess);
				CloseHandle(old->second.info.hThread);
			}

			launched[target] = process;
			return json{{"result", {{"started", target}, {"pid", process.info.dwProcessId}, {"command_line", command_line}}}};
		}

		json stop_game(const json& args)
		{
			const auto target = args.value("target", "client");

			const auto answer = rpc(target, "command", {{"command", "quit"}}, 2);
			if (const auto it = launched.find(target); it != launched.end())
			{
				if (WaitForSingleObject(it->second.info.hProcess, 10000) == WAIT_TIMEOUT)
				{
					TerminateProcess(it->second.info.hProcess, 1);
					return json{{"result", "did not quit within 10 s, terminated"}};
				}
				return json{{"result", "quit"}};
			}

			if (answer.contains("error"))
			{
				return answer;
			}
			return json{{"result", "quit command sent"}};
		}

		json wait_for(const json& args)
		{
			const auto target = args.value("target", "client");
			const auto state = args.value("state", "main_menu");
			const auto timeout = std::clamp(args.value("timeout_s", 120), 1, 600);

			const auto start = std::chrono::steady_clock::now();
			json last{};
			while (std::chrono::steady_clock::now() - start < std::chrono::seconds(timeout))
			{
				last = rpc(target, "status", json::object(), 2);
				if (state == "running" && !last.contains("not_running"))
				{
					return json{{"result", {{"reached", state}, {"status", last}}}};
				}

				if (last.contains("result"))
				{
					const auto& status = last["result"];
					const auto reached =
						(state == "main_menu" && status.value("main_menu", false)) ||
						(state == "in_game" && status.value("in_game", false)) ||
						(state == "server_running" && status.value("sv_running", false) && !status.value("main_menu", false));
					if (reached)
					{
						const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
						return json{{"result", {{"reached", state}, {"waited_ms", took}, {"status", status}}}};
					}
				}

				if (!is_running(target) && launched.contains(target))
				{
					return json{{"error", "the game process exited"}, {"last", last}};
				}

				std::this_thread::sleep_for(1s);
			}

			return json{{"error", "timeout waiting for " + state}, {"last", last}};
		}

		json target_schema()
		{
			return {{"type", "string"}, {"enum", {"client", "server"}},
				{"description", "client = the game (port 27099), server = dedicated server (port 27098). Default client."}};
		}

		json tools()
		{
			return json::array({
				{
					{"name", "game_status"},
					{"description", "State of a running mwx instance: map, game type, main menu / in game, connected server, players (name, team, score, ping, bot, position; only where the server runs)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "run_command"},
					{"description", "Runs a console command in the game, e.g. 'map mp_crash', 'spawnbot 5', 'fast_restart'. Use console_log afterwards to see output."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"command", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"command"}}}},
				},
				{
					{"name", "get_dvar"},
					{"description", "Reads a dvar (console variable)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"name", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"name"}}}},
				},
				{
					{"name", "set_dvar"},
					{"description", "Sets a dvar (console variable)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"name", {{"type", "string"}}}, {"value", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"name", "value"}}}},
				},
				{
					{"name", "console_log"},
					{"description", "The last lines of the game console (up to 1000), optionally only lines containing `filter`."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"lines", {{"type", "integer"}}}, {"filter", {{"type", "string"}}}, {"target", target_schema()}}}}},
				},
				{
					{"name", "load_times"},
					{"description", "Load-time log of the latest start: every fastfile with its time, plus first frame / main menu / map milestones."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "start_game"},
					{"description", "Starts mwx.exe (the game, or a dedicated server with dedicated=true). Optional extra command line args, e.g. '+set net_port 27017 +map mp_crash'. Default server args: +exec server_default.cfg +set net_port 27016 +map_rotate."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"dedicated", {{"type", "boolean"}}}, {"args", {{"type", "string"}}}}}}},
				},
				{
					{"name", "stop_game"},
					{"description", "Quits a running mwx instance (terminates it after 10 s if it was started by start_game and doesn't quit)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "wait_for"},
					{"description", "Waits until an instance reaches a state: running (debug server answers), main_menu, in_game, server_running. Returns how long it took."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"state", {{"type", "string"}, {"enum", {"running", "main_menu", "in_game", "server_running"}}}},
						{"timeout_s", {{"type", "integer"}}}, {"target", target_schema()}}}, {"required", {"state"}}}},
				},
			});
		}

		json call_tool(const std::string& name, const json& args)
		{
			const auto target = args.value("target", "client");

			if (name == "game_status") return rpc(target, "status");
			if (name == "run_command") return rpc(target, "command", {{"command", args.value("command", "")}});
			if (name == "get_dvar") return rpc(target, "get_dvar", {{"name", args.value("name", "")}});
			if (name == "set_dvar") return rpc(target, "set_dvar", {{"name", args.value("name", "")}, {"value", args.value("value", "")}});
			if (name == "console_log") return rpc(target, "console", {{"lines", args.value("lines", 100)}, {"filter", args.value("filter", "")}});
			if (name == "load_times") return rpc(target, "load_times");
			if (name == "start_game") return start_game(args);
			if (name == "stop_game") return stop_game(args);
			if (name == "wait_for") return wait_for(args);

			return json{{"error", "unknown tool: " + name}};
		}

		void handle(const json& message)
		{
			const auto method = message.value("method", "");
			const auto has_id = message.contains("id");
			const auto id = has_id ? message["id"] : json{};

			const auto reply = [&](const json& result)
			{
				if (has_id)
				{
					send({{"jsonrpc", "2.0"}, {"id", id}, {"result", result}});
				}
			};

			if (method == "initialize")
			{
				const auto requested = message.contains("params") ? message["params"].value("protocolVersion", protocol_version) : protocol_version;
				reply({
					{"protocolVersion", requested},
					{"capabilities", {{"tools", json::object()}}},
					{"serverInfo", {{"name", "mwx"}, {"version", VERSION}}},
					{"instructions", "Debug interface of MWX (HorizonMW-based Call of Duty: MWR LAN client). start_game / wait_for / game_status / run_command / console_log / load_times. target 'server' = dedicated server."},
				});
				return;
			}

			if (method == "ping")
			{
				reply(json::object());
				return;
			}

			if (method == "tools/list")
			{
				reply({{"tools", tools()}});
				return;
			}

			if (method == "tools/call")
			{
				const auto& params = message.contains("params") ? message["params"] : json::object();
				const auto name = params.value("name", "");
				const auto args = params.contains("arguments") && params["arguments"].is_object() ? params["arguments"] : json::object();

				json result{};
				try
				{
					result = call_tool(name, args);
				}
				catch (const std::exception& e)
				{
					result = json{{"error", e.what()}};
				}

				const auto is_error = result.contains("error");
				const auto& payload = is_error ? result : (result.contains("result") ? result["result"] : result);
				const auto text = payload.is_string() ? payload.get<std::string>() : payload.dump(2, ' ', false, json::error_handler_t::replace);

				reply({{"content", json::array({{{"type", "text"}, {"text", text}}})}, {"isError", is_error}});
				return;
			}

			if (method.starts_with("notifications/"))
			{
				return;
			}

			if (has_id)
			{
				send({{"jsonrpc", "2.0"}, {"id", id}, {"error", {{"code", -32601}, {"message", "method not found: " + method}}}});
			}
		}
	}

	int run()
	{
		_setmode(_fileno(stdout), _O_BINARY);
		_setmode(_fileno(stdin), _O_BINARY);

		std::string line;
		while (std::getline(std::cin, line))
		{
			if (!line.empty() && line.back() == '\r')
			{
				line.pop_back();
			}
			if (line.empty())
			{
				continue;
			}

			try
			{
				handle(json::parse(line));
			}
			catch (const std::exception& e)
			{
				send({{"jsonrpc", "2.0"}, {"id", nullptr}, {"error", {{"code", -32700}, {"message", e.what()}}}});
			}
		}

		for (auto& [_, process] : launched)
		{
			CloseHandle(process.info.hProcess);
			CloseHandle(process.info.hThread);
		}
		return 0;
	}
}

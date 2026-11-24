#include <std_include.hpp>

#include "mcp.hpp"
#include "component/debug_server.hpp"
#include "version.hpp"

#include <utils/http.hpp>
#include <utils/string.hpp>

#include <algorithm>
#include <set>

// MWX MCP bridge (stdio, newline-delimited JSON-RPC 2.0).
//
// Add to an MCP client, e.g. Claude desktop (claude_desktop_config.json):
//   "mcpServers": { "mwx": { "command": "C:\\...\\mwx.exe", "args": ["-mcp"] } }
// or opencode (opencode.json in the repo):
//   "mcp": { "mwx": { "type": "local", "command": ["C:\\...\\mwx.exe", "-mcp"] } }
//
// Nothing of the game is loaded in this mode; it only forwards to the debug server of running
// mwx.exe instances (client: 127.0.0.1:27099, dedicated server: 127.0.0.1:27098) and starts or
// stops instances. Every tool takes an optional "target": an instance id from start_client /
// start_server, a debug port, or "client" / "server" (the default instance of that kind).

namespace mcp
{
	namespace
	{
		using json = nlohmann::json;
		constexpr auto protocol_version = "2025-06-18";

		std::mutex output_mutex;

		struct instance_t
		{
			std::string id;
			bool dedicated = false;
			std::uint16_t port = 0;
			PROCESS_INFORMATION info{};
			std::string command_line;
		};

		std::mutex instance_mutex;
		std::vector<instance_t> instances;
		std::uint32_t next_client = 1;
		std::uint32_t next_server = 1;

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

		bool process_running(const instance_t& instance)
		{
			if (!instance.info.hProcess)
			{
				return false;
			}

			DWORD code{};
			return GetExitCodeProcess(instance.info.hProcess, &code) && code == STILL_ACTIVE;
		}

		int process_exit_code(const instance_t& instance)
		{
			if (!instance.info.hProcess)
			{
				return -1;
			}

			DWORD code{};
			return GetExitCodeProcess(instance.info.hProcess, &code) ? static_cast<int>(code) : -1;
		}

		std::optional<instance_t> find_instance(const std::string& target)
		{
			std::lock_guard _(instance_mutex);

			for (const auto& instance : instances)
			{
				if (instance.id == target)
				{
					return instance;
				}
			}

			const auto is_server_target = target == "server";
			if (target == "client" || is_server_target)
			{
				for (const auto& instance : instances)
				{
					if (instance.dedicated == is_server_target && process_running(instance))
					{
						return instance;
					}
				}
			}

			return {};
		}

		std::uint16_t port_for(const std::string& target)
		{
			if (const auto instance = find_instance(target))
			{
				return instance->port;
			}

			if (!target.empty() && std::all_of(target.begin(), target.end(), [](const char c) { return std::isdigit(static_cast<unsigned char>(c)); }))
			{
				return static_cast<std::uint16_t>(std::atoi(target.data()));
			}

			return target == "server" ? debug_server::default_server_port : debug_server::default_client_port;
		}

		std::string describe_target(const std::string& target)
		{
			if (const auto instance = find_instance(target))
			{
				return instance->id + " (" + std::to_string(instance->port) + ")";
			}

			return target + " (" + std::to_string(port_for(target)) + ")";
		}

		json rpc(const std::string& target, const std::string& method, const json& params = json::object(), const int timeout_s = 5)
		{
			const auto port = port_for(target);
			const auto url = utils::string::va("http://127.0.0.1:%u/rpc", port);
			const json request{{"method", method}, {"params", params}};

			const auto result = utils::http::get_data(url, request.dump(), {{"Content-Type", "application/json"}}, {}, timeout_s);
			if (!result.has_value() || result->code != CURLE_OK)
			{
				return json{{"error", utils::string::va("mwx %s is not running (no answer on 127.0.0.1:%u)",
					describe_target(target).data(), port)}, {"not_running", true}};
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

		std::uint16_t allocate_port(const bool dedicated)
		{
			std::lock_guard _(instance_mutex);

			const auto first = dedicated ? static_cast<std::uint16_t>(debug_server::default_server_port + 10)
				: debug_server::default_client_port;
			const auto limit = dedicated ? 27200 : 27100;

			for (auto candidate = first; candidate <= limit; ++candidate)
			{
				auto used = false;
				for (const auto& instance : instances)
				{
					if (instance.port == candidate && process_running(instance))
					{
						used = true;
						break;
					}
				}

				if (!used)
				{
					return candidate;
				}
			}

			return first;
		}

		std::string quote_arg(const std::string& value)
		{
			return "\"" + value + "\"";
		}

		json start_instance(const bool dedicated, const json& args)
		{
			const auto port = static_cast<std::uint16_t>(args.value("port", 0)) != 0
				? static_cast<std::uint16_t>(args.value("port", 0)) : allocate_port(dedicated);

			const auto exe = get_exe_path();
			const auto dir = exe.parent_path();

			std::string command_line = utils::string::va("\"%s\" %s-debugport %u", exe.string().data(),
				dedicated ? "-dedicated -memoryfix " : "", port);

			// Each dedicated instance gets its own net port next to its debug port, so a server
			// whose predecessor exited slowly can never collide on 27017 (cranked in the 2026-11-24
			// full run). A caller-provided net_port (dvar or args) still wins because it comes later
			// on the command line.
			std::uint16_t net_port = 0;
			if (dedicated && port >= static_cast<std::uint16_t>(debug_server::default_server_port + 10))
			{
				net_port = static_cast<std::uint16_t>(27016 + (port - (debug_server::default_server_port + 10)));
				command_line += " +set net_port " + std::to_string(net_port);
			}

			// test mode: windowed 960x540, muted, no mouse capture (see test_mode.cpp)
			if (args.value("test_mode", true))
			{
				command_line += " +set mwx_test_mode 1";
			}

			const auto resolution = args.value("resolution", "");
			if (!resolution.empty())
			{
				command_line += " +set r_mode -1 +set r_customwidth " + resolution.substr(0, resolution.find('x')) +
					" +set r_customheight " + resolution.substr(resolution.find('x') + 1);
			}

			if (args.contains("dvars") && args["dvars"].is_object())
			{
				for (const auto& [name, value] : args["dvars"].items())
				{
					command_line += " +set " + name + " " + quote_arg(value.is_string() ? value.get<std::string>() : value.dump());
				}
			}

			if (args.contains("mod") && args["mod"].is_string() && !args["mod"].get<std::string>().empty())
			{
				command_line += " -mod " + quote_arg(args["mod"].get<std::string>());
			}

			const auto gametype = args.value("gametype", "");
			if (!gametype.empty())
			{
				command_line += " +set g_gametype " + quote_arg(gametype);
			}

			const auto map = args.value("map", "");
			if (!map.empty())
			{
				command_line += " +map " + quote_arg(map);
			}
			else if (dedicated && args.value("args", "").empty())
			{
				command_line += " +exec server_default.cfg +set net_port 27016 +map_rotate";
			}

			const auto extra = args.value("args", "");
			if (!extra.empty())
			{
				command_line += " " + extra;
			}

			STARTUPINFOA startup{};
			startup.cb = sizeof(startup);

			PROCESS_INFORMATION info{};
			if (!CreateProcessA(nullptr, command_line.data(), nullptr, nullptr, FALSE, CREATE_NEW_CONSOLE,
				nullptr, dir.string().data(), &startup, &info))
			{
				return json{{"error", utils::string::va("CreateProcess failed (%lu)", GetLastError())}};
			}

			instance_t instance{};
			instance.command_line = command_line;
			instance.dedicated = dedicated;
			instance.port = port;

			{
				std::lock_guard _(instance_mutex);
				instance.id = dedicated ? "s" + std::to_string(next_server++) : "c" + std::to_string(next_client++);
				instance.info = info;
				instances.push_back(instance);
			}

			return json{{"id", instance.id}, {"pid", info.dwProcessId}, {"port", port},
				{"net_port", net_port}, {"dedicated", dedicated}, {"command_line", command_line}};
		}

		json stop_instance(const std::string& target)
		{
			std::string id;
			std::uint16_t port = 0;
			PROCESS_INFORMATION info{};

			{
				std::lock_guard _(instance_mutex);
				for (auto& instance : instances)
				{
					if (instance.id == target)
					{
						id = instance.id;
						port = instance.port;
						info = instance.info;
						instance.info = {};
						break;
					}
				}
			}

			if (id.empty())
			{
				return json{{"error", "no instance with id " + target}};
			}

			const auto url = utils::string::va("http://127.0.0.1:%u/rpc", port);
			const json request{{"method", "command"}, {"params", {{"command", "quit"}}}};
			const auto answer = utils::http::get_data(url, request.dump(), {{"Content-Type", "application/json"}}, {}, 2);

			if (info.hProcess)
			{
				if (WaitForSingleObject(info.hProcess, 10000) == WAIT_TIMEOUT)
				{
					TerminateProcess(info.hProcess, 1);
					CloseHandle(info.hProcess);
					CloseHandle(info.hThread);
					return json{{"result", "did not quit within 10 s, terminated"}, {"id", id}};
				}

				CloseHandle(info.hProcess);
				CloseHandle(info.hThread);
			}

			return json{{"result", "quit"}, {"id", id}};
		}

		json list_instances()
		{
			std::vector<instance_t> copy;
			{
				std::lock_guard _(instance_mutex);
				copy = instances;
			}

			json result = json::array();
			for (const auto& instance : copy)
			{
				const auto running = process_running(instance);
				json status{};
				if (running)
				{
					const auto url = utils::string::va("http://127.0.0.1:%u/rpc", instance.port);
					const json request{{"method", "status"}, {"params", json::object()}};
					const auto answer = utils::http::get_data(url, request.dump(), {{"Content-Type", "application/json"}}, {}, 2);
					if (answer.has_value() && answer->code == CURLE_OK)
					{
						try
						{
							status = json::parse(answer->buffer);
						}
						catch (...)
						{
						}
					}
				}

				result.emplace_back(json{
					{"id", instance.id},
					{"dedicated", instance.dedicated},
					{"port", instance.port},
					{"pid", instance.info.dwProcessId},
					{"running", running},
					{"command_line", instance.command_line},
					{"status", status}
				});
			}

			return json{{"instances", result}};
		}

		json wait_for(const json& args)
		{
			const auto target = args.value("target", "client");
			const auto state = args.value("state", "main_menu");
			const auto timeout = std::clamp(args.value("timeout_s", args.value("timeout", 120)), 1, 3600);

			json params{{"state", state}, {"timeout_s", timeout}};
			for (const auto& [key, value] : args.items())
			{
				if (key != "target" && key != "timeout_s" && key != "timeout")
				{
					params[key] = value;
				}
			}

			const auto start = std::chrono::steady_clock::now();
			// one tool call has to stay well under the MCP client's request timeout (~60 s), so a
			// longer wait is split: it returns still_waiting and the caller calls again
			const auto budget = std::min<std::int64_t>(timeout, 45);
			const auto deadline = start + std::chrono::seconds(budget);
			json last{};

			while (std::chrono::steady_clock::now() < deadline)
			{
				const auto remaining = std::chrono::duration_cast<std::chrono::seconds>(deadline - std::chrono::steady_clock::now()).count();
				params["timeout_s"] = std::max<std::int64_t>(1, std::min<std::int64_t>(remaining, 10));

				const auto answer = rpc(target, "wait", params, static_cast<int>(params["timeout_s"].get<std::int64_t>()) + 15);
				last = answer;

				if (!answer.contains("not_running"))
				{
					if (answer.contains("result"))
					{
						auto reached = answer;
						reached["result"]["waited_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
							std::chrono::steady_clock::now() - start).count();
						return reached;
					}

					// an error other than a timeout (unknown state, busy) is final
					const auto error = answer.value("error", "");
					if (error.find("timeout") == std::string::npos && error.find("busy") == std::string::npos)
					{
						return answer;
					}
				}
				else if (const auto instance = find_instance(target); instance.has_value() && instance->info.hProcess &&
					!process_running(instance.value()))
				{
					return json{{"error", "the game process exited"}, {"last", last}};
				}

				std::this_thread::sleep_for(1s);
			}

			if (budget < timeout)
			{
				return json{{"result", {{"reached", false}, {"still_waiting", true}, {"state", state},
					{"waited_ms", std::chrono::duration_cast<std::chrono::milliseconds>(
						std::chrono::steady_clock::now() - start).count()}, {"status", last}}}};
			}

			return json{{"error", "timeout waiting for " + state}, {"last", last}};
		}

		// ---------------------------------------------------------------- game mode tests

		struct test_case
		{
			std::string name;
			std::string script;
			std::string map;
			std::string gametype;
			std::string mod;
			json dvars = json::object();
			int timeout_s = 300;
			bool listen = false;
		};

		json load_test_manifest()
		{
			const auto path = get_exe_path().parent_path() / "mwx" / "tests" / "tests.json";
			std::ifstream file(path);
			if (!file)
			{
				return json::array();
			}

			try
			{
				return json::parse(file);
			}
			catch (const std::exception& e)
			{
				fprintf(stderr, "mwx mcp: bad tests.json: %s\n", e.what());
				return json::array();
			}
		}

		std::optional<test_case> find_test(const std::string& name)
		{
			const auto manifest = load_test_manifest();
			for (const auto& entry : manifest)
			{
				if (entry.value("name", "") != name)
				{
					continue;
				}

				test_case test{};
				test.name = name;
				test.script = entry.value("script", name);
				test.map = entry.value("map", "mp_shipment");
				test.gametype = entry.value("gametype", test.script);
				test.mod = entry.value("mod", "");
				test.dvars = entry.value("dvars", json::object());
				test.timeout_s = entry.value("timeout_s", 300);
				test.listen = entry.value("listen", false);
				return test;
			}

			return {};
		}

		std::vector<std::string> list_tests()
		{
			std::vector<std::string> names;
			for (const auto& entry : load_test_manifest())
			{
				names.push_back(entry.value("name", ""));
			}
			return names;
		}

		// A test run takes minutes (map load + match), far longer than MCP clients wait for one
		// tool call (opencode closes the server after ~60 s). run_test / run_all_tests therefore
		// start a background job and return at once; test_status reports the result.
		struct test_job
		{
			std::string id;
			std::string name;
			std::string state = "running";
			json result;
			std::atomic_bool cancel{false};
			std::chrono::steady_clock::time_point started = std::chrono::steady_clock::now();
		};

		std::mutex jobs_mutex;
		std::vector<std::shared_ptr<test_job>> test_jobs;
		std::uint32_t next_job = 0;

		json run_one_test(const test_case& test, const std::shared_ptr<test_job>& job = {});

		json job_summary(const std::shared_ptr<test_job>& job)
		{
			json entry{{"job", job->id}, {"name", job->name}, {"state", job->state},
				{"elapsed_s", std::chrono::duration_cast<std::chrono::seconds>(
					std::chrono::steady_clock::now() - job->started).count()}};
			if (!job->result.is_null())
			{
				entry["result"] = job->result;
			}
			return entry;
		}

		json start_test_job(const std::string& name, const bool all)
		{
			{
				// two game instances on one PC block each other's map load (seen with a stale client:
				// the next server hung right after post_load), so only one test job at a time
				std::lock_guard _(jobs_mutex);
				for (const auto& running : test_jobs)
				{
					if (running->state == "running")
					{
						return json{{"error", "a test job is already running (" + running->id + ", " + running->name +
							"); poll test_status or cancel_test"}};
					}
				}
			}

			auto job = std::make_shared<test_job>();
			job->id = "t" + std::to_string(++next_job);
			job->name = name;

			// read the manifest once: a build that mirrors data\mwx into the game folder while the
			// job runs did shorten the list once (find_test() on a missing file returns nothing and
			// the remaining tests were skipped silently)
			std::vector<test_case> cases;
			for (const auto& entry_name : list_tests())
			{
				if (!all && entry_name != name)
				{
					continue;
				}

				const auto test = find_test(entry_name);
				if (test.has_value())
				{
					cases.push_back(test.value());
				}
			}

			if (cases.empty())
			{
				return json{{"error", "no tests to run"}, {"tests", list_tests()}};
			}

			{
				std::lock_guard _(jobs_mutex);
				test_jobs.push_back(job);
			}

			std::thread([job, cases, all]()
			{
				json result{};
				try
				{
					if (!all)
					{
						result = run_one_test(cases.front(), job);
					}
					else
					{
						json tests = json::array();
						auto passed = 0;
						auto failed = 0;
						for (const auto& test : cases)
						{
							if (job->cancel)
							{
								break;
							}

							const auto one = run_one_test(test, job);
							const auto ok = !one.contains("error") && one.value("failed", 1) == 0 &&
								one.value("script_errors", 1) == 0;
							ok ? ++passed : ++failed;
							tests.emplace_back(one);
							fprintf(stderr, "mwx mcp: test %s %s\n", test.name.data(), ok ? "green" : "failed");
						}
						result = json{{"tests", tests}, {"passed", passed}, {"failed", failed}};
					}
				}
				catch (const std::exception& e)
				{
					result = json{{"error", std::string("test job failed: ") + e.what()}};
				}

				std::lock_guard _(jobs_mutex);
				job->result = result;
				job->state = "done";
				fprintf(stderr, "mwx mcp: job %s (%s) done\n", job->id.data(), job->name.data());
			}).detach();

			return json{{"job", job->id}, {"name", name}, {"state", "running"},
				{"hint", "poll test_status (job '" + job->id + "'); a full run takes minutes"}};
		}

		json test_status(const json& args)
		{
			const auto id = args.value("job", "");

			std::lock_guard _(jobs_mutex);
			json jobs = json::array();
			for (auto it = test_jobs.rbegin(); it != test_jobs.rend(); ++it)
			{
				if (!id.empty() && (*it)->id != id)
				{
					continue;
				}
				jobs.emplace_back(job_summary(*it));
			}

			if (!id.empty() && jobs.empty())
			{
				return json{{"error", "no job with id " + id}};
			}

			return json{{"jobs", jobs}};
		}

		json cancel_test(const json& args)
		{
			const auto id = args.value("job", "");
			std::lock_guard _(jobs_mutex);
			for (auto& job : test_jobs)
			{
				if (id.empty() || job->id == id)
				{
					job->cancel = true;
					return json{{"result", "cancelling " + job->id}};
				}
			}
			return json{{"error", "no job with id " + id}};
		}

		json run_one_test(const test_case& test, const std::shared_ptr<test_job>& job)
		{
			const auto start = std::chrono::steady_clock::now();

			// The map goes on the command line: a `map` command after boot hangs a dedicated
			// server that was started without one. A listen client boots to the menu and then
			// loads the map over the RPC (that works, and AW ported usermaps only load there).
			json started{};
			if (test.listen)
			{
				started = start_instance(false, json{{"test_mode", true}, {"resolution", "960x540"}});
			}
			else
			{
				auto test_dvars = test.dvars;
				test_dvars["mwx_test"] = test.script;
				started = start_instance(true, json{{"map", test.map}, {"gametype", test.gametype},
					{"mod", test.mod}, {"dvars", test_dvars}, {"test_mode", true}});
			}
			if (started.contains("error"))
			{
				return started;
			}

			const auto id = started["id"].get<std::string>();
			fprintf(stderr, "mwx mcp: test %s debug port %d, net port %d\n", test.name.data(),
				started.value("port", 0), started.value("net_port", 0));
			const auto stop = gsl::finally([&] { stop_instance(id); });

			if (test.listen)
			{
				// wait for the debug server
				json status{};
				for (auto i = 0; i < 180; ++i)
				{
					status = rpc(id, "status", json::object(), 2);
					if (status.contains("result"))
					{
						break;
					}
					std::this_thread::sleep_for(1s);
				}

				if (!status.contains("result"))
				{
					return json{{"error", "the client did not come up"}, {"test", test.name}, {"status", status}};
				}

				rpc(id, "set_dvar", {{"name", "g_gametype"}, {"value", test.gametype}});
				rpc(id, "set_dvar", {{"name", "mwx_test"}, {"value", test.script}});
				for (const auto& [name, value] : test.dvars.items())
				{
					rpc(id, "set_dvar", {{"name", name}, {"value", value.is_string() ? value.get<std::string>() : value.dump()}});
				}

				rpc(id, "command", {{"command", "map " + test.map}}, 10);
			}

			// wait until the server runs the map
			json status{};
			auto running = false;
			for (auto i = 0; i < 180; ++i)
			{
				if (job && job->cancel)
				{
					stop_instance(id);
					return json{{"error", "cancelled"}, {"test", test.name}};
				}

				status = rpc(id, "status", json::object(), 2);
				if (status.contains("result"))
				{
					const auto& st = status["result"];
					if (st.value("sv_running", false) && (!test.listen || st.value("in_game", false)))
					{
						running = true;
						break;
					}
				}

				if (const auto instance = find_instance(id); instance.has_value() && instance->info.hProcess &&
					!process_running(instance.value()))
				{
					return json{{"error", "server exited (code " + std::to_string(process_exit_code(instance.value())) + ")"},
						{"test", test.name}, {"port", started.value("port", 0)}, {"net_port", started.value("net_port", 0)}};
				}
				std::this_thread::sleep_for(1s);
			}

			if (!running)
			{
				return json{{"error", "the dedicated server did not start the map"}, {"test", test.name}, {"status", status}};
			}

			// bots: spawnBot uses the normal bot path (name, class, team)
			const auto bots = test.dvars.value("mwx_test_bots", 0);
			if (bots > 0)
			{
				rpc(id, "command", {{"command", "spawnBot " + std::to_string(bots)}}, 10);
				std::this_thread::sleep_for(3s);
			}

			const auto deadline = start + std::chrono::seconds(test.timeout_s);
			json done{};
			json events{};
			std::set<int> handled_actions;
			auto server_exited = false;
			auto server_exit_code = -1;

			while (std::chrono::steady_clock::now() < deadline)
			{
				if (job && job->cancel)
				{
					break;
				}

				events = rpc(id, "events", {{"since", 0}, {"limit", 5000}}, 20);
				if (events.contains("result"))
				{
					for (const auto& event : events["result"]["events"])
					{
						if (event["type"] == "test_done")
						{
							done = event;
							break;
						}

						// the test asks the runner for a console command (late joiner, map change, ...)
						if (event["type"] == "test_action" && event["data"].contains("command"))
						{
							const auto idnum = event.value("id", 0);
							if (!handled_actions.contains(idnum))
							{
								handled_actions.insert(idnum);
								const auto command = event["data"]["command"].get<std::string>();
								fprintf(stderr, "mwx mcp: test %s runs '%s'\n", test.name.data(), command.data());
								rpc(id, "command", {{"command", command}}, 10);
							}
						}
					}
				}

				if (!done.is_null())
				{
					break;
				}

				if (const auto instance = find_instance(id); instance.has_value() && instance->info.hProcess &&
					!process_running(instance.value()))
				{
					server_exited = true;
					server_exit_code = process_exit_code(instance.value());
					break;
				}

				std::this_thread::sleep_for(1s);
			}

			json failures = json::array();
			json steps = json::array();
			auto passed = 0;
			auto failed = 0;
			auto script_errors = 0;
			auto kills = 0;
			std::set<std::string> kill_weapons;
			std::int64_t started_ms = 0;
			std::int64_t done_ms = 0;

			if (events.contains("result"))
			{
				for (const auto& event : events["result"]["events"])
				{
					if (event["type"] == "script_error")
					{
						script_errors++;
					}
					else if (event["type"] == "test_started")
					{
						started_ms = event.value("time_ms", 0);
					}
					else if (event["type"] == "test_assert")
					{
						const auto& data = event["data"];

						auto ok = false;
						if (data.contains("ok"))
						{
							if (data["ok"].is_boolean())
							{
								ok = data["ok"].get<bool>();
							}
							else if (data["ok"].is_number())
							{
								ok = data["ok"].get<double>() != 0.0;
							}
						}

						if (ok)
						{
							passed++;
						}
						else
						{
							failed++;
							failures.emplace_back(data);
						}
					}
					else if (event["type"] == "test_done")
					{
						done_ms = event.value("time_ms", 0);
					}
					else if (event["type"] == "test_step")
					{
						steps.emplace_back(event["data"]);
					}
					else if (event["type"] == "kill")
					{
						// the weapons of every kill in the run, so a test result also shows what the
						// match was fought with (no killstreak weapons in Infected, ...)
						const auto& data = event["data"];
						if (data.contains("weapon") && data["weapon"].is_string())
						{
							kill_weapons.insert(data["weapon"].get<std::string>());
						}
						kills++;
					}
				}
			}

			const auto duration = done_ms > started_ms ? (done_ms - started_ms) / 1000.0 : 0.0;
			const auto total_wait = std::chrono::duration_cast<std::chrono::milliseconds>(
				std::chrono::steady_clock::now() - start).count() / 1000.0;

			json result{};
			result["test"] = test.name;
			result["script"] = test.script;
			result["map"] = test.map;
			result["gametype"] = test.gametype;
			result["mod"] = test.mod;
			result["listen"] = test.listen;
			result["port"] = started.value("port", 0);
			result["net_port"] = started.value("net_port", 0);
			result["passed"] = passed;
			result["failed"] = failed;
			result["failures"] = failures;
			result["steps"] = steps;
			result["script_errors"] = script_errors;
			result["kills"] = kills;
			result["kill_weapons"] = kill_weapons;
			result["done"] = !done.is_null() && done["data"].contains("ok") && done["data"]["ok"].is_number() &&
				done["data"]["ok"].get<double>() != 0.0;
			result["duration_s"] = duration;
			result["total_s"] = total_wait;

			if (done.is_null())
			{
				result["error"] = server_exited
					? "server exited (code " + std::to_string(server_exit_code) + ")"
					: "timeout waiting for test_done";
			}

			return result;
		}

		json run_test(const json& args)
		{
			const auto name = args.value("name", "");
			if (name.empty())
			{
				return json{{"error", "name is required"}, {"tests", list_tests()}};
			}

			if (!find_test(name).has_value())
			{
				return json{{"error", "unknown test: " + name}, {"tests", list_tests()}};
			}

			return start_test_job(name, false);
		}

		json run_all_tests(const json& args)
		{
			const auto only = args.value("name", "");
			if (!only.empty() && !find_test(only).has_value())
			{
				return json{{"error", "unknown test: " + only}, {"tests", list_tests()}};
			}

			return start_test_job(only.empty() ? "all" : only, true);
		}

		json target_schema()
		{
			return {{"type", "string"},
				{"description", "Instance id from start_client/start_server (e.g. c1, s1), a debug port, or 'client'/'server' (default instance of that kind)."}};
		}

		json tools()
		{
			return json::array({
				{
					{"name", "game_status"},
					{"description", "State of a running mwx instance: map, game type, main menu / in game, connected server, players (name, team, score, ping, bot, position)."},
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
					{"description", "Starts mwx.exe (dedicated=true for a dedicated server). Older alias of start_client/start_server; returns an instance id."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"dedicated", {{"type", "boolean"}}}, {"args", {{"type", "string"}}}}}}},
				},
				{
					{"name", "start_client"},
					{"description", "Starts a game client. Optional: map, gametype, mod ('mods/<name>'), dvars {name: value}, resolution ('960x540'), args, port. Test mode (windowed, muted, no mouse capture) is on by default."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"map", {{"type", "string"}}}, {"gametype", {{"type", "string"}}}, {"mod", {{"type", "string"}}},
						{"dvars", {{"type", "object"}}}, {"resolution", {{"type", "string"}}}, {"args", {{"type", "string"}}},
						{"test_mode", {{"type", "boolean"}}}, {"port", {{"type", "integer"}}}}}}},
				},
				{
					{"name", "start_server"},
					{"description", "Starts a dedicated server. Optional: map, gametype, mod, dvars, args, port. Map defaults to map_rotate with server_default.cfg."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"map", {{"type", "string"}}}, {"gametype", {{"type", "string"}}}, {"mod", {{"type", "string"}}},
						{"dvars", {{"type", "object"}}}, {"args", {{"type", "string"}}}, {"port", {{"type", "integer"}}}}}}},
				},
				{
					{"name", "list_instances"},
					{"description", "The instances this MCP server started: id, port, pid, running, command line, status."},
					{"inputSchema", {{"type", "object"}, {"properties", json::object()}}},
				},
				{
					{"name", "stop_instance"},
					{"description", "Stops an instance this MCP server started (id from start_client/start_server). Terminates it after 10 s if it doesn't quit."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"id", {{"type", "string"}}}}}, {"required", {"id"}}}},
				},
				{
					{"name", "stop_game"},
					{"description", "Quits a running mwx instance (target 'client'/'server' or an instance id)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "connect_client_to_server"},
					{"description", "Connects a client to a dedicated server or host on 127.0.0.1 (uses the server's net_port)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"client", target_schema()}, {"server", target_schema()}}}}},
				},
				{
					{"name", "wait_for"},
					{"description", "Waits (inside the game, no polling by the client) until a condition is true. state: main_menu, in_game, server_running, map_loaded (value = map name), menu_open (name), player_count (count, op '>=' or '=='), dvar (name, value), event (type, filter). Returns {reached, waited_ms, details}."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"state", {{"type", "string"}}}, {"timeout_s", {{"type", "integer"}}},
						{"value", {{"type", "string"}}}, {"name", {{"type", "string"}}}, {"type", {{"type", "string"}}},
						{"filter", {{"type", "string"}}}, {"count", {{"type", "integer"}}}, {"op", {{"type", "string"}}},
						{"target", target_schema()}}}, {"required", {"state"}}}},
				},
				{
					{"name", "screenshot"},
					{"description", "Native screenshot of the rendered frame (also while the window is not focused). Returns the PNG as an image and saves it to mwx-screenshots/<timestamp>.png. Optional scale (0.5) and region {x,y,width,height}."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"scale", {{"type", "number"}}}, {"region", {{"type", "object"}}}, {"path", {{"type", "string"}}},
						{"target", target_schema()}}}}},
				},
				{
					{"name", "ui_snapshot"},
					{"description", "Tree of the visible LUI menu elements: menu stack, and per element id, type, text, visible, focused, disabled, position/size."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "ui_click"},
					{"description", "Clicks a menu element through the normal button path: by id or by visible text (and optional index). Returns what was clicked."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"id", {{"type", "string"}}}, {"text", {{"type", "string"}}}, {"index", {{"type", "integer"}}}, {"target", target_schema()}}}}},
				},
				{
					{"name", "ui_back"},
					{"description", "Leaves the top menu (LUI.FlowManager.RequestLeaveMenuByName of the top menu)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "ui_open"},
					{"description", "Opens a LUI menu by name (LUI.FlowManager.RequestAddMenu)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"name", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"name"}}}},
				},
				{
					{"name", "lua_eval"},
					{"description", "Runs Lua in the LUI state and returns the result as JSON. Debug only."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"code", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"code"}}}},
				},
				{
					{"name", "gsc_eval"},
					{"description", "Runs a GSC snippet in the running server script VM and returns its result (e.g. 'return level.gametype;'). Errors come back as text."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"code", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"code"}}}},
				},
				{
					{"name", "input"},
					{"description", "Input without OS focus. action: press|hold|move|release|look|stop; command ('+attack', 'weapnext', '-forward'); ms; for look: pitch/yaw or look_at [x,y,z]. Works through the engine commands."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"action", {{"type", "string"}}}, {"command", {{"type", "string"}}}, {"ms", {{"type", "integer"}}},
						{"pitch", {{"type", "number"}}}, {"yaw", {{"type", "number"}}},
						{"look_at", {{"type", "array"}, {"items", {{"type", "number"}}}}}, {"target", target_schema()}}}, {"required", {"action"}}}},
				},
				{
					{"name", "players"},
					{"description", "Server-side player list: name, num, bot, team, alive, health, score, kills, deaths, origin, angles, current weapon, weapons with clip/stock, perks, class."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "entities"},
					{"description", "Entities by classname, targetname, or near a point. Returns classname, origin, model, targetname."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"classname", {{"type", "string"}}}, {"targetname", {{"type", "string"}}},
						{"origin", {{"type", "array"}}}, {"radius", {{"type", "number"}}}, {"limit", {{"type", "integer"}}},
						{"target", target_schema()}}}}},
				},
				{
					{"name", "bots"},
					{"description", "Bots: action spawn (count), kick (num), team (num, team), freeze / unfreeze (num)."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"action", {{"type", "string"}}}, {"count", {{"type", "integer"}}}, {"num", {{"type", "integer"}}},
						{"team", {{"type", "string"}}}, {"target", target_schema()}}}, {"required", {"action"}}}},
				},
				{
					{"name", "model_bounds"},
					{"description", "XModel asset bounds: model or models[] -> {model, loaded, mins, maxs, radius, contents}. Used to size Prop Hunt props."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"model", {{"type", "string"}}},
						{"models", {{"type", "array"}, {"items", {{"type", "string"}}}}},
						{"target", target_schema()}}}}},
				},
				{
					{"name", "events"},
					{"description", "Server-side event stream with a cursor: since = last id. Types: kill, damage, join, quit, spawn, team_change, match_end, script_error, console_error, console_warning, test_assert, test_done. 5000 events are kept."},
					{"inputSchema", {{"type", "object"}, {"properties", {
						{"since", {{"type", "integer"}}}, {"type", {{"type", "string"}}}, {"limit", {{"type", "integer"}}},
						{"target", target_schema()}}}}},
				},
				{
					{"name", "perf"},
					{"description", "fps, frame time, uptime, memory, map/gametype, players, and the zone load times of this start."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "last_crash"},
					{"description", "The newest minidump: file name, time, size and the info.txt content."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"target", target_schema()}}}}},
				},
				{
					{"name", "list_tests"},
					{"description", "Game mode tests from GAME\\mwx\\tests\\tests.json."},
					{"inputSchema", {{"type", "object"}, {"properties", json::object()}}},
				},
				{
					{"name", "run_test"},
					{"description", "Starts one game mode test in the background (dedicated server with mwx_test=<name>, the test dvars and bots). Returns a job id at once; poll test_status for the result (a run takes minutes)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"name", {{"type", "string"}}}}}, {"required", {"name"}}}},
				},
				{
					{"name", "run_all_tests"},
					{"description", "Starts every test from tests.json in a row in the background (or only the one given as name). Returns a job id; poll test_status."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"name", {{"type", "string"}}}}}}},
				},
				{
					{"name", "test_status"},
					{"description", "State and result of test jobs: job id, name, running/done, passed/failed/failures/steps/script_errors/duration. Without a job id: all jobs, newest first."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"job", {{"type", "string"}}}}}}},
				},
				{
					{"name", "cancel_test"},
					{"description", "Cancels a running test job (stops its server)."},
					{"inputSchema", {{"type", "object"}, {"properties", {{"job", {{"type", "string"}}}}}}},
				},
			});
		}

		json call_tool(const std::string& name, const json& args)
		{
			const auto target = args.value("target", "client");

			if (name == "game_status") return rpc(target, "status");
			if (name == "run_command") return rpc(target, "command", {{"command", args.value("command", "")}}, 10);
			if (name == "get_dvar") return rpc(target, "get_dvar", {{"name", args.value("name", "")}});
			if (name == "set_dvar") return rpc(target, "set_dvar", {{"name", args.value("name", "")}, {"value", args.value("value", "")}});
			if (name == "console_log") return rpc(target, "console", {{"lines", args.value("lines", 100)}, {"filter", args.value("filter", "")}});
			if (name == "load_times") return rpc(target, "load_times");
			if (name == "perf") return rpc(target, "perf", json::object(), 10);
			if (name == "last_crash") return rpc(target, "last_crash");
			if (name == "list_tests") return json{{"tests", list_tests()}};
			if (name == "run_test") return run_test(args);
			if (name == "run_all_tests") return run_all_tests(args);
			if (name == "test_status") return test_status(args);
			if (name == "cancel_test") return cancel_test(args);
			if (name == "events") return rpc(target, "events", {{"since", args.value("since", 0)}, {"type", args.value("type", "")}, {"limit", args.value("limit", 0)}});

			if (name == "start_game")
			{
				return start_instance(args.value("dedicated", false), args);
			}
			if (name == "start_client") return start_instance(false, args);
			if (name == "start_server") return start_instance(true, args);
			if (name == "list_instances") return list_instances();
			if (name == "stop_instance") return stop_instance(args.value("id", ""));
			if (name == "stop_game")
			{
				if (const auto instance = find_instance(target))
				{
					return stop_instance(instance->id);
				}

				const auto answer = rpc(target, "command", {{"command", "quit"}}, 2);
				return answer.contains("error") ? answer : json{{"result", "quit command sent"}};
			}

			if (name == "connect_client_to_server")
			{
				const auto client = args.value("client", "client");
				const auto server = args.value("server", "server");
				const auto status = rpc(server, "status");
				if (!status.contains("result"))
				{
					return status;
				}

				const auto port = status["result"].value("net_port", "27016");
				const auto command = "connect 127.0.0.1:" + port;
				auto answer = rpc(client, "command", {{"command", command}}, 10);
				if (answer.contains("error"))
				{
					return answer;
				}

				return json{{"result", command}, {"server", server}};
			}

			if (name == "wait_for") return wait_for(args);

			if (name == "screenshot")
			{
				json params{};
				if (args.contains("scale")) params["scale"] = args["scale"];
				if (args.contains("region")) params["region"] = args["region"];
				if (args.contains("path")) params["path"] = args["path"];
				return rpc(target, "screenshot", params, 30);
			}

			if (name == "ui_snapshot") return rpc(target, "ui_snapshot", json::object(), 20);
			if (name == "ui_click") return rpc(target, "ui_click", args, 20);
			if (name == "ui_back") return rpc(target, "ui_back", json::object(), 20);
			if (name == "ui_open") return rpc(target, "ui_open", {{"name", args.value("name", "")}}, 20);
			if (name == "lua_eval") return rpc(target, "lua_eval", {{"code", args.value("code", "")}}, 30);
			if (name == "gsc_eval") return rpc(target, "gsc_eval", {{"code", args.value("code", "")}}, 40);
			if (name == "players") return rpc(target, "players", json::object(), 30);
			if (name == "entities") return rpc(target, "entities", args, 30);
			if (name == "model_bounds") return rpc(target, "model_bounds", args, 60);
			if (name == "bots") return rpc(target, "bots", args, 30);

			if (name == "input")
			{
				json params = args;
				params.erase("target");
				return rpc(target, "input", params, 15);
			}

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
					{"instructions", "MWX (HorizonMW-based CoD:MWR LAN client) test interface. Instances: start_client/start_server/list_instances/stop_instance. Inspect and drive: game_status, players, events, ui_snapshot/ui_click, screenshot, gsc_eval, lua_eval, input, bots, wait_for. target = instance id, port, or client/server."},
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

				// screenshots: return the PNG as an MCP image content block
				if (name == "screenshot" && !is_error && payload.is_object() && payload.contains("png_base64"))
				{
					json content = json::array();
					content.emplace_back(json{{"type", "image"}, {"data", payload["png_base64"]}, {"mimeType", "image/png"}});
					content.emplace_back(json{{"type", "text"}, {"text", "saved to " + payload.value("path", "") +
						" (" + std::to_string(payload.value("width", 0)) + "x" + std::to_string(payload.value("height", 0)) + ")"}});
					reply({{"content", content}, {"isError", false}});
					return;
				}

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

		{
			std::lock_guard _(instance_mutex);
			for (auto& instance : instances)
			{
				if (instance.info.hProcess)
				{
					CloseHandle(instance.info.hProcess);
					CloseHandle(instance.info.hThread);
				}
			}
		}

		return 0;
	}
}

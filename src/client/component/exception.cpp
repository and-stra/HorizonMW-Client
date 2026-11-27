#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "exception.hpp"
#include "scheduler.hpp"
#include "system_check.hpp"
#include "version.hpp"

#include <tlhelp32.h>

#include "game/dvars.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/string.hpp>
#include <utils/thread.hpp>
#include <utils/compression.hpp>

#include <exception/minidump.hpp>

#include <dbghelp.h>

#pragma comment(lib, "dbghelp.lib")

namespace exception
{
	namespace
	{
		thread_local struct
		{
			DWORD code = 0;
			PVOID address = nullptr;
		} exception_data;

		struct
		{
			std::chrono::time_point<std::chrono::high_resolution_clock> last_recovery{};
			std::atomic<int> recovery_counts = {0};
		} recovery_data;

		bool is_game_thread()
		{
			static std::vector<int> allowed_threads =
			{
				game::THREAD_CONTEXT_MAIN,
			};

			const auto self_id = GetCurrentThreadId();
			for (const auto& index : allowed_threads)
			{
				if (game::threadIds[index] == self_id)
				{
					return true;
				}
			}

			return false;
		}

		bool is_exception_interval_too_short()
		{
			const auto delta = std::chrono::high_resolution_clock::now() - recovery_data.last_recovery;
			return delta < 1min;
		}

		bool too_many_exceptions_occured()
		{
			return recovery_data.recovery_counts >= 3;
		}

		volatile bool& is_initialized()
		{
			static volatile bool initialized = false;
			return initialized;
		}

		bool is_recoverable()
		{
			return is_initialized()
				&& is_game_thread()
				&& !is_exception_interval_too_short()
				&& !too_many_exceptions_occured();
		}

		void show_mouse_cursor()
		{
			while (ShowCursor(TRUE) < 0);
		}

		void display_error_dialog()
		{
			std::string error_str = utils::string::va("Fatal error (0x%08X) at 0x%p (0x%p).\n"
			                                          "A minidump has been written.\n\n",
			                                          exception_data.code, exception_data.address, 
			                                          reinterpret_cast<uint64_t>(exception_data.address) - game::base_address);

			if (!system_check::is_valid())
			{
				error_str += "Make sure to get supported game files to avoid such crashes!";
			}
			else
			{
				error_str += "Make sure to update your graphics card drivers and install operating system updates!";
			}

			utils::thread::suspend_other_threads();
			show_mouse_cursor();

			MSG_BOX_ERROR(error_str.data());
			TerminateProcess(GetCurrentProcess(), exception_data.code);
		}

		void reset_state()
		{
			if (dvars::cg_legacyCrashHandling && dvars::cg_legacyCrashHandling->current.enabled)
			{
				display_error_dialog();
			}

			// TODO: Add a limit for dedi restarts
			if (game::environment::is_dedi())
			{
				utils::nt::relaunch_self();
				utils::nt::terminate(exception_data.code);
			}

			if (is_recoverable())
			{
				recovery_data.last_recovery = std::chrono::high_resolution_clock::now();
				++recovery_data.recovery_counts;

				game::Com_Error(game::ERR_DROP, "Fatal error (0x%08X) at 0x%p.\nA minidump has been written.\n\n"
				                "HorizonMW has tried to recover your game, but it might not run stable anymore.\n\n"
				                "Make sure to update your graphics card drivers and install operating system updates!\n",
				                exception_data.code, exception_data.address);
			}
			else
			{
				display_error_dialog();
			}
		}

		size_t get_reset_state_stub()
		{
			static auto* stub = utils::hook::assemble([](utils::hook::assembler& a)
			{
				a.sub(rsp, 0x10);
				a.or_(rsp, 0x8);
				a.jmp(reset_state);
			});

			return reinterpret_cast<size_t>(stub);
		}

		std::string get_timestamp()
		{
			tm ltime{};
			char timestamp[MAX_PATH] = {0};
			const auto time = _time64(nullptr);

			_localtime64_s(&ltime, &time);
			strftime(timestamp, sizeof(timestamp) - 1, "%Y-%m-%d-%H-%M-%S", &ltime);

			return timestamp;
		}

		std::vector<std::string> get_call_stack(const LPEXCEPTION_POINTERS exceptioninfo)
		{
			std::vector<std::string> frames{};

			const auto process = GetCurrentProcess();
			SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
			if (!SymInitialize(process, nullptr, TRUE))
			{
				return frames;
			}

			const auto cleanup = gsl::finally([&] { SymCleanup(process); });

			auto* context = exceptioninfo->ContextRecord;

			STACKFRAME64 frame{};
			frame.AddrPC.Offset = context->Rip;
			frame.AddrPC.Mode = AddrModeFlat;
			frame.AddrFrame.Offset = context->Rbp;
			frame.AddrFrame.Mode = AddrModeFlat;
			frame.AddrStack.Offset = context->Rsp;
			frame.AddrStack.Mode = AddrModeFlat;

			for (auto i = 0; i < 32; ++i)
			{
				if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, GetCurrentThread(), &frame, context, nullptr,
					SymFunctionTableAccess64, SymGetModuleBase64, nullptr))
				{
					break;
				}

				if (frame.AddrPC.Offset == 0)
				{
					break;
				}

				std::string text = utils::string::va("%-18s 0x%llX", "?", frame.AddrPC.Offset);

				std::array<char, sizeof(SYMBOL_INFO) + 256> buffer{};
				auto* symbol = reinterpret_cast<SYMBOL_INFO*>(buffer.data());
				symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
				symbol->MaxNameLen = 255;

				DWORD64 displacement = 0;
				if (SymFromAddr(process, frame.AddrPC.Offset, &displacement, symbol))
				{
					text = utils::string::va("%s+0x%llX", symbol->Name, displacement);
					text += utils::string::va(" 0x%llX", frame.AddrPC.Offset);

					IMAGEHLP_LINE64 line{};
					line.SizeOfStruct = sizeof(line);
					DWORD line_displacement = 0;
					if (SymGetLineFromAddr64(process, frame.AddrPC.Offset, &line_displacement, &line))
					{
						text += utils::string::va(" (%s:%lu)", line.FileName, line.LineNumber);
					}
				}

				frames.push_back(text);
			}

			return frames;
		}

		std::string generate_crash_info(const LPEXCEPTION_POINTERS exceptioninfo)
		{
			std::string info{};
			const auto line = [&info](const std::string& text)
			{
				info.append(text);
				info.append("\r\n");
			};

			line("HorizonMW Crash Dump");
			line("");
			line("Version: "s + VERSION);
			line("Environment: "s + game::environment::get_string());
			line("Timestamp: "s + get_timestamp());
			line("Clean game: "s + (system_check::is_valid() ? "Yes" : "No"));
			line(utils::string::va("Exception: 0x%08X", exceptioninfo->ExceptionRecord->ExceptionCode));
			line(utils::string::va("Address: 0x%llX", exceptioninfo->ExceptionRecord->ExceptionAddress));
			line(utils::string::va("Base: 0x%llX", game::base_address));

#pragma warning(push)
#pragma warning(disable: 4996)
			OSVERSIONINFOEXA version_info;
			ZeroMemory(&version_info, sizeof(version_info));
			version_info.dwOSVersionInfoSize = sizeof(version_info);
			GetVersionExA(reinterpret_cast<LPOSVERSIONINFOA>(&version_info));
#pragma warning(pop)

			line(utils::string::va("OS Version: %u.%u", version_info.dwMajorVersion, version_info.dwMinorVersion));

			// MWX: a readable call stack, so last_crash (debug interface / MCP) shows where it died
			line("");
			line("Call stack:");
			for (const auto& frame : get_call_stack(exceptioninfo))
			{
				line("  " + frame);
			}

			return info;
		}

		void write_minidump(const LPEXCEPTION_POINTERS exceptioninfo)
		{
			const std::string crash_name = utils::string::va("minidumps/hmw-mod-crash-%d-%s.zip",
			                                                 game::environment::get_real_mode(),
			                                                 get_timestamp().data());

			const auto info = generate_crash_info(exceptioninfo);

			utils::compression::zip::archive zip_file{};
			zip_file.add("crash.dmp", create_minidump(exceptioninfo));
			zip_file.add("info.txt", info);
			zip_file.write(crash_name, "HorizonMW Crash Dump");

			// MWX: the same text next to the dump, readable without unpacking the zip
			// (last_crash in the debug interface / MCP)
			utils::io::create_directory("mwx-logs");
			utils::io::write_file("mwx-logs/last_crash.txt",
				crash_name + "\n\n" + info);
		}

		bool is_harmless_error(const LPEXCEPTION_POINTERS exceptioninfo)
		{
			const auto code = exceptioninfo->ExceptionRecord->ExceptionCode;
			return code == STATUS_INTEGER_OVERFLOW || code == STATUS_FLOAT_OVERFLOW || code == STATUS_SINGLE_STEP;
		}

		LONG WINAPI exception_filter(const LPEXCEPTION_POINTERS exceptioninfo)
		{
			if (is_harmless_error(exceptioninfo))
			{
				return EXCEPTION_CONTINUE_EXECUTION;
			}

			write_minidump(exceptioninfo);

			exception_data.code = exceptioninfo->ExceptionRecord->ExceptionCode;
			exception_data.address = exceptioninfo->ExceptionRecord->ExceptionAddress;
			exceptioninfo->ContextRecord->Rip = get_reset_state_stub();

			return EXCEPTION_CONTINUE_EXECUTION;
		}

		LPTOP_LEVEL_EXCEPTION_FILTER WINAPI set_unhandled_exception_filter_stub(LPTOP_LEVEL_EXCEPTION_FILTER)
		{
			// Don't register anything here...
			return &exception_filter;
		}
	}

	std::vector<std::string> get_thread_stacks(const unsigned int process_id)
	{
		std::vector<std::string> result;

		const auto process = GetCurrentProcess();
		SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
		if (!SymInitialize(process, nullptr, TRUE))
		{
			return result;
		}

		const auto cleanup = gsl::finally([&] { SymCleanup(process); });

		const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
		if (snapshot == INVALID_HANDLE_VALUE)
		{
			return result;
		}

		const auto close_snapshot = gsl::finally([&] { CloseHandle(snapshot); });

		THREADENTRY32 entry{};
		entry.dwSize = sizeof(entry);

		for (auto ok = Thread32First(snapshot, &entry); ok; ok = Thread32Next(snapshot, &entry))
		{
			if (entry.th32OwnerProcessID != process_id || entry.th32ThreadID == GetCurrentThreadId())
			{
				continue;
			}

			const auto thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION,
				FALSE, entry.th32ThreadID);
			if (thread == nullptr)
			{
				continue;
			}

			const auto close_thread = gsl::finally([&] { CloseHandle(thread); });

			SuspendThread(thread);

			CONTEXT context{};
			context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;

			if (GetThreadContext(thread, &context))
			{
				STACKFRAME64 frame{};
				frame.AddrPC.Offset = context.Rip;
				frame.AddrPC.Mode = AddrModeFlat;
				frame.AddrFrame.Offset = context.Rbp;
				frame.AddrFrame.Mode = AddrModeFlat;
				frame.AddrStack.Offset = context.Rsp;
				frame.AddrStack.Mode = AddrModeFlat;

				result.push_back(utils::string::va("--- thread %u (rip 0x%llX) ---",
					entry.th32ThreadID, context.Rip));

				for (auto i = 0; i < 24; ++i)
				{
					if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame, &context, nullptr,
						SymFunctionTableAccess64, SymGetModuleBase64, nullptr))
					{
						break;
					}

					if (frame.AddrPC.Offset == 0)
					{
						break;
					}

					std::string text = utils::string::va("0x%llX", frame.AddrPC.Offset);

					IMAGEHLP_MODULE64 module{};
					module.SizeOfStruct = sizeof(module);
					if (SymGetModuleInfo64(process, frame.AddrPC.Offset, &module))
					{
						text += utils::string::va(" %s+0x%llX", module.ModuleName,
							frame.AddrPC.Offset - module.BaseOfImage);
					}

					result.push_back("    " + text);
				}
			}

			ResumeThread(thread);
		}

		return result;
	}

	class component final : public component_interface
	{
	public:
		component()
		{
			SetUnhandledExceptionFilter(exception_filter);
		}

		void post_load() override
		{
			SetUnhandledExceptionFilter(exception_filter);
			utils::hook::jump(SetUnhandledExceptionFilter, set_unhandled_exception_filter_stub, true);

			scheduler::on_game_initialized([]
			{
				is_initialized() = true;
			});
		}

		void post_unpack() override
		{
			dvars::cg_legacyCrashHandling = dvars::register_bool("cg_legacyCrashHandling", 
				false, game::DVAR_FLAG_SAVED, "Toggle better crash handling");
		}
	};
}

REGISTER_COMPONENT(exception::component)

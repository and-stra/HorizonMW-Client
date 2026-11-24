#pragma once

#include "game/scripting/entity.hpp"
#include "game/scripting/execution.hpp"

namespace logfile
{
	extern bool hook_enabled;

	void set_gsc_hook(const char* source, const char* target);
	void clear_hook(const char* pos);
	size_t get_hook_count();

	void clear_callbacks();

	void enable_vm_execute_hook();
	void disable_vm_execute_hook();

	bool client_command_stub(const int client_num);

	// MWX: called with every formatted game log line (G_LogPrintf), before it is written to
	// the log file. Used by the test interface for the kill/damage/join event stream.
	// Must be fast and must not log.
	void add_line_callback(const std::function<void(const std::string&)>& callback);
}
#pragma once

#include <string>
#include <vector>

namespace exception
{
	// Walks the stacks of every thread of the given process (called from the debug server thread,
	// which is not the stalled game thread). Used to inspect a hung load without a debugger.
	std::vector<std::string> get_thread_stacks(unsigned int process_id);
}

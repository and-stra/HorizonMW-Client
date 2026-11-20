#pragma once

namespace load_timing
{
	// Called when the game starts reading a fastfile (DB_InitLoadXFile).
	void zone_start(const char* name);

	// Writes one line (with the time since start) to the console and to mwx-logs\load_times.log.
	void mark(const std::string& event);
}

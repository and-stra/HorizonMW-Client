#pragma once

namespace load_timing
{
	// Called when the game starts reading a fastfile (DB_InitLoadXFile).
	void zone_start(const char* name);

	// Starts a new block in the log (called at the start of main)
	void begin(bool dedicated);

	// Serializes the engine's early init with other MWX processes in this session. A second
	// process started while another one is still initializing exits silently (no output, no
	// crash dump), so the init phase is guarded by a named mutex. Released automatically on
	// the first main-thread frame (or after a watchdog timeout / process exit).
	void acquire_startup_lock();
	void release_startup_lock();

	// Writes one line (with the time since start) to the console and to mwx-logs\load_times.log.
	void mark(const std::string& event);
}

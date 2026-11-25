#pragma once

namespace filesystem
{
	// Names of the client's own data and log folders. Kept in one place so the planned rename
	// (mwx -> hmw) only has to change these two constants; -datadir/-logdir override them at runtime.
	inline constexpr auto default_data_dir = "mwx";
	inline constexpr auto default_log_dir = "mwx-logs";

	std::string read_file(const std::string& path);
	bool read_file(const std::string& path, std::string* data, std::string* real_path = nullptr);
	bool find_file(const std::string& path, std::string* real_path);
	bool exists(const std::string& path);

	void register_path(const std::filesystem::path& path);
	void unregister_path(const std::filesystem::path& path);

	std::vector<std::string> get_search_paths();
	std::vector<std::string> get_search_paths_rev();

	// Data folder ("mwx" by default) and log folder ("mwx-logs" by default). A test build can point
	// them elsewhere with -datadir <dir> / -logdir <dir> (e.g. a separate client next to the game).
	std::string get_data_dir();
	std::string get_log_dir();
}

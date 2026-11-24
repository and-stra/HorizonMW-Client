#pragma once
#include <utils/concurrency.hpp>

#include "game/game.hpp"
#include "game/scripting/script_value.hpp"

namespace scripting
{
	using shared_table_t = std::unordered_map<std::string, std::string>;

	extern std::unordered_map<int, std::unordered_map<std::string, int>> fields_table;
	extern std::unordered_map<std::string, std::unordered_map<std::string, const char*>> script_function_table;
	extern std::unordered_map<std::string, std::vector<std::pair<std::string, const char*>>> script_function_table_sort;
	extern std::unordered_map<const char*, std::pair<std::string, std::string>> script_function_table_rev;

	extern utils::concurrency::container<shared_table_t> shared_table;

	extern std::string current_file;
	extern unsigned int current_file_id;

	// MWX: called for every GSC notify (Script_VM notify), on the server thread. Used by the
	// debug interface for the event stream (spawn, team change, match end, ...). Must be fast.
	using notify_callback = std::function<void(const std::string& name, unsigned int entity,
		const std::vector<scripting::script_value>& arguments)>;
	void add_notify_callback(notify_callback callback);

	void on_shutdown(const std::function<void(bool, bool)>& callback);
	std::optional<std::string> get_canonical_string(const unsigned int id);
	std::string get_token(unsigned int id);
}
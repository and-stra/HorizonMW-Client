#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "command.hpp"
#include "console.hpp"
#include "filesystem.hpp"
#include "fonts.hpp"
#include "localized_strings.hpp"
#include "mods.hpp"
#include "scheduler.hpp"

#include <json.hpp>

#include <utils/flags.hpp>
#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/nt.hpp>
#include <utils/string.hpp>

// MWX: mod support. A mod is a folder mods/<name>/ with
//   mod.json      name, description, author, version, optional "gametypes"
//   mod.ff        optional zone (weapons, models, ...), loaded by the engine through fs_game
//   maps/, scripts/mp/ ...  raw GSC (gametype scripts, script mods)
// Loading or unloading a mod relaunches the game with -mod, so every zone, table and menu is built
// fresh with the mod (no partial reloads).
namespace mods
{
	namespace
	{
		std::optional<std::string> mod_path;
		std::vector<mod_gametype> gametypes;

		utils::hook::detour db_release_xassets_hook;
		bool release_assets = false;

		void db_release_xassets_stub()
		{
			if (release_assets)
			{
				fonts::clear();
			}

			db_release_xassets_hook.invoke<void>();
		}

		std::string to_upper(std::string value)
		{
			std::transform(value.begin(), value.end(), value.begin(),
				[](const unsigned char c) { return static_cast<char>(std::toupper(c)); });
			return value;
		}

		std::optional<nlohmann::json> read_mod_json(const std::string& path)
		{
			std::string data;
			if (!utils::io::read_file(path + "/mod.json", &data))
			{
				return {};
			}

			try
			{
				return nlohmann::json::parse(data);
			}
			catch (const std::exception& e)
			{
				console::error("[mods] %s/mod.json: %s\n", path.data(), e.what());
				return {};
			}
		}

		void load_gametypes(const std::string& path)
		{
			gametypes.clear();

			const auto json = read_mod_json(path);
			if (!json || !json->contains("gametypes") || !(*json)["gametypes"].is_array())
			{
				return;
			}

			for (const auto& entry : (*json)["gametypes"])
			{
				const auto ref = entry.value("ref", "");
				if (ref.empty() || ref.size() > 16 || ref.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789_") != std::string::npos)
				{
					console::error("[mods] invalid gametype ref '%s' in %s/mod.json\n", ref.data(), path.data());
					continue;
				}

				const auto upper = to_upper(ref);
				const auto name = entry.value("name", ref);
				const auto desc = entry.value("description", "");
				const auto objective = entry.value("objective", desc);

				mod_gametype gametype{};
				gametype.ref = ref;
				gametype.template_ref = entry.value("template", "dm");
				gametype.name_key = "MWXMOD_" + upper;
				gametype.desc_key = "MWXMOD_" + upper + "_DESC";
				gametype.class_choice = entry.value("class_choice", false);

				localized_strings::override(gametype.name_key, name);
				localized_strings::override(gametype.name_key + "_CAPS", to_upper(name));
				localized_strings::override(gametype.desc_key, desc);
				localized_strings::override(upper, to_upper(name)); // loading screen ("@" .. upper(ref))

				for (const auto& key : {ref, upper})
				{
					localized_strings::override("OBJECTIVES_" + key, objective);
					localized_strings::override("OBJECTIVES_" + key + "_SCORE", objective);
					localized_strings::override("OBJECTIVES_" + key + "_HINT", objective);
				}

				if (entry.contains("strings") && entry["strings"].is_object())
				{
					for (const auto& [key, value] : entry["strings"].items())
					{
						if (value.is_string())
						{
							localized_strings::override(key, value.get<std::string>());
						}
					}
				}

				console::info("[mods] gametype %s (%s)\n", ref.data(), name.data());
				gametypes.push_back(std::move(gametype));
			}
		}

		bool is_valid_mod_path(const std::string& path)
		{
			return path.starts_with("mods/") && path.find("..") == std::string::npos &&
				path.find(':') == std::string::npos && utils::io::directory_exists(path);
		}

		void relaunch(const std::string& path)
		{
			const utils::nt::library self;
			auto command_line = "\"" + self.get_path().generic_string() + "\"";
			if (!path.empty())
			{
				command_line += " -mod \"" + path + "\"";
			}

			console::info("[mods] relaunching: %s\n", command_line.data());
			utils::nt::relaunch_self(command_line, true);
			utils::nt::terminate();
		}

		bool can_change_mod()
		{
			// MWX: the plain HMW main menu reports Com_InFrontend() == false (same quirk the debug server works around); use "cgame is running and not in the virtual lobby" as the match test
			if (game::CL_IsCgameInitialized() && !game::VirtualLobby_Loaded())
			{
				console::info("Cannot change the mod while in a match!\n");
				return false;
			}

			return true;
		}
	}

	void set_mod(const std::string& path, const bool change_fs_game)
	{
		if (mod_path.has_value())
		{
			filesystem::unregister_path(mod_path.value());
		}

		if (change_fs_game)
		{
			game::Dvar_SetFromStringByNameFromSource("fs_game", path.data(), game::DVAR_SOURCE_INTERNAL);
		}

		if (path.empty())
		{
			mod_path.reset();
			gametypes.clear();
			return;
		}

		filesystem::register_path(path);
		mod_path = path;
		load_gametypes(path);
		console::info("[mods] loaded %s\n", path.data());
	}

	std::optional<std::string> get_mod()
	{
		return mod_path;
	}

	const std::vector<mod_gametype>& get_gametypes()
	{
		return gametypes;
	}

	std::string list_mods()
	{
		std::string result;
		if (!utils::io::directory_exists("mods"))
		{
			return result;
		}

		for (const auto& folder : utils::io::list_files("mods"))
		{
			if (!utils::io::directory_exists(folder) || utils::io::directory_is_empty(folder))
			{
				continue;
			}

			const auto path = folder; // "mods/<name>" (directory_iterator keeps the relative root)

			auto name = std::filesystem::path(folder).filename().generic_string();
			std::string desc;

			if (const auto json = read_mod_json(path))
			{
				name = json->value("name", name);
				desc = json->value("description", "");
				const auto author = json->value("author", "");
				const auto version = json->value("version", "");
				if (!author.empty() || !version.empty())
				{
					desc += "\n" + author + (version.empty() ? "" : " - v" + version);
				}
			}

			for (auto* text : {&name, &desc})
			{
				std::replace(text->begin(), text->end(), '\t', ' ');
			}
			std::replace(name.begin(), name.end(), '\n', ' ');

			result += path + "\t" + name + "\t" + desc + "\x1f";
		}

		return result;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!utils::io::directory_exists("mods"))
			{
				utils::io::create_directory("mods");
			}

			db_release_xassets_hook.create(0x399740_b, db_release_xassets_stub);

			localized_strings::override("MWX_MENU_MODS", "MODS");
			localized_strings::override("MWX_MENU_MODS_DESC", "Load a mod from the mods folder. The game restarts.");
			localized_strings::override("MWX_MODS_LOADED", "LOADED MOD");
			localized_strings::override("MWX_MODS_AVAILABLE", "AVAILABLE MODS");
			localized_strings::override("MWX_MODS_UNLOAD", "Unload mod");
			localized_strings::override("MWX_MODS_UNLOAD_DESC", "Return to the unmodded game. The game restarts.");
			localized_strings::override("MWX_MODS_NONE", "No mods found in the mods folder.");

			command::add("loadmod", [](const command::params& params)
			{
				if (params.size() < 2)
				{
					console::info("Usage: loadmod mods/<modname>\n");
					return;
				}

				const std::string path = params.get(1);
				if (!is_valid_mod_path(path))
				{
					console::info("Mod %s not found!\n", path.data());
					return;
				}

				if (!can_change_mod())
				{
					return;
				}

				relaunch(path);
			});

			command::add("unloadmod", []()
			{
				if (!mod_path.has_value())
				{
					console::info("No mod loaded\n");
					return;
				}

				if (!can_change_mod())
				{
					return;
				}

				relaunch("");
			});
		}
	};
}

REGISTER_COMPONENT(mods::component)

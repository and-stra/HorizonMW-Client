#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "command.hpp"
#include "console.hpp"
#include "dvars.hpp"
#include "fastfiles.hpp"
#include "filesystem.hpp"
#include "fonts.hpp"
#include "gamemodes.hpp"
#include "localized_strings.hpp"
#include "mods.hpp"
#include "scheduler.hpp"
#include "ui_scripting.hpp"

#include "game/dvars.hpp"

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
		std::vector<std::string> gametype_string_keys;

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

		void clear_gametype_strings()
		{
			for (const auto& key : gametype_string_keys)
			{
				localized_strings::remove(key);
			}

			gametype_string_keys.clear();
		}

		void add_gametype_string(const std::string& key, const std::string& value)
		{
			localized_strings::override(key, value);
			gametype_string_keys.push_back(key);
		}

		void load_gametypes(const std::string& path)
		{
			gametypes.clear();
			clear_gametype_strings();

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

				add_gametype_string(gametype.name_key, name);
				add_gametype_string(gametype.name_key + "_CAPS", to_upper(name));
				add_gametype_string(gametype.desc_key, desc);
				add_gametype_string(upper, to_upper(name)); // loading screen ("@" .. upper(ref))

				for (const auto& key : {ref, upper})
				{
					add_gametype_string("OBJECTIVES_" + key, objective);
					add_gametype_string("OBJECTIVES_" + key + "_SCORE", objective);
					add_gametype_string("OBJECTIVES_" + key + "_HINT", objective);
				}

				if (entry.contains("strings") && entry["strings"].is_object())
				{
					for (const auto& [key, value] : entry["strings"].items())
					{
						if (value.is_string())
						{
							add_gametype_string(key, value.get<std::string>());
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

		bool load_mod_zone()
		{
			if (!mod_path.has_value() || !fastfiles::exists("mod"))
			{
				return false;
			}

			console::info("[mods] loading the mod zone (%s/mod.ff)\n", mod_path->data());

			game::XZoneInfo info{};
			info.name = "mod";
			info.allocFlags = game::DB_ZONE_COMMON | game::DB_ZONE_CUSTOM;
			info.freeFlags = 0;
			// submit the load; switch_mod waits for the database before it restarts the menu
			game::DB_LoadXAssets(&info, 1u, game::DBSyncMode::DB_LOAD_SYNC);

			// the zone list gets a new slot for this load (reported by modzone status)
			console::info("[mods] mod zone load queued, zone count now %u\n", *game::g_zoneCount);
			return true;
		}

		bool unload_mod_zone()
		{
			console::info("[mods] unloading the mod zone\n");

			// The engine's own unload path for exactly this zone. XZoneInfo freeFlags matches by
			// flag, not by name, and would free every custom zone loaded with the same flags
			// (the hmw_* content zones): "Could not load default asset ... surfacefx".
			// unload_zone takes the newest "mod" slot, the active one after a reload.
			return fastfiles::unload_zone("mod", true);
		}

		void switch_mod(const std::string& path)
		{
			if (!can_change_mod())
			{
				return;
			}

			const auto current = mod_path.value_or("");
			if (current == path)
			{
				console::info("[mods] %s is already loaded\n", path.empty() ? "no mod" : path.data());
				return;
			}

			// M6 fallback: the old relaunch path (or an explicit mwx_mod_relaunch 1)
			if (const auto* relaunch_dvar = game::Dvar_FindVar("mwx_mod_relaunch");
				relaunch_dvar && relaunch_dvar->current.enabled)
			{
				relaunch(path);
				return;
			}

			const auto start = std::chrono::steady_clock::now();
			const auto elapsed_ms = [&start]()
			{
				return std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - start).count();
			};

			// never load a new mod.ff over the old one; if the old mod had a zone and the unload
			// fails, relaunch instead
			if (!current.empty() && fastfiles::exists("mod") && !unload_mod_zone())
			{
				console::error("[mods] the mod zone could not be unloaded, relaunching\n");
				relaunch(path);
				return;
			}

			const auto zone_ms = elapsed_ms();
			set_mod(path);

			if (!path.empty() && !load_mod_zone())
			{
				// a mod without mod.ff is allowed (scripts only); a broken one is reported and the
				// next map load fails the normal way
				if (fastfiles::exists("mod"))
				{
					console::error("[mods] the mod zone of %s could not be loaded, relaunching\n", path.data());
					relaunch(path);
					return;
				}
			}

			const auto load_ms = elapsed_ms() - zone_ms;

			gamemodes::invalidate();

			// DB_LoadXAssets queues the zone load (even DB_LOAD_SYNC returned after a few ms and
			// the mod.ff loaded for another ~18 s). Wait for the database before the menu restart,
			// so the new menu and the first map start see a complete mod zone.
			const auto waiting_logged = std::make_shared<bool>(false);
			scheduler::schedule([start, path, waiting_logged]()
			{
				if (!game::Sys_IsDatabaseReady2())
				{
					if (!*waiting_logged)
					{
						console::info("[mods] waiting for the mod zone load to finish\n");
						*waiting_logged = true;
					}
					return scheduler::cond_continue;
				}

				ui_scripting::restart([start, path]()
				{
					const auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
						std::chrono::steady_clock::now() - start).count();
					console::info("[mods] switched to %s without a relaunch, main menu ready after %lld ms\n",
						path.empty() ? "no mod" : path.data(), total_ms);
				});

				return scheduler::cond_end;
			}, scheduler::pipeline::main, 250ms);

			console::info("[mods] switch to %s: zone unload %lld ms, load request %lld ms\n",
				path.empty() ? "no mod" : path.data(), zone_ms, load_ms);
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
			clear_gametype_strings();
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
			localized_strings::override("MWX_MENU_MODS_DESC", "Load a mod from the mods folder.");
			localized_strings::override("MWX_MODS_LOADED", "LOADED MOD");
			localized_strings::override("MWX_MODS_AVAILABLE", "AVAILABLE MODS");
			localized_strings::override("MWX_MODS_UNLOAD", "Unload mod");
			localized_strings::override("MWX_MODS_UNLOAD_DESC", "Return to the unmodded game.");
			localized_strings::override("MWX_MODS_NONE", "No mods found in the mods folder.");

			scheduler::once([]()
			{
				dvars::register_bool("mwx_mod_relaunch", false, game::DVAR_FLAG_SAVED,
					"Load/unload mods by relaunching the game (old M6 behaviour)");
			}, scheduler::pipeline::main);

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

				switch_mod(path);
			});

			command::add("unloadmod", []()
			{
				if (!mod_path.has_value())
				{
					console::info("No mod loaded\n");
					return;
				}

				switch_mod("");
			});

			// M6 diagnostics: unload/load only the mod zone (no gamemode/LUI rebuild), used to
			// prove the zone can be released at all. `modzone status` lists the loaded zone.
			command::add("modzone", [](const command::params& params)
			{
				const std::string action = params.size() > 1 ? params.get(1) : "status";

				if (action == "status")
				{
					auto mod_slots = 0u;
					for (auto i = 1u; i <= *game::g_zoneCount; ++i)
					{
						const auto* zone = fastfiles::get_zone_name(i);
						if (zone && std::strcmp(zone, "mod") == 0)
						{
							mod_slots++;
						}
					}

					console::info("[mods] mod path: %s\n", mod_path.value_or("<none>").data());
					console::info("[mods] zone count: %u, mod zone slots: %u, db ready: %i\n",
						*game::g_zoneCount, mod_slots, game::Sys_IsDatabaseReady2() ? 1 : 0);
					console::info("[mods] crossbow asset: exists %i, default %i\n",
						game::DB_XAssetExists(game::ASSET_TYPE_WEAPON, "iw5_exocrossbow_mp") ? 1 : 0,
						game::DB_IsXAssetDefault(game::ASSET_TYPE_WEAPON, "iw5_exocrossbow_mp") ? 1 : 0);
					for (const auto& gametype : gametypes)
					{
						console::info("[mods] gametype: %s\n", gametype.ref.data());
					}
					return;
				}

				if (action == "unload")
				{
					if (!can_change_mod())
					{
						return;
					}
					console::info("[mods] mod zone unload: %s\n", unload_mod_zone() ? "ok" : "failed");
					return;
				}

				if (action == "list")
				{
					for (auto i = 1u; i <= *game::g_zoneCount; ++i)
					{
						console::info("[mods] zone %u: %s\n", i, fastfiles::get_zone_name(i));
					}
					return;
				}

				if (action == "load")
				{
					if (!can_change_mod())
					{
						return;
					}
					console::info("[mods] mod zone load: %s\n", load_mod_zone() ? "ok" : "failed");
					return;
				}

				console::info("Usage: modzone [status|unload|load]\n");
			});
		}
	};
}

REGISTER_COMPONENT(mods::component)

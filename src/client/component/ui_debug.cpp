#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"

#include "game/ui_scripting/types.hpp"

#include "ui_debug.hpp"
#include "ui_scripting.hpp"

#include <utils/string.hpp>

// MWX: thin C++ side of the LUI debug helpers. The logic lives in
// data/mwx/ui_scripts/mwx_debug/__init__.lua so it can use the game's LUI API directly.

namespace ui_debug
{
	namespace
	{
		std::string lua_quote(const std::string& value)
		{
			std::string result = "\"";
			for (const auto c : value)
			{
				switch (c)
				{
				case '\\': result += "\\\\"; break;
				case '"': result += "\\\""; break;
				case '\n': result += "\\n"; break;
				case '\r': result += "\\r"; break;
				case '\t': result += "\\t"; break;
				default: result.push_back(c); break;
				}
			}
			result += '"';
			return result;
		}

		// Menu texts can contain bytes that are not valid UTF-8 (player names, .csv strings).
		// nlohmann::json refuses those, so replace every invalid byte with '?'.
		std::string sanitize_utf8(const std::string& input)
		{
			std::string output;
			output.reserve(input.size());

			auto i = 0u;
			while (i < input.size())
			{
				const auto c = static_cast<unsigned char>(input[i]);
				auto length = 1u;

				if (c >= 0x80)
				{
					if ((c & 0xE0) == 0xC0) length = 2;
					else if ((c & 0xF0) == 0xE0) length = 3;
					else if ((c & 0xF8) == 0xF0) length = 4;
					else length = 0;
				}

				auto valid = length != 0 && i + length <= input.size();
				for (auto k = 1u; valid && k < length; ++k)
				{
					if ((static_cast<unsigned char>(input[i + k]) & 0xC0) != 0x80)
					{
						valid = false;
					}
				}

				if (valid)
				{
					output.append(input, i, length);
					i += length;
				}
				else
				{
					output.push_back('?');
					++i;
				}
			}

			return output;
		}

		nlohmann::json parse_json(const std::string& text)
		{
			auto result = nlohmann::json::parse(sanitize_utf8(text), nullptr, false);
			if (result.is_discarded())
			{
				return nlohmann::json{{"text", sanitize_utf8(text)}};
			}
			return result;
		}

		nlohmann::json call(const std::string& function, const std::string& arguments = {})
		{
			std::vector<std::string> results;
			std::string error;

			const auto code = "return mwx_debug." + function + "(" + arguments + ")";
			if (!ui_scripting::eval(code, &results, &error))
			{
				return nlohmann::json{{"error", error}};
			}

			if (results.empty() || results[0].empty() || results[0] == "nil")
			{
				return nlohmann::json::object();
			}

			return parse_json(results[0]);
		}
	}

	nlohmann::json snapshot()
	{
		return call("snapshot");
	}

	nlohmann::json click(const nlohmann::json& params)
	{
		// mwx_debug.click(element_id, text, index) - every argument is positional, so
		// absent ones have to be passed as a real `nil` placeholder.
		const auto string_arg = [](const nlohmann::json& value) -> std::string
		{
			if (value.is_string())
			{
				return lua_quote(value.get<std::string>());
			}
			return "nil";
		};

		const auto id = string_arg(params.contains("id") ? params["id"] : nlohmann::json());
		const auto text = string_arg(params.contains("text") ? params["text"] : nlohmann::json());

		std::string index = "nil";
		if (params.contains("index") && params["index"].is_number_integer())
		{
			index = std::to_string(params["index"].get<int>());
		}

		return call("click", id + ", " + text + ", " + index);
	}

	nlohmann::json back()
	{
		return call("back");
	}

	nlohmann::json open(const nlohmann::json& params)
	{
		const auto name = params.value("name", "");
		if (name.empty())
		{
			return nlohmann::json{{"error", "name is required"}};
		}

		return call("open", lua_quote(name));
	}

	nlohmann::json lua_eval(const nlohmann::json& params)
	{
		const auto code = params.value("code", "");
		if (code.empty())
		{
			return nlohmann::json{{"error", "code is required"}};
		}

		// The LUI state can exist while the frontend scripts or a zone are being (re)loaded;
		// running a chunk there crashes (0x1400BCB13). Return "busy" and let the caller retry.
		if (ui_scripting::is_loading())
		{
			return nlohmann::json{{"ok", false}, {"error", "the game is busy loading the UI, try again"}};
		}

		std::vector<std::string> results;
		std::string error;

		// run the chunk, then serialise its first result with the Lua helper
		const auto chunk =
			"local f, e = loadstring(" + lua_quote(code) + ", 'mwx_eval')\n"
			"if not f then return nil, e end\n"
			"local ok, r = pcall(f)\n"
			"if not ok then return nil, r end\n"
			"if type(r) == 'nil' then return 'null', nil end\n"
			"if mwx_debug == nil then return tostring(r), nil end\n"
			"local ok2, j = pcall(mwx_debug.to_json, r)\n"
			"if not ok2 then return nil, j end\n"
			"return j, nil";

		if (!ui_scripting::eval(chunk, &results, &error))
		{
			return nlohmann::json{{"ok", false}, {"error", error}};
		}

		nlohmann::json value{};
		if (!results.empty() && results[0] != "nil")
		{
			value = parse_json(results[0]);
		}

		if (results.size() > 1 && results[1] != "nil")
		{
			return nlohmann::json{{"ok", false}, {"error", results[1]}};
		}

		return nlohmann::json{{"ok", true}, {"result", value}};
	}

	bool is_menu_open(const std::string& name)
	{
		const auto value = call("menu_open", lua_quote(name));
		if (value.is_boolean())
		{
			return value.get<bool>();
		}

		if (value.contains("result"))
		{
			return value["result"].is_boolean() && value["result"].get<bool>();
		}

		return false;
	}

	nlohmann::json menu()
	{
		return call("menu");
	}

	nlohmann::json has_element(const std::string& id)
	{
		return call("has_element", lua_quote(id));
	}

	nlohmann::json actions()
	{
		return call("actions");
	}
}

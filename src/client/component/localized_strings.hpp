#pragma once

namespace localized_strings
{
	void override(const std::string& key, const std::string& value);

	// MWX (M6): drop an override again, so the next load of a mod does not keep the old mod's
	// gametype names/objectives.
	void remove(const std::string& key);
}
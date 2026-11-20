#pragma once

namespace repack
{
	// `mwx.exe -repack <all|zone[,zone...]>`: rewrites HorizonMW's zlib zones (one big zlib
	// stream, inflated on one thread) as LZ4 block zones like the retail ones. Originals are
	// moved to hmw-mod\zone_backup_zlib\ first and verified before anything is replaced.
	// `mwx.exe -repack-restore <all|zone[,zone...]>` puts the originals back.
	int run(const std::string& what, bool restore);
}

#include <std_include.hpp>

#include "repack.hpp"

#include <utils/io.hpp>
#include <utils/string.hpp>

#include <zlib.h>

// Zone container (x64 zone tools / retail H1, version 0x42):
//   0x00 magic "S1ffu100" (unsigned) | "S1ff0100" (retail, signed)
//   0x08 u32 version 0x42
//   0x0c u8 compress, u8 compressType (1 = zlib, 4 = LZ4), u8 pointer size, u8 long size
//   0x10 u32 x2 file time, 0x18 u32 image count, 0x1c image count x 24-byte stream table
//   then u64 base file length (= .ff size), u64 total length (+ streamed images)
//   zlib: one zlib stream follows
//   LZ4:  u64 image size, u32 flags (00 00 01 04), blocks { u32 packed, u32 size, data } aligned 4,
//         64 KiB per block (retail adds an S1ffs100 auth header with hashes; we write unsigned)

namespace repack
{
	namespace
	{
		constexpr std::uint32_t zone_version = 0x42;
		constexpr std::size_t block_size = 0x10000;
		constexpr auto backup_dir = "hmw-mod/zone_backup_zlib";

		std::ofstream log_file;

		void log(const std::string& line)
		{
			printf("%s\n", line.data());
			fflush(stdout);
			if (log_file.is_open())
			{
				log_file << line << "\n";
				log_file.flush();
			}
		}

		template <typename T>
		T read_at(const std::string& data, const std::size_t offset)
		{
			T value{};
			std::memcpy(&value, data.data() + offset, sizeof(T));
			return value;
		}

		template <typename T>
		void append(std::string& out, const T value)
		{
			out.append(reinterpret_cast<const char*>(&value), sizeof(T));
		}

		// ---- LZ4 block format (greedy compressor + decompressor for verification) ----

		std::uint32_t read32(const std::uint8_t* p)
		{
			std::uint32_t v;
			std::memcpy(&v, p, 4);
			return v;
		}

		std::size_t lz4_bound(const std::size_t n)
		{
			return n + n / 255 + 16;
		}

		void write_length(std::uint8_t*& op, std::size_t length)
		{
			while (length >= 255)
			{
				*op++ = 255;
				length -= 255;
			}
			*op++ = static_cast<std::uint8_t>(length);
		}

		std::size_t lz4_compress(const std::uint8_t* src, const std::size_t n, std::uint8_t* dst)
		{
			constexpr std::size_t min_match = 4;
			constexpr std::size_t last_literals = 5;
			constexpr std::size_t mf_limit = 12;
			constexpr int hash_bits = 13;

			std::int32_t table[1 << hash_bits];
			std::fill(std::begin(table), std::end(table), -1);

			auto* op = dst;
			const auto* anchor = src;
			const auto* ip = src;
			const auto* const iend = src + n;

			if (n > mf_limit)
			{
				const auto* const match_start_limit = iend - mf_limit;
				const auto* const match_end_limit = iend - last_literals;

				while (ip < match_start_limit)
				{
					const auto sequence = read32(ip);
					const auto h = (sequence * 2654435761u) >> (32 - hash_bits);
					const auto ref = table[h];
					const auto pos = static_cast<std::int32_t>(ip - src);
					table[h] = pos;

					if (ref < 0 || pos - ref > 65535 || read32(src + ref) != sequence)
					{
						++ip;
						continue;
					}

					const auto* match = src + ref;
					while (ip > anchor && match > src && ip[-1] == match[-1])
					{
						--ip;
						--match;
					}

					const auto* p = ip + min_match;
					const auto* m = match + min_match;
					while (p < match_end_limit && *p == *m)
					{
						++p;
						++m;
					}

					const auto literal_length = static_cast<std::size_t>(ip - anchor);
					const auto match_length = static_cast<std::size_t>(p - ip) - min_match;
					const auto offset = static_cast<std::uint16_t>(ip - match);

					auto* token = op++;
					*token = static_cast<std::uint8_t>((literal_length >= 15 ? 15 : literal_length) << 4);
					if (literal_length >= 15)
					{
						write_length(op, literal_length - 15);
					}
					std::memcpy(op, anchor, literal_length);
					op += literal_length;

					*op++ = static_cast<std::uint8_t>(offset & 0xFF);
					*op++ = static_cast<std::uint8_t>(offset >> 8);

					*token |= static_cast<std::uint8_t>(match_length >= 15 ? 15 : match_length);
					if (match_length >= 15)
					{
						write_length(op, match_length - 15);
					}

					ip = p;
					anchor = ip;
				}
			}

			const auto literal_length = static_cast<std::size_t>(iend - anchor);
			auto* token = op++;
			*token = static_cast<std::uint8_t>((literal_length >= 15 ? 15 : literal_length) << 4);
			if (literal_length >= 15)
			{
				write_length(op, literal_length - 15);
			}
			std::memcpy(op, anchor, literal_length);
			op += literal_length;

			return static_cast<std::size_t>(op - dst);
		}

		bool lz4_decompress(const std::uint8_t* src, const std::size_t packed, std::uint8_t* dst, const std::size_t size)
		{
			const auto* ip = src;
			const auto* const iend = src + packed;
			auto* op = dst;
			auto* const oend = dst + size;

			while (ip < iend)
			{
				const auto token = *ip++;
				std::size_t literal_length = token >> 4;
				if (literal_length == 15)
				{
					std::uint8_t s;
					do
					{
						if (ip >= iend) return false;
						s = *ip++;
						literal_length += s;
					} while (s == 255);
				}

				if (literal_length > static_cast<std::size_t>(iend - ip) || literal_length > static_cast<std::size_t>(oend - op)) return false;
				std::memcpy(op, ip, literal_length);
				ip += literal_length;
				op += literal_length;

				if (ip >= iend)
				{
					break; // last sequence
				}

				if (iend - ip < 2) return false;
				const std::size_t offset = ip[0] | (ip[1] << 8);
				ip += 2;
				if (offset == 0 || offset > static_cast<std::size_t>(op - dst)) return false;

				std::size_t match_length = token & 15;
				if (match_length == 15)
				{
					std::uint8_t s;
					do
					{
						if (ip >= iend) return false;
						s = *ip++;
						match_length += s;
					} while (s == 255);
				}
				match_length += 4;

				if (match_length > static_cast<std::size_t>(oend - op)) return false;
				const auto* match = op - offset;
				for (std::size_t i = 0; i < match_length; ++i)
				{
					op[i] = match[i];
				}
				op += match_length;
			}

			return op == oend;
		}

		// ---- zone handling ----

		struct zone_header
		{
			bool valid = false;
			bool is_zlib = false;
			std::size_t data_offset = 0;   // first byte after the two lengths
			std::size_t lengths_offset = 0;
		};

		zone_header parse_header(const std::string& file)
		{
			zone_header header{};
			if (file.size() < 0x1c || read_at<std::uint32_t>(file, 8) != zone_version)
			{
				return header;
			}

			const auto magic = file.substr(0, 8);
			if (magic != "S1ffu100")
			{
				return header; // retail (signed) zones are LZ4 already
			}

			const auto image_count = read_at<std::uint32_t>(file, 0x18);
			header.lengths_offset = 0x1c + static_cast<std::size_t>(image_count) * 24;
			header.data_offset = header.lengths_offset + 16;
			if (header.data_offset >= file.size())
			{
				return header;
			}

			header.valid = true;
			header.is_zlib = static_cast<std::uint8_t>(file[13]) == 1;
			return header;
		}

		bool inflate_zlib(const std::string& file, const std::size_t offset, std::string& out)
		{
			z_stream stream{};
			if (inflateInit(&stream) != Z_OK)
			{
				return false;
			}

			const auto _ = gsl::finally([&]() { inflateEnd(&stream); });

			out.clear();
			out.reserve((file.size() - offset) * 4);

			stream.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(file.data() + offset));
			stream.avail_in = static_cast<uInt>(file.size() - offset);

			std::vector<char> buffer(16 * 1024 * 1024);
			int result{};
			do
			{
				stream.next_out = reinterpret_cast<Bytef*>(buffer.data());
				stream.avail_out = static_cast<uInt>(buffer.size());
				result = inflate(&stream, Z_NO_FLUSH);
				if (result != Z_OK && result != Z_STREAM_END)
				{
					return false;
				}
				out.append(buffer.data(), buffer.size() - stream.avail_out);
			} while (result != Z_STREAM_END);

			return true;
		}

		// compresses `image` into 64 KiB LZ4 blocks on all cores
		std::string build_lz4_data(const std::string& image)
		{
			const auto block_count = (image.size() + block_size - 1) / block_size;
			std::vector<std::string> blocks(block_count);
			std::atomic<std::size_t> next{0};

			const auto worker = [&]()
			{
				std::vector<std::uint8_t> buffer(lz4_bound(block_size));
				while (true)
				{
					const auto i = next++;
					if (i >= block_count)
					{
						return;
					}

					const auto* src = reinterpret_cast<const std::uint8_t*>(image.data()) + i * block_size;
					const auto size = std::min(block_size, image.size() - i * block_size);
					const auto packed = lz4_compress(src, size, buffer.data());

					auto& block = blocks[i];
					append<std::uint32_t>(block, static_cast<std::uint32_t>(packed));
					append<std::uint32_t>(block, static_cast<std::uint32_t>(size));
					block.append(reinterpret_cast<const char*>(buffer.data()), packed);
					while (block.size() % 4)
					{
						block.push_back(0);
					}
				}
			};

			std::vector<std::thread> threads;
			const auto count = std::max(1u, std::thread::hardware_concurrency());
			for (auto i = 0u; i < count; ++i)
			{
				threads.emplace_back(worker);
			}
			for (auto& t : threads)
			{
				t.join();
			}

			std::string data;
			std::size_t total = 12;
			for (const auto& b : blocks) total += b.size();
			data.reserve(total);

			append<std::uint64_t>(data, image.size());
			data.append("\x00\x00\x01\x04", 4);
			for (const auto& b : blocks)
			{
				data.append(b);
			}

			return data;
		}

		bool verify_lz4_data(const std::string& data, const std::string& image)
		{
			if (data.size() < 12 || read_at<std::uint64_t>(data, 0) != image.size())
			{
				return false;
			}

			std::vector<std::uint8_t> out(block_size);
			std::size_t pos = 12;
			std::size_t done = 0;
			while (done < image.size())
			{
				if (pos + 8 > data.size()) return false;
				const auto packed = read_at<std::uint32_t>(data, pos);
				const auto size = read_at<std::uint32_t>(data, pos + 4);
				if (size > block_size || pos + 8 + packed > data.size()) return false;

				if (!lz4_decompress(reinterpret_cast<const std::uint8_t*>(data.data() + pos + 8), packed, out.data(), size)) return false;
				if (std::memcmp(out.data(), image.data() + done, size) != 0) return false;

				done += size;
				pos = (pos + 8 + packed + 3) & ~static_cast<std::size_t>(3);
			}

			return true;
		}

		std::vector<std::filesystem::path> find_zones()
		{
			std::vector<std::filesystem::path> zones;
			std::error_code ec;

			for (const auto& entry : std::filesystem::directory_iterator("hmw-mod/zone", ec))
			{
				if (entry.is_regular_file() && entry.path().extension() == ".ff")
				{
					zones.emplace_back(entry.path());
				}
			}

			for (const auto& entry : std::filesystem::recursive_directory_iterator("hmw-usermaps", ec))
			{
				if (entry.is_regular_file() && entry.path().extension() == ".ff")
				{
					zones.emplace_back(entry.path());
				}
			}

			return zones;
		}

		bool selected(const std::filesystem::path& path, const std::vector<std::string>& names)
		{
			if (names.empty())
			{
				return true;
			}

			const auto stem = utils::string::to_lower(path.stem().string());
			return std::ranges::any_of(names, [&](const std::string& name) { return name == stem; });
		}

		std::filesystem::path backup_path_for(const std::filesystem::path& zone)
		{
			return std::filesystem::path(backup_dir) / zone.relative_path();
		}

		bool repack_zone(const std::filesystem::path& path)
		{
			const auto name = path.generic_string();
			const auto start = std::chrono::steady_clock::now();

			std::string file;
			if (!utils::io::read_file(path.string(), &file))
			{
				log("  " + name + ": can't read");
				return false;
			}

			const auto header = parse_header(file);
			if (!header.valid || !header.is_zlib)
			{
				log("  " + name + ": not a zlib tools zone, skipped");
				return true;
			}

			const auto backup = backup_path_for(path);
			if (std::filesystem::exists(backup))
			{
				log("  " + name + ": a backup already exists (" + backup.generic_string() + "), skipped");
				return false;
			}

			std::string image;
			if (!inflate_zlib(file, header.data_offset, image))
			{
				log("  " + name + ": zlib data is broken, skipped");
				return false;
			}

			const auto data = build_lz4_data(image);
			if (!verify_lz4_data(data, image))
			{
				log("  " + name + ": verification of the LZ4 data failed, skipped");
				return false;
			}

			// header: same, with compressType 4 and the new file lengths
			std::string out = file.substr(0, header.data_offset);
			out[13] = 4;
			const auto old_base = read_at<std::uint64_t>(file, header.lengths_offset);
			const auto old_total = read_at<std::uint64_t>(file, header.lengths_offset + 8);
			const std::uint64_t new_base = out.size() + data.size();
			const std::uint64_t new_total = new_base + (old_total >= old_base ? old_total - old_base : 0);
			std::memcpy(out.data() + header.lengths_offset, &new_base, 8);
			std::memcpy(out.data() + header.lengths_offset + 8, &new_total, 8);
			out.append(data);

			const auto temp = path.string() + ".mwxtmp";
			if (!utils::io::write_file(temp, out, false))
			{
				log("  " + name + ": can't write " + temp);
				return false;
			}

			std::error_code ec;
			std::filesystem::create_directories(backup.parent_path(), ec);
			std::filesystem::rename(path, backup, ec);
			if (ec)
			{
				log("  " + name + ": can't move the original to the backup folder (" + ec.message() + "), nothing changed");
				std::filesystem::remove(temp, ec);
				return false;
			}

			std::filesystem::rename(temp, path, ec);
			if (ec)
			{
				log("  " + name + ": can't put the new file in place (" + ec.message() + "), restoring the original");
				std::filesystem::rename(backup, path, ec);
				return false;
			}

			const auto took = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
			log(utils::string::va("  %s: %.0f MB zlib -> %.0f MB LZ4 (image %.0f MB) in %.1f s, original in %s",
				name.data(), file.size() / 1e6, out.size() / 1e6, image.size() / 1e6, took, backup.generic_string().data()));
			return true;
		}

		bool restore_zone(const std::filesystem::path& path)
		{
			const auto backup = backup_path_for(path);
			if (!std::filesystem::exists(backup))
			{
				return true;
			}

			std::error_code ec;
			const auto repacked = path.string() + ".lz4";
			if (std::filesystem::exists(path))
			{
				std::filesystem::rename(path, repacked, ec);
				if (ec)
				{
					log("  " + path.generic_string() + ": can't move the repacked file away (" + ec.message() + ")");
					return false;
				}
			}

			std::filesystem::rename(backup, path, ec);
			if (ec)
			{
				log("  " + path.generic_string() + ": can't restore (" + ec.message() + ")");
				std::filesystem::rename(repacked, path, ec);
				return false;
			}

			std::filesystem::remove(repacked, ec);
			log("  " + path.generic_string() + ": original restored");
			return true;
		}
	}

	int run(const std::string& what, const bool restore)
	{
		// work relative to the game folder (where mwx.exe is)
		wchar_t exe[MAX_PATH]{};
		GetModuleFileNameW(nullptr, exe, MAX_PATH);
		std::filesystem::current_path(std::filesystem::path(exe).parent_path());

		std::filesystem::create_directories("mwx-logs");
		log_file.open("mwx-logs/repack.log", std::ios::app);

		// MWX scopes: "all" = hmw-mod/zone only (the custom HMW zones), "usermaps" = hmw-usermaps only,
		// "everything" = both. -repack-restore all also restores whatever is in the backup folder.
		const auto what_lower = utils::string::to_lower(what);
		const auto only_usermaps = what_lower == "usermaps";
		const auto with_usermaps = only_usermaps || what_lower == "everything" || (restore && (what_lower.empty() || what_lower == "all"));
		const auto is_usermap = [](const std::filesystem::path& zone)
		{
			return zone.generic_string().starts_with("hmw-usermaps/");
		};

		std::vector<std::string> names;
		if (!what.empty() && what_lower != "all" && !only_usermaps && what_lower != "everything")
		{
			for (auto& name : utils::string::split(utils::string::to_lower(what), ','))
			{
				if (!name.empty()) names.emplace_back(name);
			}
		}

		log(utils::string::va("==== MWX %s (%s) ====", restore ? "repack-restore" : "repack", what.empty() ? "all" : what.data()));

		auto ok = true;
		std::vector<std::filesystem::path> zones = find_zones();

		if (restore)
		{
			// zones whose original is only in the backup folder count too
			std::error_code ec;
			for (const auto& entry : std::filesystem::recursive_directory_iterator(backup_dir, ec))
			{
				if (entry.is_regular_file() && entry.path().extension() == ".ff")
				{
					const auto zone = std::filesystem::relative(entry.path(), backup_dir);
					if (std::ranges::find(zones, zone) == zones.end())
					{
						zones.emplace_back(zone);
					}
				}
			}
		}

		for (const auto& zone : zones)
		{
			if (!selected(zone, names))
			{
				continue;
			}

			if (names.empty() && (is_usermap(zone) ? !with_usermaps : only_usermaps))
			{
				continue;
			}

			try
			{
				ok &= restore ? restore_zone(zone) : repack_zone(zone);
			}
			catch (const std::exception& e)
			{
				log("  " + zone.generic_string() + ": " + e.what());
				ok = false;
			}
		}

		log(ok ? "done" : "done, with errors (see above)");
		return ok ? 0 : 1;
	}
}

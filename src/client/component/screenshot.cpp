#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "command.hpp"
#include "scheduler.hpp"
#include "screenshot.hpp"

#include "game/game.hpp"

#include <utils/cryptography.hpp>
#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/string.hpp>

#include <dxgi1_2.h>

#include <condition_variable>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>

// MWX: native screenshot of the rendered frame.
//
// The frame is copied out of the D3D11 back buffer when the game calls Present, so it works
// without focus and while another window covers the game. The swapchain is not in the game's
// symbol list, so a small hidden window + swapchain is created once to get the interface
// vtable; the Present entry of that vtable is hooked (the game's swapchain uses the same one).

namespace screenshot
{
	namespace
	{
		struct request_t
		{
			bool pending = false;
			double scale = 1.0;
			bool has_region = false;
			int x = 0;
			int y = 0;
			int width = 0;
			int height = 0;
			std::string path;
		};

		std::mutex mutex;
		std::condition_variable cv;
		request_t request;
		nlohmann::json result;
		bool result_ready = false;

		utils::hook::detour present_hook;
		utils::hook::detour present1_hook;

		using present_t = HRESULT(WINAPI*)(IDXGISwapChain*, UINT, UINT);
		using present1_t = HRESULT(WINAPI*)(IDXGISwapChain1*, UINT, UINT, const DXGI_PRESENT_PARAMETERS*);

		std::string timestamp()
		{
			const auto now = std::chrono::system_clock::now();
			const auto time = std::chrono::system_clock::to_time_t(now);
			const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000;

			std::tm local{};
			localtime_s(&local, &time);

			return utils::string::va("%04d-%02d-%02d_%02d-%02d-%02d-%03d", local.tm_year + 1900, local.tm_mon + 1,
				local.tm_mday, local.tm_hour, local.tm_min, local.tm_sec, static_cast<int>(ms));
		}

		// scaled/cropped copy of the back buffer, as RGBA. `bgra` says which channel order the
		// source really has: the formats the capture accepts are R8G8B8A8 and B8G8R8A8, and
		// swapping a real RGBA back buffer turns red into blue (the extinguisher/stocks bug).
		std::vector<std::uint8_t> transform(const std::uint8_t* pixels, const int stride, int width, int height,
			const request_t& req, const bool bgra, int* out_width, int* out_height)
		{
			int left = 0;
			int top = 0;
			int right = width;
			int bottom = height;

			if (req.has_region)
			{
				left = std::clamp(req.x, 0, width - 1);
				top = std::clamp(req.y, 0, height - 1);
				right = std::clamp(req.x + req.width, left + 1, width);
				bottom = std::clamp(req.y + req.height, top + 1, height);
			}

			const auto crop_width = right - left;
			const auto crop_height = bottom - top;

			const auto scale = req.scale > 0.0 ? req.scale : 1.0;
			const auto out_w = std::max(1, static_cast<int>(crop_width * scale));
			const auto out_h = std::max(1, static_cast<int>(crop_height * scale));

			std::vector<std::uint8_t> rgba(static_cast<size_t>(out_w) * out_h * 4);

			for (auto y = 0; y < out_h; ++y)
			{
				const auto src_y = top + static_cast<int>(y / scale);
				const auto* src_row = pixels + static_cast<size_t>(src_y) * stride;

				for (auto x = 0; x < out_w; ++x)
				{
					const auto src_x = left + static_cast<int>(x / scale);
					const auto* src = src_row + static_cast<size_t>(src_x) * 4;
					auto* dst = &rgba[(static_cast<size_t>(y) * out_w + x) * 4];

					dst[0] = bgra ? src[2] : src[0];
					dst[1] = src[1];
					dst[2] = bgra ? src[0] : src[2];
					dst[3] = 255;
				}
			}

			*out_width = out_w;
			*out_height = out_h;
			return rgba;
		}

		bool capture_swapchain(IDXGISwapChain* swapchain)
		{
			if (swapchain == nullptr || *game::d3d11_device == nullptr)
			{
				return false;
			}

			ID3D11Texture2D* backbuffer = nullptr;
			if (FAILED(swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&backbuffer))) || !backbuffer)
			{
				return false;
			}

			const auto release_buffer = gsl::finally([&] { backbuffer->Release(); });

			D3D11_TEXTURE2D_DESC desc{};
			backbuffer->GetDesc(&desc);

			// HDR / 10 bit formats: not supported, report it instead of writing a broken PNG
			if (desc.Format != DXGI_FORMAT_R8G8B8A8_UNORM && desc.Format != DXGI_FORMAT_R8G8B8A8_UNORM_SRGB &&
				desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM && desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM_SRGB &&
				desc.Format != DXGI_FORMAT_B8G8R8X8_UNORM)
			{
				std::lock_guard _(mutex);
				result = nlohmann::json{{"error", utils::string::va("unsupported back buffer format %d", desc.Format)}};
				result_ready = true;
				cv.notify_all();
				return true;
			}

			D3D11_TEXTURE2D_DESC staging_desc = desc;
			staging_desc.Usage = D3D11_USAGE_STAGING;
			staging_desc.BindFlags = 0;
			staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
			staging_desc.MiscFlags = 0;
			staging_desc.ArraySize = 1;
			staging_desc.MipLevels = 1;
			staging_desc.SampleDesc.Count = 1;
			staging_desc.SampleDesc.Quality = 0;

			ID3D11Texture2D* staging = nullptr;
			auto* device = *game::d3d11_device;
			if (FAILED(device->CreateTexture2D(&staging_desc, nullptr, &staging)) || !staging)
			{
				return false;
			}

			const auto release_staging = gsl::finally([&] { staging->Release(); });

			ID3D11DeviceContext* context = nullptr;
			device->GetImmediateContext(&context);
			if (!context)
			{
				return false;
			}

			const auto release_context = gsl::finally([&] { context->Release(); });

			context->CopyResource(staging, backbuffer);

			D3D11_MAPPED_SUBRESOURCE mapped{};
			if (FAILED(context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped)))
			{
				return false;
			}

			const auto unmap = gsl::finally([&] { context->Unmap(staging, 0); });

			request_t req{};
			{
				std::lock_guard _(mutex);
				req = request;
			}

			int width = 0;
			int height = 0;
			const auto bgra = desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM ||
				desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB ||
				desc.Format == DXGI_FORMAT_B8G8R8X8_UNORM;
			const auto rgba = transform(static_cast<const std::uint8_t*>(mapped.pData),
				static_cast<int>(mapped.RowPitch), static_cast<int>(desc.Width), static_cast<int>(desc.Height),
				req, bgra, &width, &height);

			int png_size = 0;
			auto* png = stbi_write_png_to_mem(rgba.data(), width * 4, width, height, 4, &png_size);
			if (!png)
			{
				return false;
			}

			const auto free_png = gsl::finally([&] { STBIW_FREE(png); });

			auto path = req.path;
			if (path.empty())
			{
				utils::io::create_directory("mwx-screenshots");
				path = "mwx-screenshots/" + timestamp() + ".png";
			}

			const std::string data(reinterpret_cast<const char*>(png), static_cast<size_t>(png_size));
			utils::io::write_file(path, data);

			nlohmann::json value{};
			value["path"] = path;
			value["width"] = width;
			value["height"] = height;
			value["png_base64"] = utils::cryptography::base64::encode(data);

			console::info("[screenshot] %s (%ix%i)\n", path.data(), width, height);

			{
				std::lock_guard _(mutex);
				result = std::move(value);
				result_ready = true;
			}
			cv.notify_all();
			return true;
		}

		void take_requested_frame(IDXGISwapChain* swapchain)
		{
			{
				std::lock_guard _(mutex);
				if (!request.pending)
				{
					return;
				}
				request.pending = false;
			}

			if (!capture_swapchain(swapchain))
			{
				std::lock_guard _(mutex);
				result = nlohmann::json{{"error", "could not copy the frame (device lost or no back buffer)"}};
				result_ready = true;
				cv.notify_all();
			}
		}

		HRESULT WINAPI present_stub(IDXGISwapChain* swapchain, const UINT sync_interval, const UINT flags)
		{
			take_requested_frame(swapchain);
			return present_hook.invoke<HRESULT>(swapchain, sync_interval, flags);
		}

		HRESULT WINAPI present1_stub(IDXGISwapChain1* swapchain, const UINT sync_interval, const UINT flags,
			const DXGI_PRESENT_PARAMETERS* parameters)
		{
			take_requested_frame(swapchain);
			return present1_hook.invoke<HRESULT>(swapchain, sync_interval, flags, parameters);
		}

		// True when `address` points into an executable section of a loaded module.
		bool is_executable_address(const void* address)
		{
			if (address == nullptr)
			{
				return false;
			}

			MEMORY_BASIC_INFORMATION info{};
			if (VirtualQuery(address, &info, sizeof(info)) == 0 || info.State != MEM_COMMIT)
			{
				return false;
			}

			const auto protect = info.Protect;
			return (protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
		}

		// Creates a hidden window + swapchain to get the IDXGISwapChain vtable and hooks Present.
		bool install_present_hook()
		{
			WNDCLASSEXA window_class{};
			window_class.cbSize = sizeof(window_class);
			window_class.lpfnWndProc = DefWindowProcA;
			window_class.hInstance = GetModuleHandleA(nullptr);
			window_class.lpszClassName = "mwx_screenshot_window";
			RegisterClassExA(&window_class);

			const auto window = CreateWindowExA(0, window_class.lpszClassName, "mwx", WS_POPUP, 0, 0, 2, 2,
				nullptr, nullptr, window_class.hInstance, nullptr);
			if (!window)
			{
				return false;
			}

			const auto destroy_window = gsl::finally([&]
			{
				if (window)
				{
					DestroyWindow(window);
				}
			});

			DXGI_SWAP_CHAIN_DESC desc{};
			desc.BufferCount = 1;
			desc.BufferDesc.Width = 2;
			desc.BufferDesc.Height = 2;
			desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
			desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
			desc.OutputWindow = window;
			desc.SampleDesc.Count = 1;
			desc.Windowed = TRUE;
			desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

			ID3D11Device* device = nullptr;
			ID3D11DeviceContext* context = nullptr;
			IDXGISwapChain* swapchain = nullptr;
			D3D_FEATURE_LEVEL level{};

			const auto hr = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
				D3D11_SDK_VERSION, &desc, &swapchain, &device, &level, &context);
			if (FAILED(hr) || !swapchain)
			{
				console::warn("[screenshot] no D3D11 swapchain for the Present hook (%08X)\n", static_cast<unsigned>(hr));
				return false;
			}

			const auto release_all = gsl::finally([&]
			{
				swapchain->Release();
				if (context) context->Release();
				if (device) device->Release();
			});

			auto** vtable = *reinterpret_cast<void***>(swapchain);

			// IDXGISwapChain::Present (index 8) exists in every version; Present1 (index 22) only
			// in IDXGISwapChain1 and later. Only hook it when the pointer is real - a dummy or old
			// interface can have fewer entries, and hooking the garbage behind index 22 crashed the
			// game on the first frame.
			present_hook.create(vtable[8], present_stub);

			if (auto* present1 = vtable[22]; is_executable_address(present1))
			{
				present1_hook.create(present1, present1_stub);
			}

			console::info("[screenshot] Present hook installed\n");
			return true;
		}

		void save_command()
		{
			nlohmann::json params = nlohmann::json::object();
			params["path"] = "mwx-screenshots/" + timestamp() + ".png";
			const auto answer = capture(params);
			if (answer.contains("path"))
			{
				console::info("Screenshot saved: %s\n", answer["path"].get<std::string>().data());
			}
			else
			{
				console::error("Screenshot failed: %s\n", answer.value("error", "unknown error").data());
			}
		}
	}

	nlohmann::json capture(const nlohmann::json& params)
	{
		if (!present_hook.get_place())
		{
			return nlohmann::json{{"error", "the screenshot hook is not installed (client only)"}};
		}

		{
			std::lock_guard _(mutex);
			request = {};
			request.pending = true;
			request.scale = params.value("scale", 1.0);
			request.path = params.value("path", "");

			if (params.contains("region") && params["region"].is_object())
			{
				const auto& region = params["region"];
				request.has_region = true;
				request.x = region.value("x", 0);
				request.y = region.value("y", 0);
				request.width = region.value("width", 0);
				request.height = region.value("height", 0);
			}

			result = {};
			result_ready = false;
		}

		// The next Present captures the frame (the render thread calls it even when the window is
		// not focused). Give it a moment.
		std::unique_lock lock(mutex);
		if (!cv.wait_for(lock, std::chrono::seconds(10), [] { return result_ready; }))
		{
			request.pending = false;
			return nlohmann::json{{"error", "timeout: no frame was presented within 10 s (is the game rendering?)"}};
		}

		return result;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}




			// the vtable hook needs a D3D11 device, which exists once the renderer is up
			scheduler::once([]{
				if (game::environment::is_dedi())
				{
					return;
				}
				if (!install_present_hook())
				{
					console::warn("[screenshot] frame capture is not available\n");
				}
			}, scheduler::pipeline::renderer, 5s);

			scheduler::once([]
			{
				command::add("screenshot", [] { save_command(); });

				// F12, if it is not bound to something else
				if (game::playerKeys[0].keys[VK_F12].binding == 0)
				{
					command::execute("bind F12 screenshot", false);
					console::info("[screenshot] bound to F12\n");
				}
			}, scheduler::pipeline::main);
		}

		void pre_destroy() override
		{
			present_hook.clear();
			present1_hook.clear();
			cv.notify_all();
		}
	};
}

REGISTER_COMPONENT(screenshot::component)

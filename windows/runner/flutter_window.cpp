#include "flutter_window.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr double kMiniExtent = 480;
constexpr double kMiniMinExtent = 200;
constexpr double kMiniMargin = 24;

std::optional<int> IntArgument(const flutter::EncodableMap& args,
                               const char* key) {
  const auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return std::nullopt;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return static_cast<int>(*value);
  }
  return std::nullopt;
}

SIZE MiniSize(double aspect, double extent) {
  if (aspect >= 1) {
    return {std::lround(extent), std::lround(extent / aspect)};
  }
  return {std::lround(extent * aspect), std::lround(extent)};
}

double WindowScale(HWND window) {
  return FlutterDesktopGetDpiForHWND(window) / 96.0;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "duanju/device",
          &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setFullScreen") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const bool* enabled = nullptr;
          if (args) {
            const auto found = args->find(flutter::EncodableValue("enabled"));
            if (found != args->end()) enabled = std::get_if<bool>(&found->second);
          }
          if (!enabled) {
            result->Error("bad_args", "enabled is required");
            return;
          }
          SetFullScreen(*enabled);
          result->Success();
          return;
        }
        if (call.method_name() == "setMiniWindow") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const bool* enabled = nullptr;
          const double* aspect = nullptr;
          if (args) {
            const auto found = args->find(flutter::EncodableValue("enabled"));
            if (found != args->end()) enabled = std::get_if<bool>(&found->second);
            const auto ratio = args->find(flutter::EncodableValue("aspect"));
            if (ratio != args->end()) aspect = std::get_if<double>(&ratio->second);
          }
          if (!enabled || (*enabled && (!aspect || !(*aspect > 0)))) {
            result->Error("bad_args", "enabled and aspect are required");
            return;
          }
          if (!*enabled) {
            result->Success(ExitMiniWindow());
            return;
          }
          EnterMiniWindow(*aspect, *args);
          result->Success();
          return;
        }
        if (call.method_name() != "playbackPower") {
          result->NotImplemented();
          return;
        }
        SYSTEM_POWER_STATUS power{};
        const bool known = GetSystemPowerStatus(&power) != 0;
        MEMORYSTATUSEX memory{};
        memory.dwLength = sizeof(memory);
        const bool memory_known = GlobalMemoryStatusEx(&memory) != 0;
        flutter::EncodableMap values;
        values[flutter::EncodableValue("batterySaver")] =
            flutter::EncodableValue(known && power.SystemStatusFlag == 1);
        values[flutter::EncodableValue("onBattery")] =
            flutter::EncodableValue(!known || power.ACLineStatus != 1);
        values[flutter::EncodableValue("lowMemory")] =
            flutter::EncodableValue(!memory_known || memory.ullTotalPhys < 4ULL * 1024 * 1024 * 1024);
        result->Success(flutter::EncodableValue(values));
      });
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&taskbar_))) ||
      FAILED(taskbar_->HrInit())) {
    taskbar_.Reset();
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetFullScreen(bool enabled) {
  if (enabled == fullscreen_) {
    return;
  }
  HWND window = GetHandle();
  RECT target = frame_before_fullscreen_;
  if (enabled) {
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
      return;
    }
    GetWindowRect(window, &frame_before_fullscreen_);
    target = monitor.rcMonitor;
  }
  fullscreen_ = enabled;
  SetWindowPos(window, nullptr, target.left, target.top,
               target.right - target.left, target.bottom - target.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  if (taskbar_) {
    taskbar_->MarkFullscreenWindow(window, enabled);
  }
}

void FlutterWindow::EnterMiniWindow(double aspect,
                                    const flutter::EncodableMap& args) {
  HWND window = GetHandle();
  const double scale = WindowScale(window);
  mini_aspect_ = aspect;
  if (mini_) {
    RECT frame;
    GetWindowRect(window, &frame);
    const SIZE size = MiniSize(
        aspect, std::max(frame.right - frame.left, frame.bottom - frame.top));
    SetWindowPos(window, nullptr, 0, 0, size.cx, size.cy,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    return;
  }
  fullscreen_before_mini_ = fullscreen_;
  if (fullscreen_) {
    SetFullScreen(false);
  }
  placement_before_mini_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(window, &placement_before_mini_);
  if (IsZoomed(window)) {
    ShowWindow(window, SW_RESTORE);
  }
  const auto left = IntArgument(args, "left");
  const auto top = IntArgument(args, "top");
  const auto extent = IntArgument(args, "extent");
  RECT target{};
  bool placed = false;
  if (left && top && extent && *extent >= kMiniMinExtent * scale) {
    const SIZE size = MiniSize(aspect, *extent);
    target = {*left, *top, *left + size.cx, *top + size.cy};
    placed = MonitorFromRect(&target, MONITOR_DEFAULTTONULL) != nullptr;
  }
  if (!placed) {
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                   &monitor);
    const SIZE size = MiniSize(aspect, kMiniExtent * scale);
    const LONG margin = std::lround(kMiniMargin * scale);
    target.right = monitor.rcWork.right - margin;
    target.bottom = monitor.rcWork.bottom - margin;
    target.left = target.right - size.cx;
    target.top = target.bottom - size.cy;
  }
  style_before_mini_ = GetWindowLong(window, GWL_STYLE);
  SetWindowLong(window, GWL_STYLE, style_before_mini_ & ~WS_CAPTION);
  mini_ = true;
  SetWindowPos(window, HWND_TOPMOST, target.left, target.top,
               target.right - target.left, target.bottom - target.top,
               SWP_FRAMECHANGED);
}

flutter::EncodableValue FlutterWindow::ExitMiniWindow() {
  if (!mini_) {
    return flutter::EncodableValue();
  }
  HWND window = GetHandle();
  RECT frame;
  GetWindowRect(window, &frame);
  mini_ = false;
  SetWindowLong(window, GWL_STYLE, style_before_mini_);
  SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  SetWindowPlacement(window, &placement_before_mini_);
  if (fullscreen_before_mini_) {
    SetFullScreen(true);
  }
  flutter::EncodableMap values;
  values[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(frame.left));
  values[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(frame.top));
  values[flutter::EncodableValue("extent")] = flutter::EncodableValue(
      static_cast<int32_t>(std::max(frame.right - frame.left,
                                    frame.bottom - frame.top)));
  return flutter::EncodableValue(values);
}

void FlutterWindow::KeepMiniAspect(WPARAM edge, RECT* frame) {
  double width = frame->right - frame->left;
  double height = frame->bottom - frame->top;
  if (edge == WMSZ_TOP || edge == WMSZ_BOTTOM) {
    width = height * mini_aspect_;
  } else {
    height = width / mini_aspect_;
  }
  const double minimum = kMiniMinExtent * WindowScale(GetHandle());
  const double extent = std::max(width, height);
  if (extent < minimum) {
    width *= minimum / extent;
    height *= minimum / extent;
  }
  if (edge == WMSZ_LEFT || edge == WMSZ_TOPLEFT || edge == WMSZ_BOTTOMLEFT) {
    frame->left = frame->right - std::lround(width);
  } else {
    frame->right = frame->left + std::lround(width);
  }
  if (edge == WMSZ_TOP || edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT) {
    frame->top = frame->bottom - std::lround(height);
  } else {
    frame->bottom = frame->top + std::lround(height);
  }
}

void FlutterWindow::OnDestroy() {
  device_channel_.reset();
  taskbar_.Reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_NCCALCSIZE:
      if ((fullscreen_ || mini_) && wparam) {
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      if (mini_) {
        return DefWindowProc(hwnd, message, wparam, -1);
      }
      break;
    case WM_SIZING:
      if (mini_) {
        KeepMiniAspect(wparam, reinterpret_cast<RECT*>(lparam));
        return TRUE;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

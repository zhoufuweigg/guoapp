#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <shobjidl.h>
#include <wrl/client.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetFullScreen(bool enabled);
  void EnterMiniWindow(double aspect, const flutter::EncodableMap& args);
  flutter::EncodableValue ExitMiniWindow();
  void KeepMiniAspect(WPARAM edge, RECT* frame);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> device_channel_;
  Microsoft::WRL::ComPtr<ITaskbarList2> taskbar_;
  bool fullscreen_ = false;
  RECT frame_before_fullscreen_{};
  bool mini_ = false;
  bool fullscreen_before_mini_ = false;
  double mini_aspect_ = 16.0 / 9.0;
  LONG style_before_mini_ = 0;
  WINDOWPLACEMENT placement_before_mini_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

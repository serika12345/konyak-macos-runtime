#define WIN32_LEAN_AND_MEAN

#include <stdlib.h>
#include <windows.h>
#include <wchar.h>

static const wchar_t *kClassName = L"KonyakGuiLaunchProbeWindow";
static const wchar_t *kSentinelPath = L"C:\\konyak-gui-launch-smoke-ok.txt";
static const char kSentinel[] = "KONYAK_GUI_LAUNCH_SMOKE_OK\n";

static int fail_last_error(void) {
  const DWORD error = GetLastError();
  return error == 0 ? 1 : (int)(error & 0x7fffffff);
}

static LRESULT CALLBACK window_proc(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  switch (message) {
    case WM_CLOSE:
      DestroyWindow(window);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
    default:
      return DefWindowProcW(window, message, wparam, lparam);
  }
}

static int write_sentinel(void) {
  HANDLE file = CreateFileW(
      kSentinelPath,
      GENERIC_WRITE,
      0,
      NULL,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return fail_last_error();
  }

  DWORD bytes_written = 0;
  const BOOL write_ok = WriteFile(
      file,
      kSentinel,
      (DWORD)(sizeof(kSentinel) - 1),
      &bytes_written,
      NULL);
  CloseHandle(file);
  return write_ok && bytes_written == sizeof(kSentinel) - 1 ? 0 : 1;
}

static DWORD hold_milliseconds(void) {
  wchar_t buffer[32];
  wchar_t *end = NULL;
  const DWORD length = GetEnvironmentVariableW(
      L"KONYAK_GUI_LAUNCH_PROBE_HOLD_MS",
      buffer,
      (DWORD)(sizeof(buffer) / sizeof(buffer[0])));
  if (length == 0 || length >= sizeof(buffer) / sizeof(buffer[0])) {
    return 1500;
  }

  const unsigned long parsed = wcstoul(buffer, &end, 10);
  if (end == buffer || parsed > 60000UL) {
    return 1500;
  }
  return (DWORD)parsed;
}

int WINAPI wWinMain(
    HINSTANCE instance,
    HINSTANCE previous_instance,
    PWSTR command_line,
    int show_command) {
  (void)previous_instance;
  (void)command_line;

  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);

  WNDCLASSEXW window_class = {0};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = window_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kClassName;
  if (!RegisterClassExW(&window_class)) {
    return fail_last_error();
  }

  HWND window = CreateWindowExW(
      0,
      kClassName,
      L"Konyak GUI Launch Probe",
      WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      320,
      200,
      NULL,
      NULL,
      instance,
      NULL);
  if (window == NULL) {
    return fail_last_error();
  }

  ShowWindow(window, show_command);
  UpdateWindow(window);

  const int write_status = write_sentinel();
  const DWORD deadline = GetTickCount() + hold_milliseconds();
  while (GetTickCount() < deadline) {
    MSG message;
    while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        DestroyWindow(window);
        return write_status;
      }
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(50);
  }

  DestroyWindow(window);
  return write_status;
}

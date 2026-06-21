#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <windows.h>

static const char kSuccessSentinelPath[] =
    "C:\\konyak-d3d11-device-probe-ok.txt";
static const char kSuccessMarker[] =
    "KONYAK_D3D11_DEVICE_PROBE_OK\n";

typedef HRESULT(WINAPI *D3D11CreateDeviceAndSwapChainProc)(
    IDXGIAdapter *,
    D3D_DRIVER_TYPE,
    HMODULE,
    UINT,
    const D3D_FEATURE_LEVEL *,
    UINT,
    UINT,
    const DXGI_SWAP_CHAIN_DESC *,
    IDXGISwapChain **,
    ID3D11Device **,
    D3D_FEATURE_LEVEL *,
    ID3D11DeviceContext **);

static const wchar_t *kClassName = L"KonyakBackendD3D11ProbeWindow";

static int fail_hresult(const char *operation, HRESULT result) {
  fprintf(stderr, "%s failed: 0x%08lx\n", operation, (unsigned long)result);
  return 1;
}

static int fail_last_error(const char *operation) {
  const DWORD error = GetLastError();
  fprintf(stderr, "%s failed: %lu\n", operation, (unsigned long)error);
  return 1;
}

static int write_success_sentinel(void) {
  HANDLE file = CreateFileA(
      kSuccessSentinelPath,
      GENERIC_WRITE,
      0,
      NULL,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return fail_last_error("CreateFileA(success sentinel)");
  }

  DWORD bytes_written = 0;
  const DWORD marker_size = (DWORD)(sizeof(kSuccessMarker) - 1);
  const BOOL write_ok = WriteFile(
      file,
      kSuccessMarker,
      marker_size,
      &bytes_written,
      NULL);
  CloseHandle(file);
  if (!write_ok || bytes_written != marker_size) {
    return fail_last_error("WriteFile(success sentinel)");
  }
  return 0;
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

int main(void) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);

  const HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSEXW window_class = {0};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = window_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kClassName;
  if (!RegisterClassExW(&window_class)) {
    return fail_last_error("RegisterClassExW");
  }

  HWND window = CreateWindowExW(
      0,
      kClassName,
      L"Konyak Backend D3D11 Probe",
      WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      64,
      64,
      NULL,
      NULL,
      instance,
      NULL);
  if (window == NULL) {
    return fail_last_error("CreateWindowExW");
  }

  HMODULE d3d11_module = LoadLibraryA("d3d11.dll");
  if (d3d11_module == NULL) {
    DestroyWindow(window);
    return fail_last_error("LoadLibraryA(d3d11.dll)");
  }

  union {
    FARPROC symbol;
    D3D11CreateDeviceAndSwapChainProc function;
  } create_device_and_swap_chain;
  create_device_and_swap_chain.symbol =
      GetProcAddress(d3d11_module, "D3D11CreateDeviceAndSwapChain");
  if (create_device_and_swap_chain.symbol == NULL) {
    const int status =
        fail_last_error("GetProcAddress(D3D11CreateDeviceAndSwapChain)");
    FreeLibrary(d3d11_module);
    DestroyWindow(window);
    return status;
  }

  DXGI_SWAP_CHAIN_DESC swap_chain_desc = {0};
  swap_chain_desc.BufferDesc.Width = 64;
  swap_chain_desc.BufferDesc.Height = 64;
  swap_chain_desc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  swap_chain_desc.BufferDesc.RefreshRate.Numerator = 60;
  swap_chain_desc.BufferDesc.RefreshRate.Denominator = 1;
  swap_chain_desc.SampleDesc.Count = 1;
  swap_chain_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swap_chain_desc.BufferCount = 1;
  swap_chain_desc.OutputWindow = window;
  swap_chain_desc.Windowed = TRUE;
  swap_chain_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

  const D3D_FEATURE_LEVEL requested_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };
  D3D_FEATURE_LEVEL created_level = D3D_FEATURE_LEVEL_10_0;
  IDXGISwapChain *swap_chain = NULL;
  ID3D11Device *device = NULL;
  ID3D11DeviceContext *context = NULL;

  HRESULT result = create_device_and_swap_chain.function(
      NULL,
      D3D_DRIVER_TYPE_HARDWARE,
      NULL,
      0,
      requested_levels,
      (UINT)(sizeof(requested_levels) / sizeof(requested_levels[0])),
      D3D11_SDK_VERSION,
      &swap_chain_desc,
      &swap_chain,
      &device,
      &created_level,
      &context);
  if (FAILED(result)) {
    FreeLibrary(d3d11_module);
    DestroyWindow(window);
    return fail_hresult("D3D11CreateDeviceAndSwapChain", result);
  }

  IDXGISwapChain_Present(swap_chain, 0, 0);

  printf(
      "KONYAK_D3D11_DEVICE_PROBE_OK featureLevel=0x%04x\n",
      (unsigned int)created_level);
  const int sentinel_status = write_success_sentinel();

  if (context != NULL) {
    ID3D11DeviceContext_Release(context);
  }
  if (device != NULL) {
    ID3D11Device_Release(device);
  }
  if (swap_chain != NULL) {
    IDXGISwapChain_Release(swap_chain);
  }
  FreeLibrary(d3d11_module);
  DestroyWindow(window);
  return sentinel_status;
}

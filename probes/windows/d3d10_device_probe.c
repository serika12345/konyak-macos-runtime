#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include <d3d10.h>
#include <stdio.h>
#include <windows.h>

static const char kSuccessSentinelPath[] =
    "C:\\konyak-d3d10-device-probe-ok.txt";
static const char kSuccessMarker[] =
    "KONYAK_D3D10_DEVICE_PROBE_OK\n";

typedef HRESULT(WINAPI *D3D10CreateDeviceProc)(
    IDXGIAdapter *,
    D3D10_DRIVER_TYPE,
    HMODULE,
    UINT,
    UINT,
    ID3D10Device **);

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

int main(void) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);

  HMODULE d3d10_module = LoadLibraryA("d3d10.dll");
  if (d3d10_module == NULL) {
    return fail_last_error("LoadLibraryA(d3d10.dll)");
  }

  union {
    FARPROC symbol;
    D3D10CreateDeviceProc function;
  } create_device;
  create_device.symbol = GetProcAddress(d3d10_module, "D3D10CreateDevice");
  if (create_device.symbol == NULL) {
    const int status = fail_last_error("GetProcAddress(D3D10CreateDevice)");
    FreeLibrary(d3d10_module);
    return status;
  }

  ID3D10Device *device = NULL;

  HRESULT result = create_device.function(
      NULL,
      D3D10_DRIVER_TYPE_HARDWARE,
      NULL,
      0,
      D3D10_SDK_VERSION,
      &device);
  if (FAILED(result)) {
    FreeLibrary(d3d10_module);
    return fail_hresult("D3D10CreateDevice", result);
  }

  printf(
      "KONYAK_D3D10_DEVICE_PROBE_OK sdkVersion=0x%04x\n",
      (unsigned int)D3D10_SDK_VERSION);
  const int sentinel_status = write_success_sentinel();

  if (device != NULL) {
    ID3D10Device_Release(device);
  }
  FreeLibrary(d3d10_module);
  return sentinel_status;
}

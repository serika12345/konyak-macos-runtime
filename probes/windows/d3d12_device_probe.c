#define COBJMACROS
#define INITGUID
#define WIN32_LEAN_AND_MEAN

#include <d3d12.h>
#include <stdio.h>
#include <windows.h>

static const char kSuccessSentinelPath[] =
    "C:\\konyak-d3d12-device-probe-ok.txt";
static const char kStatusPath[] =
    "C:\\konyak-d3d12-device-probe-status.txt";
static const char kSuccessMarker[] =
    "KONYAK_D3D12_DEVICE_PROBE_OK\n";

typedef HRESULT(WINAPI *D3D12CreateDeviceProc)(
    IUnknown *,
    D3D_FEATURE_LEVEL,
    REFIID,
    void **);

static void write_status(const char *message) {
  HANDLE file = CreateFileA(
      kStatusPath,
      GENERIC_WRITE,
      0,
      NULL,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  DWORD bytes_written = 0;
  WriteFile(file, message, (DWORD)lstrlenA(message), &bytes_written, NULL);
  CloseHandle(file);
}

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
  write_status("started\n");

  HMODULE d3d12_module = LoadLibraryA("d3d12.dll");
  if (d3d12_module == NULL) {
    write_status("LoadLibraryA(d3d12.dll) failed\n");
    return fail_last_error("LoadLibraryA(d3d12.dll)");
  }

  union {
    FARPROC symbol;
    D3D12CreateDeviceProc function;
  } create_device;
  create_device.symbol =
      GetProcAddress(d3d12_module, "D3D12CreateDevice");
  if (create_device.symbol == NULL) {
    write_status("GetProcAddress(D3D12CreateDevice) failed\n");
    const int status = fail_last_error("GetProcAddress(D3D12CreateDevice)");
    FreeLibrary(d3d12_module);
    return status;
  }

  ID3D12Device *device = NULL;
  HRESULT result = create_device.function(
      NULL,
      D3D_FEATURE_LEVEL_11_0,
      &IID_ID3D12Device,
      (void **)&device);
  if (FAILED(result)) {
    write_status("D3D12CreateDevice failed\n");
    FreeLibrary(d3d12_module);
    return fail_hresult("D3D12CreateDevice", result);
  }

  printf("KONYAK_D3D12_DEVICE_PROBE_OK featureLevel=0x%04x\n", 0x0b00u);
  write_status(kSuccessMarker);
  const int sentinel_status = write_success_sentinel();

  if (device != NULL) {
    ID3D12Device_Release(device);
  }
  FreeLibrary(d3d12_module);
  return sentinel_status;
}

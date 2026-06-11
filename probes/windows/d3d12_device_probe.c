#define COBJMACROS
#define INITGUID
#define WIN32_LEAN_AND_MEAN

#include <d3d12.h>
#include <stdio.h>
#include <windows.h>

typedef HRESULT(WINAPI *D3D12CreateDeviceProc)(
    IUnknown *,
    D3D_FEATURE_LEVEL,
    REFIID,
    void **);

static int fail_hresult(const char *operation, HRESULT result) {
  fprintf(stderr, "%s failed: 0x%08lx\n", operation, (unsigned long)result);
  return 1;
}

static int fail_last_error(const char *operation) {
  const DWORD error = GetLastError();
  fprintf(stderr, "%s failed: %lu\n", operation, (unsigned long)error);
  return 1;
}

int main(void) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);

  HMODULE d3d12_module = LoadLibraryA("d3d12.dll");
  if (d3d12_module == NULL) {
    return fail_last_error("LoadLibraryA(d3d12.dll)");
  }

  union {
    FARPROC symbol;
    D3D12CreateDeviceProc function;
  } create_device;
  create_device.symbol =
      GetProcAddress(d3d12_module, "D3D12CreateDevice");
  if (create_device.symbol == NULL) {
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
    FreeLibrary(d3d12_module);
    return fail_hresult("D3D12CreateDevice", result);
  }

  printf("KONYAK_D3D12_DEVICE_PROBE_OK featureLevel=0x%04x\n", 0x0b00u);

  if (device != NULL) {
    ID3D12Device_Release(device);
  }
  FreeLibrary(d3d12_module);
  return 0;
}

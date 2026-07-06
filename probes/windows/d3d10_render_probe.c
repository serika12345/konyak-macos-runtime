#define COBJMACROS
#define INITGUID
#define WIN32_LEAN_AND_MEAN

#include <d3d10.h>
#include <stdio.h>
#include <windows.h>

static const char kSuccessSentinelPath[] =
    "C:\\konyak-d3d10-render-probe-ok.txt";
static const char kSuccessMarker[] =
    "KONYAK_D3D10_RENDER_PROBE_OK\n";

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

static int fail_message(const char *message) {
  fprintf(stderr, "%s\n", message);
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

static int byte_matches(unsigned char actual, unsigned char expected) {
  const int delta = (int)actual - (int)expected;
  return delta >= -2 && delta <= 2;
}

static int verify_first_pixel(const D3D10_MAPPED_TEXTURE2D *mapped) {
  if (mapped->pData == NULL) {
    return fail_message("ID3D10Texture2D::Map returned a null data pointer");
  }
  if (mapped->RowPitch < 4) {
    fprintf(stderr, "ID3D10Texture2D::Map returned a short row pitch: %u\n",
            mapped->RowPitch);
    return 1;
  }

  const unsigned char *pixel = (const unsigned char *)mapped->pData;
  const unsigned char expected[4] = {32, 128, 223, 255};
  const int matches =
      byte_matches(pixel[0], expected[0]) &&
      byte_matches(pixel[1], expected[1]) &&
      byte_matches(pixel[2], expected[2]) &&
      byte_matches(pixel[3], expected[3]);
  if (!matches) {
    fprintf(
        stderr,
        "D3D10 readback pixel mismatch: got [%u, %u, %u, %u], expected [%u, %u, %u, %u]\n",
        pixel[0],
        pixel[1],
        pixel[2],
        pixel[3],
        expected[0],
        expected[1],
        expected[2],
        expected[3]);
    return 1;
  }

  printf(
      "KONYAK_D3D10_RENDER_READBACK pixel=[%u,%u,%u,%u] rowPitch=%u\n",
      pixel[0],
      pixel[1],
      pixel[2],
      pixel[3],
      mapped->RowPitch);
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
  ID3D10Texture2D *render_texture = NULL;
  ID3D10Texture2D *staging_texture = NULL;
  ID3D10RenderTargetView *render_target_view = NULL;
  D3D10_MAPPED_TEXTURE2D mapped = {0};
  int mapped_texture = 0;
  int status = 1;

  HRESULT result = create_device.function(
      NULL,
      D3D10_DRIVER_TYPE_HARDWARE,
      NULL,
      0,
      D3D10_SDK_VERSION,
      &device);
  if (FAILED(result)) {
    status = fail_hresult("D3D10CreateDevice", result);
    goto cleanup;
  }

  D3D10_TEXTURE2D_DESC render_desc = {0};
  render_desc.Width = 16;
  render_desc.Height = 16;
  render_desc.MipLevels = 1;
  render_desc.ArraySize = 1;
  render_desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  render_desc.SampleDesc.Count = 1;
  render_desc.Usage = D3D10_USAGE_DEFAULT;
  render_desc.BindFlags = D3D10_BIND_RENDER_TARGET;

  result = ID3D10Device_CreateTexture2D(
      device,
      &render_desc,
      NULL,
      &render_texture);
  if (FAILED(result)) {
    status = fail_hresult("ID3D10Device::CreateTexture2D(render)", result);
    goto cleanup;
  }

  result = ID3D10Device_CreateRenderTargetView(
      device,
      (ID3D10Resource *)render_texture,
      NULL,
      &render_target_view);
  if (FAILED(result)) {
    status = fail_hresult("ID3D10Device::CreateRenderTargetView", result);
    goto cleanup;
  }

  const float clear_color[4] = {0.125f, 0.5f, 0.875f, 1.0f};
  ID3D10Device_ClearRenderTargetView(
      device,
      render_target_view,
      clear_color);

  D3D10_TEXTURE2D_DESC staging_desc = render_desc;
  staging_desc.Usage = D3D10_USAGE_STAGING;
  staging_desc.BindFlags = 0;
  staging_desc.CPUAccessFlags = D3D10_CPU_ACCESS_READ;

  result = ID3D10Device_CreateTexture2D(
      device,
      &staging_desc,
      NULL,
      &staging_texture);
  if (FAILED(result)) {
    status = fail_hresult("ID3D10Device::CreateTexture2D(staging)", result);
    goto cleanup;
  }

  ID3D10Device_CopyResource(
      device,
      (ID3D10Resource *)staging_texture,
      (ID3D10Resource *)render_texture);
  ID3D10Device_Flush(device);

  result = ID3D10Texture2D_Map(
      staging_texture,
      0,
      D3D10_MAP_READ,
      0,
      &mapped);
  if (FAILED(result)) {
    status = fail_hresult("ID3D10Texture2D::Map", result);
    goto cleanup;
  }
  mapped_texture = 1;

  status = verify_first_pixel(&mapped);
  if (status != 0) {
    goto cleanup;
  }

  printf(
      "KONYAK_D3D10_RENDER_PROBE_OK sdkVersion=0x%04x\n",
      (unsigned int)D3D10_SDK_VERSION);
  status = write_success_sentinel();

cleanup:
  if (mapped_texture) {
    ID3D10Texture2D_Unmap(staging_texture, 0);
  }
  if (render_target_view != NULL) {
    ID3D10RenderTargetView_Release(render_target_view);
  }
  if (staging_texture != NULL) {
    ID3D10Texture2D_Release(staging_texture);
  }
  if (render_texture != NULL) {
    ID3D10Texture2D_Release(render_texture);
  }
  if (device != NULL) {
    ID3D10Device_Release(device);
  }
  FreeLibrary(d3d10_module);
  return status;
}

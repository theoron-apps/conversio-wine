/* Exercise D3DMetal window destruction while another thread presents and
 * processes native window events. A watchdog turns a driver deadlock into
 * a failing process, without relying on a SIP-protected timeout wrapper. */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

static volatile LONG stop;
static HANDLE ready;
enum { iterations = 20, watchdog_ms = 60000 };

struct graphics
{
    IDXGISwapChain *swap;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    ID3D11RenderTargetView *view;
};

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static HWND create_window(int x)
{
    return CreateWindowW(L"ConversioSurfaceRace", L"Conversio D3DMetal surface race",
                         WS_OVERLAPPEDWINDOW | WS_VISIBLE, x, 40, 320, 240,
                         NULL, NULL, GetModuleHandleW(NULL), NULL);
}

static int init_graphics(HWND hwnd, struct graphics *g)
{
    DXGI_SWAP_CHAIN_DESC desc = {0};
    ID3D11Texture2D *texture = NULL;
    HRESULT hr;
    desc.BufferDesc.Width = 320;
    desc.BufferDesc.Height = 240;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.OutputWindow = hwnd;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                      D3D11_SDK_VERSION, &desc, &g->swap, &g->device,
                                      NULL, &g->context);
    if (FAILED(hr))
    {
        printf("device failed %lx\n", (unsigned long)hr);
        return 0;
    }
    hr = IDXGISwapChain_GetBuffer(g->swap, 0, &IID_ID3D11Texture2D, (void **)&texture);
    if (FAILED(hr)) return 0;
    hr = ID3D11Device_CreateRenderTargetView(g->device, (ID3D11Resource *)texture, NULL, &g->view);
    ID3D11Texture2D_Release(texture);
    return SUCCEEDED(hr);
}

static int frame(struct graphics *g)
{
    float color[] = {0.05f, 0.1f, 0.2f, 1};
    MSG msg;
    HRESULT hr;
    ID3D11DeviceContext_ClearRenderTargetView(g->context, g->view, color);
    hr = IDXGISwapChain_Present(g->swap, 0, 0);
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return SUCCEEDED(hr);
}

static void cleanup(struct graphics *g)
{
    if (g->context)
    {
        ID3D11DeviceContext_ClearState(g->context);
        ID3D11DeviceContext_Flush(g->context);
    }
    if (g->view) ID3D11RenderTargetView_Release(g->view);
    if (g->swap) IDXGISwapChain_Release(g->swap);
    if (g->context) ID3D11DeviceContext_Release(g->context);
    if (g->device) ID3D11Device_Release(g->device);
}

static DWORD WINAPI presenter(void *unused)
{
    HWND hwnd = create_window(20);
    struct graphics g = {0};
    int ok = hwnd && init_graphics(hwnd, &g);
    (void)unused;
    if (!ok) InterlockedExchange(&stop, 1);
    SetEvent(ready);
    while (ok && !InterlockedCompareExchange(&stop, 0, 0))
    {
        ok = frame(&g);
        Sleep(1);
    }
    cleanup(&g);
    if (hwnd) DestroyWindow(hwnd);
    return ok ? 0 : 2;
}

static DWORD WINAPI destroyer(void *unused)
{
    int i, j;
    (void)unused;
    if (WaitForSingleObject(ready, 10000) != WAIT_OBJECT_0 ||
        InterlockedCompareExchange(&stop, 0, 0)) return 2;
    for (i = 0; i < iterations; i++)
    {
        HWND hwnd = create_window(360);
        struct graphics g = {0};
        int ok = hwnd && init_graphics(hwnd, &g);
        for (j = 0; ok && j < 4; j++) ok = frame(&g);
        cleanup(&g);
        if (hwnd) DestroyWindow(hwnd);
        if (!ok)
        {
            InterlockedExchange(&stop, 1);
            return 2;
        }
        printf("destroyed %d\n", i + 1);
    }
    InterlockedExchange(&stop, 1);
    return 0;
}

int main(void)
{
    WNDCLASSW wc = {0};
    HANDLE threads[2];
    DWORD status, a, b;
    setvbuf(stdout, NULL, _IONBF, 0);
    wc.lpfnWndProc = wndproc;
    wc.lpszClassName = L"ConversioSurfaceRace";
    wc.hInstance = GetModuleHandleW(NULL);
    if (!RegisterClassW(&wc)) return 2;
    ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!ready) return 2;
    threads[0] = CreateThread(NULL, 0, presenter, NULL, 0, NULL);
    threads[1] = CreateThread(NULL, 0, destroyer, NULL, 0, NULL);
    if (!threads[0] || !threads[1]) return 2;
    status = WaitForMultipleObjects(2, threads, TRUE, watchdog_ms);
    if (status == WAIT_TIMEOUT)
    {
        puts("FAIL: 60 s watchdog (possible surface lock deadlock)");
        TerminateProcess(GetCurrentProcess(), 124);
        return 124;
    }
    if (status != WAIT_OBJECT_0) return 2;
    GetExitCodeThread(threads[0], &a);
    GetExitCodeThread(threads[1], &b);
    CloseHandle(threads[0]);
    CloseHandle(threads[1]);
    CloseHandle(ready);
    printf("threads exited %lu %lu\n", (unsigned long)a, (unsigned long)b);
    return a || b;
}

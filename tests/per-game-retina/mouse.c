#include <windows.h>
#include <windowsx.h>
#include <stdio.h>

static unsigned int clicks;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg == WM_LBUTTONDOWN)
    {
        POINT client = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)}, screen = client, cursor = {-1, -1};
        DWORD pos = GetMessagePos();
        ClientToScreen(hwnd, &screen);
        GetCursorPos(&cursor);
        printf("click=%u client=%ld,%ld screen=%ld,%ld message=%d,%d cursor=%ld,%ld\n",
               ++clicks, client.x, client.y, screen.x, screen.y,
               GET_X_LPARAM(pos), GET_Y_LPARAM(pos), cursor.x, cursor.y);
        fflush(stdout);
        return 0;
    }
    if (msg == WM_LBUTTONUP && clicks == 2) DestroyWindow(hwnd);
    if (msg == WM_TIMER || msg == WM_CLOSE) DestroyWindow(hwnd);
    if (msg == WM_DESTROY) PostQuitMessage(clicks == 2 ? 0 : 1);
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int main(void)
{
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSW cls = {.lpfnWndProc = window_proc, .hInstance = instance,
                     .lpszClassName = L"ConversioRetinaMouse",
                     .hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512)),
                     .hbrBackground = (HBRUSH)(COLOR_WINDOW + 1)};
    HWND window;
    MSG msg;
    int width, height;

    SetProcessDPIAware();
    width = GetSystemMetrics(SM_CXSCREEN);
    height = GetSystemMetrics(SM_CYSCREEN);
    if (!RegisterClassW(&cls)) return 1;
    /* Put the small window beyond half the main screen, where a client using
     * twice the bottle's coordinates would otherwise exceed its cursor bounds. */
    window = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, cls.lpszClassName, L"Conversio Retina click probe",
                             WS_CAPTION | WS_SYSMENU, width * 5 / 8, height / 3,
                             300, 200, NULL, NULL, instance, NULL);
    if (!window) return 1;
    ShowWindow(window, SW_SHOWNOACTIVATE);
    printf("ready %dx%d\n", width, height);
    fflush(stdout);
    SetTimer(window, 1, 15000, NULL);
    while (GetMessageW(&msg, NULL, 0, 0) > 0) DispatchMessageW(&msg);
    return msg.message == WM_QUIT ? (int)msg.wParam : 1;
}

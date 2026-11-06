#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>

static BOOL CALLBACK close_dialog(HWND hwnd, LPARAM unused)
{
    WCHAR title[256];
    GetWindowTextW(hwnd, title, 256);
    if (!wcsncmp(title, L"Conversio visibility dialog", 26))
        PostMessageW(hwnd, WM_CLOSE, 0, 0);
    return TRUE;
}

static void CALLBACK timeout(HWND hwnd, UINT msg, UINT_PTR timer, DWORD tick)
{
    KillTimer(NULL, timer);
    EnumThreadWindows(GetCurrentThreadId(), close_dialog, 0);
}

static DWORD WINAPI watchdog(void *unused)
{
    Sleep(8000);
    fputs("WATCHDOG: Wine did not finish the dialog\n", stderr);
    fflush(stderr);
    TerminateProcess(GetCurrentProcess(), 124);
    return 0;
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int main(int argc, char **argv)
{
    const char *scenario = argc > 1 ? argv[1] : "rapid";
    BOOL owned = argc > 2 && !strcmp(argv[2], "owned");
    BOOL topmost = argc <= 3 || strcmp(argv[3], "normal");
    const char *valid[] = {"hidden", "zero", "offscreen", "minimized", "visible", "hidden-after-show", "zero-after-show", "rapid"};
    BOOL recognized = FALSE;
    for (unsigned i = 0; i < sizeof(valid) / sizeof(valid[0]); i++)
        if (!strcmp(scenario, valid[i])) recognized = TRUE;
    if (!recognized) { fputs("Unknown scenario\n", stderr); return 2; }

    WNDCLASSW cls = {0};
    cls.lpfnWndProc = window_proc;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.lpszClassName = L"ConversioVisibilityRegression";
    cls.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    if (!RegisterClassW(&cls)) return 3;

    HWND owner = CreateWindowExW(topmost ? WS_EX_TOPMOST : 0, cls.lpszClassName,
        L"Conversio visibility owner", WS_OVERLAPPEDWINDOW, 100, 100, 500, 300,
        NULL, NULL, cls.hInstance, NULL);
    if (!owner) return 4;
    HANDLE guard = CreateThread(NULL, 0, watchdog, NULL, 0, NULL);
    if (!guard) return 5;
    CloseHandle(guard);

    if (!strcmp(scenario, "hidden")) ShowWindow(owner, SW_HIDE);
    else if (!strcmp(scenario, "zero")) SetWindowPos(owner, HWND_TOP, 100, 100, 0, 0, SWP_SHOWWINDOW);
    else if (!strcmp(scenario, "offscreen")) SetWindowPos(owner, HWND_TOP, -10000, -10000, 500, 300, SWP_SHOWWINDOW);
    else if (!strcmp(scenario, "minimized")) ShowWindow(owner, SW_MINIMIZE);
    else
    {
        ShowWindow(owner, SW_SHOW);
        UpdateWindow(owner);
        if (!strcmp(scenario, "hidden-after-show")) ShowWindow(owner, SW_HIDE);
        if (!strcmp(scenario, "zero-after-show")) SetWindowPos(owner, HWND_TOP, 100, 100, 0, 0, 0);
        if (!strcmp(scenario, "rapid"))
        {
            /* Win32 has cleared WS_MINIMIZE before Cocoa finishes miniaturizing. */
            ShowWindow(owner, SW_MINIMIZE);
            ShowWindow(owner, SW_RESTORE);
        }
    }

    printf("CASE %s %s %s owner=%p visible=%d iconic=%d\n", scenario,
        owned ? "owned" : "unowned", topmost ? "topmost" : "normal",
        owner, IsWindowVisible(owner), IsIconic(owner));
    fflush(stdout);
    SetTimer(NULL, 0, 1800, timeout);
    MessageBoxW(owned ? owner : NULL,
        L"This message must be visible. It closes automatically.",
        L"Conversio visibility dialog", MB_OK);
    DestroyWindow(owner);
    puts("DONE");
    return 0;
}

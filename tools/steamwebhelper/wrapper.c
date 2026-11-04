/*
 * steamwebhelper wrapper for Conversio — MIT License, (c) 2026 Theoron.
 *
 * Steam's interface is Chromium (CEF). Under Wine on Apple silicon its GPU process fails
 * (ANGLE can't get the D3D11/GLES it wants) and the UI crashes or paints black, and its
 * separate network process trips over Wine's TLS. Steam's own -cef-* switches don't reach
 * steamwebhelper.exe, so this tiny program takes its place:
 *
 *   steamwebhelper.exe       this wrapper
 *   steamwebhelper_real.exe  Valve's binary, started with --disable-gpu --single-process
 *
 * Conversio puts the wrapper in place before every Steam launch and starts Steam with
 * -noverifyfiles, so Steam's file check doesn't swap Valve's binary back.
 * The approach was worked out by notpop/steam-on-m1-wine and ByMedion/macos-wine-steam.
 */
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

#define EXTRA_FLAGS L"--disable-gpu --single-process"
#define REAL_NAME   L"steamwebhelper_real.exe"

/* The command line without our own program name. */
static const wchar_t *arguments(void)
{
    const wchar_t *cmd = GetCommandLineW();
    int quoted = 0;
    if (!cmd) return L"";
    for (; *cmd; cmd++) {
        if (*cmd == L'"') quoted = !quoted;
        else if (*cmd == L' ' && !quoted) break;
    }
    while (*cmd == L' ') cmd++;
    return cmd;
}

int wmain(void)
{
    wchar_t real[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, real, MAX_PATH);
    wchar_t *slash;
    const wchar_t *args;
    wchar_t *command;
    size_t size;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD code = 1;

    if (length == 0 || length >= MAX_PATH) return 1;
    slash = wcsrchr(real, L'\\');
    if (!slash || (size_t)(slash - real) + 1 + wcslen(REAL_NAME) >= MAX_PATH) return 1;
    wcscpy(slash + 1, REAL_NAME);

    args = arguments();
    size = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(args) + 8;
    command = (wchar_t *)calloc(size, sizeof(wchar_t));
    if (!command) return 1;
    _snwprintf(command, size, L"\"%ls\" %ls %ls", real, EXTRA_FLAGS, args);

    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    ZeroMemory(&process, sizeof(process));
    if (!CreateProcessW(real, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process)) {
        free(command);
        return 1;
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hProcess);
    CloseHandle(process.hThread);
    free(command);
    return (int)code;
}

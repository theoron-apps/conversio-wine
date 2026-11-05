/*
 * CEF helper wrapper for Conversio — MIT License, (c) 2026 Theoron.
 *
 * Steam's interface and Rockstar's Social Club are Chromium (CEF). Under Wine on Apple silicon
 * their GPU process fails or paints into a window that belongs to another process, which winemac
 * can't show: the window stays black, white or crashes. Neither app lets us pass Chromium switches
 * to its helper, so this tiny program takes the helper's place:
 *
 *   <name>.exe        this wrapper (steamwebhelper.exe, SocialClubHelper.exe, ...)
 *   <name>_real.exe   the vendor's binary, started with the switches below plus the original ones
 *
 * The wrapper picks the switches by its own file name, so one binary serves every helper.
 * Conversio puts it in place before every launch (Steam with -noverifyfiles, so Steam's file
 * check doesn't swap Valve's binary back). The Steam approach was worked out by
 * notpop/steam-on-m1-wine and ByMedion/macos-wine-steam.
 */
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

struct helper {
    const wchar_t *name;   /* file name without .exe, compared case-insensitively */
    const wchar_t *flags;
};

static const struct helper helpers[] = {
    /* Steam: everything in one process; the separate network process trips over Wine's TLS. */
    { L"steamwebhelper", L"--disable-gpu --single-process" },
    /* Social Club needs its renderer as a separate process (its IPC checks the remote process),
     * so only the GPU work moves into the browser process and onto the CPU. */
    { L"SocialClubHelper", L"--in-process-gpu --disable-gpu --disable-gpu-compositing --disable-software-rasterizer" },
};

static const wchar_t *default_flags = L"--disable-gpu --disable-gpu-compositing";

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
    wchar_t real[MAX_PATH + 16];
    wchar_t base[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, real, MAX_PATH);
    wchar_t *slash, *dot;
    const wchar_t *args, *flags = default_flags;
    wchar_t *command;
    size_t size, i;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD code = 1;

    if (length == 0 || length >= MAX_PATH) return 1;
    slash = wcsrchr(real, L'\\');
    if (!slash) return 1;
    wcsncpy(base, slash + 1, MAX_PATH - 1);
    base[MAX_PATH - 1] = 0;
    dot = wcsrchr(base, L'.');
    if (dot) *dot = 0;
    for (i = 0; i < sizeof(helpers) / sizeof(helpers[0]); i++) {
        if (!_wcsicmp(base, helpers[i].name)) flags = helpers[i].flags;
    }
    /* <dir>\<base>_real.exe */
    if ((size_t)(slash - real) + 1 + wcslen(base) + wcslen(L"_real.exe") >= MAX_PATH) return 1;
    _snwprintf(slash + 1, MAX_PATH, L"%ls_real.exe", base);

    args = arguments();
    size = wcslen(real) + wcslen(flags) + wcslen(args) + 8;
    command = (wchar_t *)calloc(size, sizeof(wchar_t));
    if (!command) return 1;
    _snwprintf(command, size, L"\"%ls\" %ls %ls", real, flags, args);

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

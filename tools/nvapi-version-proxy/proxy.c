/* SPDX-License-Identifier: MIT
 * Keep Apple's NVAPI implementation, overriding only a configured driver version.
 * No NVIDIA/Apple code is linked into or distributed with this helper.
 */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

typedef void *(__cdecl *query_fn)(unsigned int);
typedef int (__cdecl *sys_version_fn)(unsigned int *, char *);
typedef struct { unsigned int version, driver, branch; char build[64], adapter[64]; } display_version;
typedef int (__cdecl *display_version_fn)(void *, display_version *);
static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static query_fn original_query;
static unsigned int minimum_version;
static const WCHAR implementation_name[] = L"conversio_nvapi64.dll";

static BOOL CALLBACK initialize(PINIT_ONCE init, PVOID parameter, PVOID *context)
{
    (void)init; (void)parameter; (void)context;
    WCHAR executable[32768], key[32768];
    if (GetModuleFileNameW(NULL, executable, 32768)) {
        const WCHAR *name = wcsrchr(executable, L'\\');
        name = name ? name + 1 : executable;
        if (swprintf(key, 32768, L"Software\\Wine\\AppDefaults\\%ls\\NVAPI", name) > 0) {
            DWORD size = sizeof(minimum_version);
            if (RegGetValueW(HKEY_CURRENT_USER, key, L"DriverVersion", RRF_RT_REG_DWORD,
                             NULL, &minimum_version, &size) != ERROR_SUCCESS) minimum_version = 0;
        }
    }
    WCHAR path[MAX_PATH];
    HMODULE implementation = NULL;
    UINT length = GetSystemDirectoryW(path, MAX_PATH);
    if (length && length + 1 + wcslen(implementation_name) < MAX_PATH) {
        path[length++] = L'\\';
        wcscpy(path + length, implementation_name);
        implementation = LoadLibraryW(path);
    }
    if (implementation) original_query = (query_fn)(void *)GetProcAddress(implementation, "nvapi_QueryInterface");
    return TRUE;
}

static int __cdecl sys_version(unsigned int *version, char *branch)
{
    sys_version_fn original = (sys_version_fn)original_query(0x2926aaad);
    int status = original(version, branch);
    if (!status && version && *version < minimum_version) *version = minimum_version;
    return status;
}

static int __cdecl get_display_version(void *display, display_version *version)
{
    display_version_fn original = (display_version_fn)original_query(0xf951a4d1);
    int status = original(display, version);
    if (!status && version && version->driver < minimum_version) version->driver = minimum_version;
    return status;
}

__declspec(dllexport) void * __cdecl nvapi_QueryInterface(unsigned int id)
{
    InitOnceExecuteOnce(&once, initialize, NULL, NULL);
    if (!original_query) return NULL;
    void *original = original_query(id);
    if (!original || !minimum_version) return original;
    if (id == 0x2926aaad) return (void *)sys_version;
    if (id == 0xf951a4d1) return (void *)get_display_version;
    return original;
}

/* GPTK's own modules use this private export to register their direct dispatch.
 * During backend DLL initialization it can re-enter before InitOnce completes;
 * use the already mapped module first rather than waiting on our own callback. */
__declspec(dllexport) void * __cdecl nvapi_Direct_GetMethod(void *parameter)
{
    HMODULE backend = GetModuleHandleW(implementation_name);
    if (!backend) {
        InitOnceExecuteOnce(&once, initialize, NULL, NULL);
        backend = GetModuleHandleW(implementation_name);
    }
    typedef void *(__cdecl *direct_fn)(void *);
    direct_fn direct = backend ? (direct_fn)(void *)GetProcAddress(backend, "nvapi_Direct_GetMethod") : NULL;
    return direct ? direct(parameter) : NULL;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}

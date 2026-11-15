#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static BOOL query_source(const WCHAR *device, DISPLAYCONFIG_SOURCE_MODE *result)
{
    DISPLAYCONFIG_PATH_INFO *paths = NULL;
    DISPLAYCONFIG_MODE_INFO *modes = NULL;
    UINT32 path_count, mode_count;
    BOOL found = FALSE;
    LONG status;

    /* A display re-enumeration can resize the arrays between the two calls. */
    for (int attempt = 0; attempt < 3 && !found; ++attempt)
    {
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count, &mode_count)) break;
        paths = calloc(path_count, sizeof(*paths));
        modes = calloc(mode_count, sizeof(*modes));
        status = paths && modes ? QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths,
                                                     &mode_count, modes, NULL) : ERROR_NOT_ENOUGH_MEMORY;
        if (!status)
        {
            for (UINT32 i = 0; i < path_count; ++i)
            {
                DISPLAYCONFIG_PATH_SOURCE_INFO *source = &paths[i].sourceInfo;
                DISPLAYCONFIG_SOURCE_DEVICE_NAME name = {.header = {DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
                                                          sizeof(name), source->adapterId, source->id}};
                if (source->modeInfoIdx >= mode_count ||
                    modes[source->modeInfoIdx].infoType != DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE ||
                    DisplayConfigGetDeviceInfo(&name.header) || wcscmp(name.viewGdiDeviceName, device))
                    continue;
                *result = modes[source->modeInfoIdx].sourceMode;
                found = TRUE;
                break;
            }
        }
        free(paths);
        free(modes);
        if (status != ERROR_INSUFFICIENT_BUFFER) break;
    }
    return found;
}

static int sample(void)
{
    const POINT origin = {0, 0};
    HMONITOR primary = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFOEXW monitor = {.cbSize = sizeof(monitor)};
    DEVMODEW current = {.dmSize = sizeof(current)}, saved = {.dmSize = sizeof(saved)};
    DISPLAYCONFIG_SOURCE_MODE source = {0};
    int width = GetSystemMetrics(SM_CXSCREEN), height = GetSystemMetrics(SM_CYSCREEN);
    HDC dc = GetDC(NULL);
    int gdi_width = GetDeviceCaps(dc, HORZRES), gdi_height = GetDeviceCaps(dc, VERTRES);
    ReleaseDC(NULL, dc);

    if (!EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &current) ||
        !EnumDisplaySettingsW(NULL, ENUM_REGISTRY_SETTINGS, &saved) ||
        !GetMonitorInfoW(primary, (MONITORINFO *)&monitor) || !query_source(monitor.szDevice, &source))
    {
        fprintf(stderr, "Could not read primary monitor settings (%lu)\n", GetLastError());
        return 1;
    }

    printf("pid=%lu screen=%dx%d current=%lux%lu gdi=%dx%d config=%ux%u dpi=%u\n",
           GetCurrentProcessId(), width, height, current.dmPelsWidth, current.dmPelsHeight,
           gdi_width, gdi_height, source.width, source.height, GetDpiForSystem());
    printf("device=%ls monitor=%ld,%ld,%ld,%ld work=%ld,%ld,%ld,%ld saved=%lux%lu\n",
           monitor.szDevice, monitor.rcMonitor.left, monitor.rcMonitor.top,
           monitor.rcMonitor.right, monitor.rcMonitor.bottom, monitor.rcWork.left, monitor.rcWork.top,
           monitor.rcWork.right, monitor.rcWork.bottom, saved.dmPelsWidth, saved.dmPelsHeight);
    fflush(stdout);
    if (width != (int)current.dmPelsWidth || height != (int)current.dmPelsHeight ||
        width != monitor.rcMonitor.right - monitor.rcMonitor.left ||
        height != monitor.rcMonitor.bottom - monitor.rcMonitor.top ||
        width != gdi_width || height != gdi_height ||
        width != (int)source.width || height != (int)source.height)
    {
        fprintf(stderr, "Screen metrics, current mode, monitor, GDI and display config disagree\n");
        return 2;
    }
    return 0;
}

int main(int argc, char **argv)
{
    unsigned long duration = argc > 1 ? strtoul(argv[1], NULL, 10) : 0;
    ULONGLONG until = GetTickCount64() + duration;
    int result;

    SetProcessDPIAware();
    do
    {
        if ((result = sample())) return result;
        if (GetTickCount64() >= until) break;
        Sleep(500);
    } while (TRUE);
    return 0;
}

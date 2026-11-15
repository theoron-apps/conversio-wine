#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv) {
    DEVMODEW dm = {.dmSize = sizeof(dm)};
    MONITORINFOEXW monitor = {.cbSize = sizeof(monitor)};
    const POINT origin = {0, 0};
    HMONITOR primary;
    DEVMODEW saved = {.dmSize = sizeof(saved)};

    SetProcessDPIAware();
    primary = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    if (!EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &dm) ||
        !EnumDisplaySettingsW(NULL, ENUM_REGISTRY_SETTINGS, &saved) ||
        !GetMonitorInfoW(primary, (MONITORINFO *)&monitor))
    {
        fprintf(stderr, "Could not read primary monitor settings (%lu)\n", GetLastError());
        return 1;
    }
    printf("pid=%lu screen=%dx%d current=%lux%lu dpi=%u\n", GetCurrentProcessId(), GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), dm.dmPelsWidth, dm.dmPelsHeight, GetDpiForSystem());
    printf("device=%ls monitor=%ld,%ld,%ld,%ld work=%ld,%ld,%ld,%ld saved=%lux%lu\n",
           monitor.szDevice, monitor.rcMonitor.left, monitor.rcMonitor.top,
           monitor.rcMonitor.right, monitor.rcMonitor.bottom, monitor.rcWork.left,
           monitor.rcWork.top, monitor.rcWork.right, monitor.rcWork.bottom, saved.dmPelsWidth, saved.dmPelsHeight);
    if ((LONG)dm.dmPelsWidth != monitor.rcMonitor.right - monitor.rcMonitor.left ||
        (LONG)dm.dmPelsHeight != monitor.rcMonitor.bottom - monitor.rcMonitor.top ||
        (int)dm.dmPelsWidth != GetSystemMetrics(SM_CXSCREEN) ||
        (int)dm.dmPelsHeight != GetSystemMetrics(SM_CYSCREEN))
    {
        fprintf(stderr, "Monitor rectangle, current mode, and screen metrics disagree\n");
        return 2;
    }

    int native = 0;
    for (int i=0; EnumDisplaySettingsW(NULL,i,&dm); i++)
        if(dm.dmPelsWidth==3456 && dm.dmPelsHeight==2234) native++;
    printf("native_modes=%d\n",native); fflush(stdout);
    if(argc>1) Sleep(atoi(argv[1]));
    return 0;
}

#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv) {
    DEVMODEW dm = {.dmSize = sizeof(dm)};
    SetProcessDPIAware();
    EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &dm);
    printf("pid=%lu screen=%dx%d current=%lux%lu dpi=%u\n", GetCurrentProcessId(), GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), dm.dmPelsWidth, dm.dmPelsHeight, GetDpiForSystem());
    int native = 0;
    for (int i=0; EnumDisplaySettingsW(NULL,i,&dm); i++)
        if(dm.dmPelsWidth==3456 && dm.dmPelsHeight==2234) native++;
    printf("native_modes=%d\n",native); fflush(stdout);
    if(argc>1) Sleep(atoi(argv[1]));
    return 0;
}

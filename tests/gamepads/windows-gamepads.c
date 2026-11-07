/* MinGW: x86_64-w64-mingw32-gcc windows-gamepads.c -o windows-gamepads.exe
 *   -ldinput8 -ldxguid -lwinmm -lole32
 * Run in the game bottle, optionally with a polling duration in seconds.
 */
#define COBJMACROS
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <xinput.h>
#include <dinput.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned direct_count;
static BOOL CALLBACK device(const DIDEVICEINSTANCEA *d, void *unused) {
    printf("DirectInput name=%s product=%s type=%08lx\n",d->tszInstanceName,d->tszProductName,d->dwDevType); direct_count++; return DIENUM_CONTINUE;
}
int main(int argc,char**argv) {
    HMODULE x=LoadLibraryA("xinput1_4.dll");
    DWORD (WINAPI *state)(DWORD,XINPUT_STATE*)=(void*)GetProcAddress(x,"XInputGetState");
    if(!state) { puts("FAIL: XInputGetState missing"); return 2; }
    IDirectInput8A *di=NULL; CoInitialize(NULL);
    HRESULT hr=DirectInput8Create(GetModuleHandleA(NULL),DIRECTINPUT_VERSION,&IID_IDirectInput8A,(void**)&di,NULL);
    if(SUCCEEDED(hr)) { IDirectInput8_EnumDevices(di,DI8DEVCLASS_GAMECTRL,device,NULL,DIEDFL_ATTACHEDONLY); IDirectInput8_Release(di); }
    printf("DirectInput hr=%08lx attached=%u joyGetNumDevs=%u\n",(unsigned long)hr,direct_count,joyGetNumDevs());
    UINT count=0; GetRawInputDeviceList(NULL,&count,sizeof(RAWINPUTDEVICELIST));
    RAWINPUTDEVICELIST *list=calloc(count,sizeof(*list));
    UINT got=GetRawInputDeviceList(list,&count,sizeof(*list));
    for(UINT i=0;got!=(UINT)-1&&i<got;i++) if(list[i].dwType==RIM_TYPEHID) {
        RID_DEVICE_INFO info={.cbSize=sizeof(info)}; UINT size=sizeof(info);
        if(GetRawInputDeviceInfoA(list[i].hDevice,RIDI_DEVICEINFO,&info,&size)!=(UINT)-1)
            printf("rawHID vid=%04lx pid=%04lx usage=%04x/%04x\n",info.hid.dwVendorId,info.hid.dwProductId,info.hid.usUsagePage,info.hid.usUsage);
    } free(list);
    DWORD until=GetTickCount()+1000*(argc>1?atoi(argv[1]):1); DWORD prev[4]={~0u,~0u,~0u,~0u};
    do {
        for(DWORD i=0;i<4;i++) { XINPUT_STATE s={0}; DWORD status=state(i,&s);
            if(prev[i]!=status || status==ERROR_SUCCESS) printf("XInput slot=%lu status=%lu packet=%lu buttons=%04x LT=%u RT=%u LX=%d LY=%d RX=%d RY=%d\n",i,status,s.dwPacketNumber,s.Gamepad.wButtons,s.Gamepad.bLeftTrigger,s.Gamepad.bRightTrigger,s.Gamepad.sThumbLX,s.Gamepad.sThumbLY,s.Gamepad.sThumbRX,s.Gamepad.sThumbRY);
            prev[i]=status;
        } fflush(stdout); Sleep(250);
    } while((LONG)(until-GetTickCount())>0);
    CoUninitialize(); FreeLibrary(x); return 0;
}

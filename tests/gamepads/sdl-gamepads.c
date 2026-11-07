/* Inspect the exact bundled SDL2-compat -> SDL3 path used by winebus.
 * clang -arch x86_64 -I/opt/homebrew/include/SDL2 sdl-gamepads.c -o sdl-gamepads
 * ./sdl-gamepads /path/to/Wine/lib/libSDL2-2.0.0.dylib [seconds]
 * No link to a developer's Homebrew SDL runtime is needed.
 */
#include <SDL.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define LOAD(f) __typeof__(&f) p##f = dlsym(lib, #f); if (!p##f) { fprintf(stderr,"missing %s\n",#f); return 2; }
int main(int argc, char **argv) {
    if (argc<2) return 2;
    void *lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if (!lib) { fprintf(stderr,"%s\n",dlerror()); return 2; }
    LOAD(SDL_Init); LOAD(SDL_GetError); LOAD(SDL_Quit); LOAD(SDL_GetVersion);
    LOAD(SDL_NumJoysticks); LOAD(SDL_IsGameController); LOAD(SDL_JoystickNameForIndex);
    LOAD(SDL_GameControllerOpen); LOAD(SDL_GameControllerClose); LOAD(SDL_GameControllerGetButton);
    LOAD(SDL_GameControllerGetAxis); LOAD(SDL_JoystickGetDeviceGUID); LOAD(SDL_JoystickGetGUIDString);
    LOAD(SDL_PollEvent); LOAD(SDL_Delay);
    SDL_version v; pSDL_GetVersion(&v); printf("SDL %d.%d.%d\n",v.major,v.minor,v.patch);
    if(pSDL_Init(SDL_INIT_GAMECONTROLLER|SDL_INIT_HAPTIC)<0) { fprintf(stderr,"SDL init: %s\n",pSDL_GetError()); return 1; }
    SDL_GameController *opened[16]={0};
    time_t end=time(NULL)+(argc>2?atoi(argv[2]):1); int previous=-1;
    do {
        SDL_Event e; while(pSDL_PollEvent(&e)) {}
        int n=pSDL_NumJoysticks();
        if(n!=previous) { printf("SDL devices=%d\n",n); previous=n; }
        for(int i=0;i<n;i++) {
            char guid[33]; pSDL_JoystickGetGUIDString(pSDL_JoystickGetDeviceGUID(i),guid,sizeof(guid));
            printf("device=%d name=%s guid=%s mapped=%d",i,pSDL_JoystickNameForIndex(i),guid,pSDL_IsGameController(i));
            SDL_GameController *c=i<16 ? opened[i] : NULL;
            if(!c && i<16) c=opened[i]=pSDL_GameControllerOpen(i);
            if(c) { printf(" A=%d B=%d LX=%d LY=%d LT=%d RT=%d",pSDL_GameControllerGetButton(c,SDL_CONTROLLER_BUTTON_A),pSDL_GameControllerGetButton(c,SDL_CONTROLLER_BUTTON_B),pSDL_GameControllerGetAxis(c,SDL_CONTROLLER_AXIS_LEFTX),pSDL_GameControllerGetAxis(c,SDL_CONTROLLER_AXIS_LEFTY),pSDL_GameControllerGetAxis(c,SDL_CONTROLLER_AXIS_TRIGGERLEFT),pSDL_GameControllerGetAxis(c,SDL_CONTROLLER_AXIS_TRIGGERRIGHT));  }
            puts("");
        }
        fflush(stdout); pSDL_Delay(500);
    } while(time(NULL)<end);
    for(int i=0;i<16;i++) if(opened[i]) pSDL_GameControllerClose(opened[i]);
    pSDL_Quit(); return 0;
}

#!/usr/bin/env python3
"""Compile the real winemac caps method against the next driver's display sizes."""
import pathlib, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('static INT macdrv_GetDeviceCaps(')
end = source.index('\nstatic const struct user_driver_funcs', start)
method = source[start:end]
stub = r'''
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
typedef int INT;
typedef struct physical_device *PHYSDEV;
struct functions { INT (*pGetDeviceCaps)(PHYSDEV, INT); };
struct physical_device { struct functions *funcs; PHYSDEV next; };
#define HORZSIZE 4
#define VERTSIZE 6
#define HORZRES 8
#define VERTRES 10
#define DESKTOPHORZRES 118
#define TRACE(...) ((void)0)
#define GET_NEXT_PHYSDEV(dev, member) ((dev)->next)
static pthread_mutex_t device_data_mutex = PTHREAD_MUTEX_INITIALIZER;
static int device_data_valid = 1, horz_size = 345, vert_size = 223, retina_on;
static int width, height;
static void device_init(void) { assert(0); }
static INT next_caps(PHYSDEV dev, INT cap) {
    switch(cap) { case HORZRES: return width; case VERTRES: return height;
      case DESKTOPHORZRES: return width + 3840; default: return 96; }
}
'''
main = r'''
int main(void) {
    struct functions funcs = {next_caps};
    struct physical_device lower = {&funcs, NULL}, upper = {NULL, &lower};
    for (retina_on = 0; retina_on <= 1; retina_on++) {
        width = retina_on ? 3456 : 1728; height = retina_on ? 2234 : 1117;
        assert(macdrv_GetDeviceCaps(&upper, HORZRES) == width);
        assert(macdrv_GetDeviceCaps(&upper, VERTRES) == height);
        assert(macdrv_GetDeviceCaps(&upper, DESKTOPHORZRES) == width + 3840);
        assert(macdrv_GetDeviceCaps(&upper, HORZSIZE) == 345);
        assert(macdrv_GetDeviceCaps(&upper, VERTSIZE) == 223);
        assert(macdrv_GetDeviceCaps(&upper, 88) == 96);
    }
    puts("PASS: physical display sizes, Retina on/off, virtual desktop, millimetres and DPI forwarding");
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory)
    (path/'check.c').write_text(stub + method + main)
    subprocess.run(['clang', '-arch', 'x86_64', str(path/'check.c'), '-o', str(path/'check')], check=True)
    subprocess.run([str(path/'check')], check=True)

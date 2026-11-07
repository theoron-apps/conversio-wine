#include <windows.h>
#include <stdio.h>
typedef void *(__cdecl *Query)(unsigned);
typedef int (__cdecl *Init)(void);
typedef int (__cdecl *Version)(unsigned *,char *);
typedef struct { unsigned version,driver,branch; char build[64],adapter[64]; } DisplayVersion;
typedef int (__cdecl *Display)(void *,DisplayVersion *);
int main(int argc, char **argv) {
 unsigned expected = argc > 1 ? strtoul(argv[1],NULL,10) : 58082; int failures=0;
 HMODULE dll=LoadLibraryA("nvapi64.dll");
 if(!dll){printf("load error=%lu\n",GetLastError());return 1;}
 char module[MAX_PATH];GetModuleFileNameA(dll,module,MAX_PATH);printf("module=%s\n",module);
 Query query=(Query)GetProcAddress(dll,"nvapi_QueryInterface");
 if(!query) return 3;
 Init init=(Init)query(0x0150e828);
 if(!init) {printf("missing backend\n");return 4;}
 printf("initialize=%d\n",init());
 Version version=(Version)query(0x2926aaad);unsigned driver=0;char branch[64]={0};
 int result=version(&driver,branch);
 if(result || driver != expected) failures++;
 printf("SYS result=%d driver=%u branch=%s\n",result,driver,branch);
 Display display=(Display)query(0xf951a4d1);DisplayVersion info={0};info.version=sizeof(info)|(1<<16);
 result=display(NULL,&info);printf("Display result=%d driver=%u branch=%s adapter=%s\n",result,info.driver,info.build,info.adapter);
 if(result || info.driver != expected) failures++;
 HMODULE backend=LoadLibraryA("conversio_nvapi64.dll");
 Query real=backend ? (Query)GetProcAddress(backend,"nvapi_QueryInterface") : NULL;
 if(!real) return 2;
 // All non-version interfaces must be the original pointers, including NGX/D3D12 APIs.
 unsigned ids[]={0x0150e828,0xe5ac921f,0xceee8e9f,0x33c7358c,0xdeadbeef};
 for(unsigned i=0;i<sizeof(ids)/sizeof(ids[0]);i++)
  if(query(ids[i]) != real(ids[i])) failures++;
 DisplayVersion invalid={0};
 int actual=display(NULL,&invalid);
 typedef int (__cdecl *OriginalDisplay)(void *,DisplayVersion *);
 int original=((OriginalDisplay)real(0xf951a4d1))(NULL,&invalid);
 if(actual != original) failures++;
 printf("failures=%d\n",failures);
 return failures ? 1 : 0;
}

/* MinGW: x86_64-w64-mingw32-gcc mf-video.c -o mf-video.exe
 *   -lmfreadwrite -lmfplat -lmfuuid -lole32
 * Usage: mf-video.exe Z:\path\sample.mp4
 * Require ten decoded NV12 video samples from Media Foundation.
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <stdio.h>
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    WCHAR path[32768]; MultiByteToWideChar(CP_UTF8,0,argv[1],-1,path,32768);
    HRESULT hr=CoInitializeEx(NULL,COINIT_MULTITHREADED); if(FAILED(hr)) return 1;
    hr=MFStartup(MF_VERSION,MFSTARTUP_FULL); printf("MFStartup=%08lx\n",(unsigned long)hr);
    IMFSourceReader *reader=NULL; IMFMediaType *type=NULL; unsigned count=0;
    if(SUCCEEDED(hr)) hr=MFCreateSourceReaderFromURL(path,NULL,&reader);
    printf("MFCreateSourceReaderFromURL=%08lx\n",(unsigned long)hr);
    if(SUCCEEDED(hr)) hr=MFCreateMediaType(&type);
    if(SUCCEEDED(hr)) hr=IMFMediaType_SetGUID(type,&MF_MT_MAJOR_TYPE,&MFMediaType_Video);
    if(SUCCEEDED(hr)) hr=IMFMediaType_SetGUID(type,&MF_MT_SUBTYPE,&MFVideoFormat_NV12);
    if(SUCCEEDED(hr)) hr=IMFSourceReader_SetCurrentMediaType(reader,MF_SOURCE_READER_FIRST_VIDEO_STREAM,NULL,type);
    printf("Set NV12=%08lx\n",(unsigned long)hr);
    for(unsigned i=0;SUCCEEDED(hr)&&i<100&&count<10;i++) {
        IMFSample *sample=NULL; DWORD stream=0,flags=0; LONGLONG time=0;
        hr=IMFSourceReader_ReadSample(reader,MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,&stream,&flags,&time,&sample);
        if(sample) { DWORD len=0; IMFSample_GetTotalLength(sample,&len); printf("sample=%u time=%lld bytes=%lu flags=%08lx hr=%08lx\n",++count,time,len,flags,(unsigned long)hr); IMFSample_Release(sample); }
        if(flags&MF_SOURCE_READERF_ENDOFSTREAM) break;
    }
    if(type) IMFMediaType_Release(type); if(reader) IMFSourceReader_Release(reader);
    MFShutdown(); CoUninitialize(); printf("decoded=%u hr=%08lx\n",count,(unsigned long)hr);
    return FAILED(hr)||count<10;
}

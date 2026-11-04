# Cross-compiles the wrapper for 64-bit Windows with MinGW-w64.
CC      ?= x86_64-w64-mingw32-gcc
CFLAGS  ?= -O2 -Wall -Wextra -municode -DUNICODE -D_UNICODE
LDFLAGS ?= -static -mwindows

steamwebhelper-wrapper.exe: wrapper.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f steamwebhelper-wrapper.exe

CC = x86_64-w64-mingw32-gcc
CFLAGS = -O2 -Wall -Wextra

nvapi-version-proxy.dll: proxy.c
	$(CC) $(CFLAGS) -shared -static-libgcc -Wl,--no-insert-timestamp -s -o $@ $< -ladvapi32

clean:
	rm -f nvapi-version-proxy.dll

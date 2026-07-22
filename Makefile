# tn - tiny notepad. Freestanding, no libc, size-golfed.
CFLAGS = -Os -ffreestanding -fno-stack-protector -fno-asynchronous-unwind-tables \
         -fomit-frame-pointer -fno-ident -m64 -Wall
LDFLAGS = -nostdlib -no-pie -Wl,--build-id=none -Wl,--gc-sections \
          -Wl,-z,noseparate-code -Wl,-z,max-page-size=0x1000

tn: tn.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ tn.c
	strip -s -R .comment -R .note* $@
	@echo "size: $$(stat -c%s tn) bytes"

clean:
	rm -f tn

.PHONY: clean

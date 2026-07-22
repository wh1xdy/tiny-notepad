# tn - tiny notepad. Freestanding, no libc, size-golfed to the bone.
CFLAGS = -Os -ffreestanding -fno-stack-protector -fcf-protection=none \
         -fno-asynchronous-unwind-tables -fomit-frame-pointer -fno-ident -m64 -Wall
LDFLAGS = -nostdlib -no-pie -Wl,-T,link.ld -Wl,--build-id=none -Wl,--gc-sections

tn: tn.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ tn.c
	strip -s $@
	objcopy --strip-section-headers $@   # needs binutils >= 2.41
	@echo "size: $$(stat -c%s tn) bytes"

clean:
	rm -f tn

.PHONY: clean

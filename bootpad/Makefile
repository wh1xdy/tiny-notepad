# bootpad - a text editor in a 512-byte boot sector.
bootpad.bin: bootpad.asm
	nasm -f bin $< -o $@
	@printf 'code: %s bytes (of 512); signature: ' \
	  "$$(python3 -c 'print(len(open("bootpad.bin","rb").read()[:510].rstrip(b"\x00")))')"
	@python3 -c 'print(open("bootpad.bin","rb").read()[510:512].hex())'

# a 1.44 MB floppy image you can boot
bootpad.img: bootpad.bin
	cp bootpad.bin bootpad.img
	truncate -s 1474560 bootpad.img

# boot it in an emulator (needs qemu-system-i386)
run: bootpad.img
	qemu-system-i386 -drive file=bootpad.img,format=raw,if=floppy

clean:
	rm -f bootpad.bin bootpad.img

.PHONY: run clean

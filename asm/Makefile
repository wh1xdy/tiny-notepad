# tn (asm) - hand-written x86-64 with a hand-crafted ELF header.
tn: tn.asm
	nasm -f bin $< -o tn
	chmod +x tn
	@echo "size: $$(stat -c%s tn) bytes"

clean:
	rm -f tn

.PHONY: clean

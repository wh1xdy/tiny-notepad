# tn (asm) — 966 bytes, hand-written

The same editor as the C `tn`, rewritten in x86-64 assembly with a **hand-crafted
ELF header** — no compiler, no linker script, no `objcopy` pass. Full feature
parity: type, all four arrow keys, Backspace, Enter, `Ctrl-S` save, `Ctrl-Q` quit.

```
$ make
size: 966 bytes
$ ./tn note.txt
```

## Why it's smaller than the C build (1220 → 966)

- **The ELF header is written by hand** — 64 bytes of `ehdr` and 56 bytes of one
  program header, assembled with `nasm -f bin`. `p_filesz`/`p_memsz` are computed
  at assemble time; the 1 MiB buffer lives above the file image and the kernel
  zero-fills it (`p_memsz > p_filesz`).
- **Two registers hold the whole editor state** — `r15` = cursor, `r14` = length
  — so there are no stack spills.
- **Hand-rolled `memmove`** via `rep movsb` (forward for delete, `std` + backward
  for insert) instead of a compiler's byte-copy loop.
- Every syscall is set up inline; shared helpers (`wr`, `rd1`, `getcol`) are three
  tiny routines.

Of the 966 bytes, 120 are the ELF + program header (unavoidable for a hosted
Linux binary) and ~846 are code and the handful of ANSI escape strings.

## Build

```
make          # nasm -f bin -> a runnable ELF, prints the size
make clean
```

Needs `nasm`. x86-64 Linux only.

## How much further can you go?

For a *hosted* binary, ~120 bytes of that total is the mandatory ELF + program
header; the rest is genuinely the editor. To go below this class you have to
drop the OS entirely — see [`../bootpad`](../bootpad), a 512-byte boot-sector
editor (166 bytes of code) that runs on bare metal.

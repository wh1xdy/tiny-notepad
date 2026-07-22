# tn — tiny notepad

A full-screen terminal text editor in **1220 bytes**. No libc, no runtime, no
dependencies — just freestanding C on top of raw x86-64 Linux syscalls.

Dave Plummer — the retired Microsoft engineer who wrote the original Windows
Task Manager — built [**TinyRetroPad**](https://github.com/PlummersSoftwareLLC/TinyRetroPad),
a 2.5 kB Notepad clone, in x86 assembly. `tn` is **52% smaller**, and it's a
real ELF you can run right now. (Fair play: his 2.5 kB wraps the Windows
`RICHEDIT50W` control, so it inherits the whole editor engine — `tn` carries
its own. Different sports, same spirit.)

```
$ make
size: 1220 bytes
$ ./tn note.txt
```

## Keys

| key         | action        |
|-------------|---------------|
| arrows      | move cursor   |
| Backspace   | delete        |
| Enter       | newline       |
| `Ctrl-S`    | save          |
| `Ctrl-Q`    | quit          |

Open a file by passing it as an argument (`./tn file.txt`); a missing file is
created on save. With no argument it edits `untitled.txt`.

## How it's this small

Of the 1220 bytes, **1100 are code**; the rest is a 64-byte ELF header and a
single 56-byte program header. Every byte that isn't machine code was hunted
down and removed:

- **No libc.** The entry point is `_start`, not `main`. Every syscall
  (`read`, `write`, `open`, `close`, `ioctl`, `exit`) is one inline `syscall`
  instruction — no CRT, no dynamic loader, no relocations.
- **`.bss` is free.** The 1 MiB edit buffer lives in zero-initialised `.bss`,
  which the kernel maps at load time. It costs nothing on disk.
- **One segment, by hand.** A custom linker script (`link.ld`) emits a *single*
  `PT_LOAD` — no `GNU_STACK`, no separate data segment, no page of alignment
  padding between code and data.
- **No section headers.** `strip -s` then `objcopy --strip-section-headers`
  removes the entire section header table and `.shstrtab` — the kernel only
  reads program headers to run a binary.
- **No CET note.** `-fcf-protection=none` drops the `.note.gnu.property`
  section and with it two more program headers.
- **Golfed build.** `-Os -ffreestanding -nostdlib`, no stack protector, no
  unwind tables, no build-id.

The cursor is placed without any row/column arithmetic: after clearing the
screen and writing the text *up to* the cursor, the terminal cursor is already
in the right place, so `tn` saves it (`ESC 7` / DECSC), draws the rest of the
buffer, and restores it (`ESC 8` / DECRC). Shorter than computing coordinates —
and it can't miscount across wrapped lines.

Raw mode is set by hand too: `ioctl(TCGETS)` to snapshot the terminal, clear
`ICANON`/`ECHO`/`ISIG`/`IXON`, `ioctl(TCSETS)` to apply, restore on quit.

```
$ size tn        # before --strip-section-headers, so the sizes are visible
   text    data     bss     dec     hex filename
   1100       0 1048644 1049744  100490 tn
```

## Build

```
make          # build + strip + print size
make clean
```

Requires `gcc` (or `cc`), `ld`, `strip`, and `objcopy` from **binutils ≥ 2.41**
(for `--strip-section-headers`). x86-64 Linux only — the syscall numbers and the
`_start` stub are architecture-specific.

## How small can you actually go?

- **Hand-written assembly** would shave maybe 200–400 bytes off `tn`'s 1100
  bytes of code, but most of it is inherent — the read/edit/save loop has to
  exist. A hand-rolled Linux ELF that overlaps its header with code could reach
  roughly **700–900 bytes** and still edit.
- **The smallest runnable ELF in the world** is Brian Raiter's famous
  [45-byte executable](https://www.muppetlabs.com/~breadbox/software/tiny/teensy.html)
  — but it only calls `exit()`. The floor for an *editor* is its own code.
- **Change platforms and the header overhead vanishes.** A DOS `.COM` file has
  a zero-byte header (vs. an ELF's ~120); a **boot-sector editor** fits in ≤512
  bytes on bare metal via BIOS interrupts, no OS underneath at all. That's about
  as small as a standalone editor gets.

## Honourable mention

If you allow a browser, the smallest "notepad" is a ~30-byte URL:
`data:text/html,<body contenteditable>`. That's cheating — it's the browser
doing all the work. `tn` is the real thing: its own process, its own raw
terminal handling, reading and writing real files.

## Credits

Inspired by Dave Plummer's [TinyRetroPad](https://github.com/PlummersSoftwareLLC/TinyRetroPad)
(2.5 kB, x86 assembly, Windows). Dave is a retired Microsoft engineer — the
original Task Manager was his — and runs the *Dave's Garage* YouTube channel.

# tn — tiny notepad

A full-screen terminal text editor in **1968 bytes**. No libc, no runtime, no
dependencies — just freestanding C on top of raw x86-64 Linux syscalls.

Someone built Notepad in 2.5 kB on Windows. This is 23% smaller, and it's a
real ELF you can run right now.

```
$ make
size: 1968 bytes
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

- **No libc.** The entry point is `_start`, not `main`. Every syscall
  (`read`, `write`, `open`, `close`, `ioctl`, `exit`) is one inline `syscall`
  instruction — no CRT, no dynamic loader, no relocations.
- **`.bss` is free.** The 1 MiB edit buffer lives in zero-initialised `.bss`,
  which the kernel maps at load time. It costs nothing on disk — the whole file
  is 1968 bytes, of which only **1237 bytes are actual code**.
- **Merged segments.** `-z noseparate-code` folds code and data into one
  `PT_LOAD` so there's no page of alignment padding between them.
- **Golfed build.** `-Os -ffreestanding -nostdlib`, no stack protector, no
  unwind tables, no build-id, then `strip -s`.

Raw mode is set by hand: `ioctl(TCGETS)` to save the terminal, clear
`ICANON`/`ECHO`/`ISIG`/`IXON`, `ioctl(TCSETS)` to apply, and restore the
original on quit. Rendering is a full ANSI repaint per keystroke
(`\x1b[2J\x1b[H` + the buffer + a `\x1b[row;colH` to park the cursor) — simple,
and plenty fast for notes.

```
$ size tn
   text    data     bss     dec     hex filename
   1237       0 1048648 1049885 10051d tn
```

## Build

```
make          # build + strip + print size
make clean
```

Requires `gcc` (or `cc`), `ld`, and `strip`. x86-64 Linux only — the syscall
numbers and the `_start` stub are architecture-specific.

## Honourable mention

If you allow a browser, the smallest "notepad" is a ~30-byte URL:
`data:text/html,<body contenteditable>`. That's cheating — it's the browser
doing all the work. `tn` is the real thing: its own process, its own raw
terminal handling, reading and writing real files.

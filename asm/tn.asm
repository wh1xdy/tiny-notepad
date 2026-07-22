; tn (asm) - the tiny notepad, hand-written in x86-64 assembly with a
; hand-crafted ELF header. Same editor as the C version: type, arrows
; (all four), Backspace, Enter, Ctrl-S save, Ctrl-Q quit. Freestanding.
BITS 64
org 0x400000

; ---- registers held across the whole program ----
;   r15 = cur (cursor offset into BUF)
;   r14 = len (bytes used in BUF)
; ---- fixed addresses above the file image (kernel zero-fills these) ----
BUF   equ 0x420000          ; 1 MiB edit buffer
ORIG  equ 0x410000          ; saved termios (60 bytes)
RAW   equ 0x410040          ; modified termios
PATH  equ 0x410080          ; the file path pointer
KEY   equ 0x410088          ; 1-byte key scratch

; ================= ELF header (64 bytes) =================
ehdr:
        db 0x7f,"ELF",2,1,1,0
        times 8 db 0
        dw 2                ; e_type = EXEC
        dw 0x3e             ; e_machine = x86-64
        dd 1                ; e_version
        dq _start           ; e_entry
        dq phdr - ehdr      ; e_phoff = 64
        dq 0                ; e_shoff
        dd 0                ; e_flags
        dw 64               ; e_ehsize
        dw 56               ; e_phentsize
        dw 1                ; e_phnum
        dw 0                ; e_shentsize
        dw 0                ; e_shnum
        dw 0                ; e_shstrndx
; ================= program header (56 bytes) =============
phdr:
        dd 1                ; p_type = LOAD
        dd 7                ; p_flags = RWX
        dq 0                ; p_offset
        dq 0x400000         ; p_vaddr
        dq 0x400000         ; p_paddr
        dq FILEEND - ehdr   ; p_filesz (whole file)
        dq 0x120000         ; p_memsz  (covers BUF + 1 MiB)
        dq 0x1000           ; p_align

; ================= code =================================
_start:
        mov rdi, [rsp+16]           ; argv[1]
        test rdi, rdi
        jnz .havepath
        mov edi, DEFPATH            ; default "untitled.txt"
.havepath:
        mov [PATH], rdi
        ; open(path, O_RDONLY)
        mov eax, 2
        xor esi, esi
        xor edx, edx
        syscall
        xor r15d, r15d             ; cur = 0
        xor r14d, r14d             ; len = 0
        test rax, rax
        js .noload
        mov rbx, rax               ; fd
        mov eax, 0                 ; read(fd, BUF, 1 MiB)
        mov rdi, rbx
        mov esi, BUF
        mov edx, 0x100000
        syscall
        test rax, rax
        js .rd0
        mov r14, rax               ; len = bytes read
.rd0:
        mov eax, 3                 ; close(fd)
        mov rdi, rbx
        syscall
.noload:
        call raw_on

mainloop:
        call draw
        call rd1                    ; al = next byte
        cmp al, 17                  ; Ctrl-Q
        je quit
        cmp al, 19                  ; Ctrl-S
        je dosave
        cmp al, 127                 ; Backspace (DEL)
        je delback
        cmp al, 8                   ; Backspace (BS)
        je delback
        cmp al, 13                  ; Enter (CR)
        je doenter
        cmp al, 10                  ; Enter (LF)
        je doenter
        cmp al, 27                  ; ESC - arrow keys
        je doesc
        cmp al, 32
        jb mainloop                 ; ignore other control chars
        jmp ins_al                  ; printable -> insert

doenter:
        mov al, 10
        jmp ins_al

; ---- insert the char in AL at the cursor ----
ins_al:
        cmp r14, 0x100000
        jae mainloop                ; buffer full
        mov rcx, r14
        sub rcx, r15                ; bytes to shift right
        mov rsi, BUF
        add rsi, r14
        dec rsi                     ; src = BUF+len-1
        lea rdi, [rsi+1]            ; dst = BUF+len
        std
        rep movsb
        cld
        mov rdi, BUF
        add rdi, r15
        mov [rdi], al
        inc r15
        inc r14
        jmp mainloop

delback:
        test r15, r15
        jz mainloop
        mov rcx, r14
        sub rcx, r15                ; bytes after cursor
        mov rsi, BUF
        add rsi, r15                ; src = BUF+cur
        lea rdi, [rsi-1]           ; dst = BUF+cur-1
        cld
        rep movsb
        dec r15
        dec r14
        jmp mainloop

doesc:
        call rd1
        cmp al, '['
        jne mainloop
        call rd1
        cmp al, 'C'
        je goright
        cmp al, 'D'
        je goleft
        cmp al, 'A'
        je goup
        cmp al, 'B'
        je godown
        jmp mainloop

goright:
        cmp r15, r14
        jae mainloop
        inc r15
        jmp mainloop
goleft:
        test r15, r15
        jz mainloop
        dec r15
        jmp mainloop

; ---- move up one line, keeping column ----
goup:
        mov rdi, r15
        call getcol                 ; rax = col
        mov rbx, rax                ; col
        mov r10, r15
        sub r10, rbx                ; ls = line start of current
        test r10, r10
        jz mainloop                 ; already on first line
        lea rdi, [r10-1]
        call getcol                 ; rax = col of (ls-1) = length of prev line
        mov rsi, r10
        dec rsi
        sub rsi, rax                ; ps = start of prev line
        mov rcx, rbx                ; col
        cmp rcx, rax
        jbe .u1
        mov rcx, rax                ; clamp to prev line length
.u1:
        add rsi, rcx
        mov r15, rsi
        jmp mainloop

; ---- move down one line, keeping column ----
godown:
        mov rdi, r15
        call getcol
        mov rbx, rax                ; col
        mov rsi, r15
.dscan:
        cmp rsi, r14
        jae mainloop                ; no line below
        cmp byte [rsi+BUF], 10
        je .dfound
        inc rsi
        jmp .dscan
.dfound:
        lea rdi, [rsi+1]           ; ns = next line start
        mov rdx, rdi
.dscan2:
        cmp rdx, r14
        jae .dend
        cmp byte [rdx+BUF], 10
        je .dend
        inc rdx
        jmp .dscan2
.dend:
        mov rax, rdx
        sub rax, rdi                ; nlen
        mov rcx, rbx
        cmp rcx, rax
        jbe .d1
        mov rcx, rax
.d1:
        add rdi, rcx
        mov r15, rdi
        jmp mainloop

; getcol(rdi = position) -> rax = column within its line
getcol:
        xor eax, eax
.g:
        mov rdx, rdi
        sub rdx, rax
        test rdx, rdx
        jz .gd
        cmp byte [rdx+BUF-1], 10
        je .gd
        inc rax
        jmp .g
.gd:
        ret

dosave:
        ; open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
        mov eax, 2
        mov rdi, [PATH]
        mov esi, 577
        mov edx, 0o644
        syscall
        test rax, rax
        js mainloop
        mov rbx, rax                ; fd
        mov eax, 1                  ; write(fd, BUF, len)
        mov rdi, rbx
        mov esi, BUF
        mov rdx, r14
        syscall
        mov eax, 3                  ; close(fd)
        mov rdi, rbx
        syscall
        jmp mainloop

quit:
        call raw_off
        mov esi, CLR                ; clear screen on the way out
        mov edx, CLRLEN
        call wr
        mov eax, 60
        xor edi, edi
        syscall

; ---- redraw ----
draw:
        mov esi, CLR
        mov edx, CLRLEN
        call wr
        mov esi, BUF                ; head: BUF[0 .. cur]
        mov rdx, r15
        call wr
        mov esi, SAVC               ; DECSC (save cursor)
        mov edx, 2
        call wr
        mov esi, BUF                ; tail: BUF[cur .. len]
        add rsi, r15
        mov rdx, r14
        sub rdx, r15
        call wr
        mov esi, RESC               ; DECRC (restore cursor)
        mov edx, 2
        call wr
        ret

; write(1, rsi, rdx)
wr:
        mov eax, 1
        mov edi, 1
        syscall
        ret

; read one byte into KEY, return it in AL
rd1:
        xor eax, eax                ; read
        xor edi, edi                ; fd 0
        mov esi, KEY
        mov edx, 1
        syscall
        mov al, [KEY]
        ret

raw_on:
        mov eax, 16                 ; ioctl(0, TCGETS, ORIG)
        xor edi, edi
        mov esi, 0x5401
        mov edx, ORIG
        syscall
        mov esi, ORIG               ; copy ORIG -> RAW (60 bytes)
        mov edi, RAW
        mov ecx, 60
        rep movsb
        and dword [RAW], ~0x400     ; iflag: clear IXON
        and dword [RAW+12], ~0x800B ; lflag: clear ECHO|ICANON|ISIG|IEXTEN
        mov byte [RAW+22], 0        ; c_cc[VTIME] = 0
        mov byte [RAW+23], 1        ; c_cc[VMIN]  = 1
        mov eax, 16                 ; ioctl(0, TCSETS, RAW)
        xor edi, edi
        mov esi, 0x5402
        mov edx, RAW
        syscall
        ret

raw_off:
        mov eax, 16                 ; ioctl(0, TCSETS, ORIG)
        xor edi, edi
        mov esi, 0x5402
        mov edx, ORIG
        syscall
        ret

; ---- read-only data ----
CLR:    db 0x1b,"[2J",0x1b,"[H"
CLRLEN  equ $ - CLR
SAVC:   db 0x1b,"7"
RESC:   db 0x1b,"8"
DEFPATH: db "untitled.txt",0

FILEEND:

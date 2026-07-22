; bootpad - a text editor in a 512-byte boot sector.
; No OS, no filesystem, no runtime. Boots on bare metal via BIOS.
;   type       printable chars      Enter  newline
;   Backspace  delete               Ctrl-S save to disk (persists across reboot)
; Text is stored in sectors 2.. of the boot medium and reloaded on boot.
bits 16
org 0x7c00

BUF     equ 0x7e00      ; edit buffer, right after the boot sector in RAM
SECTS   equ 4           ; sectors persisted = 2 KiB of text

start:
        xor ax, ax
        mov ds, ax
        mov es, ax
        mov ss, ax
        mov sp, 0x7c00
        mov [drive], dl         ; BIOS leaves boot drive in DL

        mov ax, 0x0003          ; 80x25 text mode (also clears the screen)
        int 0x10

        ; ---- load previously saved text from disk into BUF ----
        mov ah, 0x02            ; read sectors
        mov al, SECTS
        mov ch, 0               ; cylinder 0
        mov cl, 2               ; start at sector 2 (sector 1 is us)
        mov dh, 0               ; head 0
        mov dl, [drive]
        mov bx, BUF
        int 0x13                ; errors ignored (blank disk on first boot)

        ; ---- print it, stop at the first NUL, leave DI at the end ----
        mov di, BUF
.show:  mov al, [di]
        test al, al
        jz edit
        call putc
        inc di
        jmp .show

edit:
        xor ah, ah
        int 0x16                ; AL=ASCII, AH=scancode
        cmp al, 0x13            ; Ctrl-S
        je save
        cmp al, 0x08            ; Backspace
        je bs
        cmp al, 0x0d            ; Enter
        je nl
        cmp al, 0x20            ; ignore other control keys
        jb edit
        mov [di], al            ; store + echo printable
        inc di
        call putc
        jmp edit

nl:     mov byte [di], 0x0d     ; store CR; putc expands CR->CRLF on echo & reload
        inc di
        mov al, 0x0d
        call putc
        jmp edit

bs:     cmp di, BUF
        jbe edit                ; nothing to erase
        dec di
        mov al, 0x08
        call putc
        mov al, 0x20
        call putc
        mov al, 0x08
        call putc
        jmp edit

save:   mov byte [di], 0        ; terminate so reload stops here
        mov ah, 0x03            ; write sectors
        mov al, SECTS
        mov ch, 0
        mov cl, 2
        mov dh, 0
        mov dl, [drive]
        mov bx, BUF
        int 0x13
        mov al, 0x07            ; beep = saved
        call putc
        jmp edit

; teletype AL; a CR is expanded to CR+LF so lines start at column 0
putc:
        push ax
        push bx
        mov ah, 0x0e
        mov bx, 0x0007
        int 0x10
        cmp al, 0x0d
        jne .done
        mov al, 0x0a
        int 0x10
.done:  pop bx
        pop ax
        ret

drive:  db 0

        times 510-($-$$) db 0
        dw 0xaa55

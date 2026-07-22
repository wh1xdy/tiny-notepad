/* tn - tiny notepad
 * A full-screen terminal text editor with zero libc: freestanding C on top of
 * raw x86-64 Linux syscalls. Open, edit, save. That's the whole job.
 *
 *   arrows  move        Ctrl-S  save        Ctrl-Q  quit        Backspace  delete
 *
 * Build: see Makefile (-nostdlib -Os, then strip). Runtime footprint is a
 * couple hundred bytes of code plus a 1 MiB edit buffer that lives in .bss and
 * costs nothing on disk.
 */

/* ---- syscalls -------------------------------------------------------------*/
static long sys(long n, long a, long b, long c) {
	long r;
	__asm__ volatile("syscall"
	                 : "=a"(r)
	                 : "a"(n), "D"(a), "S"(b), "d"(c)
	                 : "rcx", "r11", "memory");
	return r;
}
#define SYS_read 0
#define SYS_write 1
#define SYS_open 2
#define SYS_close 3
#define SYS_ioctl 16
#define SYS_exit 60

/* ---- terminal -------------------------------------------------------------*/
struct termios {
	unsigned int iflag, oflag, cflag, lflag;
	unsigned char line, cc[19];
};
#define TCGETS 0x5401
#define TCSETS 0x5402

static struct termios orig;

static void raw_on(void) {
	sys(SYS_ioctl, 0, TCGETS, (long)&orig);
	struct termios t = orig;
	t.iflag &= ~0x400u;             /* IXON  - let Ctrl-S/Q through          */
	t.lflag &= ~(0x8u | 0x2u | 0x1u | 0x8000u); /* ECHO ICANON ISIG IEXTEN   */
	t.cc[6] = 1;                    /* VMIN  = 1                             */
	t.cc[5] = 0;                    /* VTIME = 0                             */
	sys(SYS_ioctl, 0, TCSETS, (long)&t);
}
static void raw_off(void) { sys(SYS_ioctl, 0, TCSETS, (long)&orig); }

/* ---- tiny helpers ---------------------------------------------------------*/
static void puts_n(const char *s, long n) { sys(SYS_write, 1, (long)s, n); }
static long slen(const char *s) {
	const char *p = s;
	while (*p) p++;
	return p - s;
}
static void puts_s(const char *s) { puts_n(s, slen(s)); }

/* write a decimal number, no libc */
static void put_num(unsigned n) {
	char b[10];
	int i = 10;
	b[--i] = 0;
	if (!n) b[--i] = '0';
	while (n) {
		b[--i] = '0' + n % 10;
		n /= 10;
	}
	puts_s(b + i);
}

/* ---- editor state ---------------------------------------------------------*/
static char buf[1 << 20]; /* 1 MiB, lives in .bss - free on disk */
static long len;          /* bytes used                          */
static long cur;          /* cursor offset into buf              */

/* Redraw the whole screen and park the hardware cursor where `cur` points. */
static void draw(void) {
	puts_s("\x1b[2J\x1b[H"); /* clear + home */
	puts_n(buf, len);
	/* derive row/col from the newlines before the cursor */
	unsigned row = 1, col = 1;
	for (long i = 0; i < cur; i++) {
		if (buf[i] == '\n') {
			row++;
			col = 1;
		} else {
			col++;
		}
	}
	puts_s("\x1b[");
	put_num(row);
	puts_s(";");
	put_num(col);
	puts_s("H");
}

static void insert(char c) {
	if (len >= (long)sizeof buf) return;
	for (long i = len; i > cur; i--) buf[i] = buf[i - 1];
	buf[cur++] = c;
	len++;
}
static void del_back(void) {
	if (cur == 0) return;
	for (long i = cur - 1; i < len - 1; i++) buf[i] = buf[i + 1];
	cur--;
	len--;
}

/* column of the cursor within its current line */
static long col_of(long p) {
	long c = 0;
	while (p - c > 0 && buf[p - c - 1] != '\n') c++;
	return c;
}
/* start offset of the line `p` sits on */
static long line_start(long p) { return p - col_of(p); }

static void move_up(void) {
	long c = col_of(cur);
	long ls = line_start(cur);
	if (ls == 0) return;
	long ps = line_start(ls - 1); /* start of previous line */
	long plen = ls - 1 - ps;      /* length of previous line */
	cur = ps + (c < plen ? c : plen);
}
static void move_down(void) {
	long c = col_of(cur);
	long ls = line_start(cur);
	long le = ls;
	while (le < len && buf[le] != '\n') le++;
	if (le >= len) return;         /* already on last line */
	long ns = le + 1;              /* next line start */
	long ne = ns;
	while (ne < len && buf[ne] != '\n') ne++;
	long nlen = ne - ns;
	cur = ns + (c < nlen ? c : nlen);
}

static void save(const char *path) {
	long fd = sys(SYS_open, (long)path, 1 | 0100 | 01000, 0644); /* WRONLY|CREAT|TRUNC */
	if (fd < 0) return;
	sys(SYS_write, fd, (long)buf, len);
	sys(SYS_close, fd, 0, 0);
}

static void quit(void) {
	raw_off();
	puts_s("\x1b[2J\x1b[H");
	sys(SYS_exit, 0, 0, 0);
}

/* ---- entry ----------------------------------------------------------------*/
__asm__(".globl _start\n_start:\n\tmov %rsp,%rdi\n\tand $-16,%rsp\n\tcall start_c\n");

void start_c(long *sp) {
	long argc = sp[0];
	char **argv = (char **)(sp + 1);
	const char *path = argc > 1 ? argv[1] : "untitled.txt";

	/* load the file if it exists */
	long fd = sys(SYS_open, (long)path, 0, 0); /* O_RDONLY */
	if (fd >= 0) {
		len = sys(SYS_read, fd, (long)buf, sizeof buf);
		if (len < 0) len = 0;
		sys(SYS_close, fd, 0, 0);
	}

	raw_on();
	for (;;) {
		draw();
		char c;
		if (sys(SYS_read, 0, (long)&c, 1) != 1) continue;
		if (c == 17) quit();               /* Ctrl-Q */
		else if (c == 19) save(path);      /* Ctrl-S */
		else if (c == 127 || c == 8) del_back();
		else if (c == '\r' || c == '\n') insert('\n');
		else if (c == 27) {                /* escape sequence: arrows */
			char a, b;
			if (sys(SYS_read, 0, (long)&a, 1) != 1) continue;
			if (sys(SYS_read, 0, (long)&b, 1) != 1) continue;
			if (a == '[') {
				if (b == 'A') move_up();
				else if (b == 'B') move_down();
				else if (b == 'C') { if (cur < len) cur++; }
				else if (b == 'D') { if (cur > 0) cur--; }
			}
		} else if (c >= 32) insert(c);     /* printable */
	}
}

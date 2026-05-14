# luaposixcli

POSIX utilities and a POSIX shell implemented in Lua 5.4 using lpeg and luaposix.

## Building

```
meson setup build
ninja -C build
meson test -C build
```

## Quick Start

```
./run.sh
```

Builds, installs to a temp directory, and drops you into the shell with all utilities on PATH.

## Shell

See [sh/README.md](sh/README.md) for the shell's feature list.

## Implemented Utilities

| Utility | Description |
|---------|-------------|
| `basename` | strip directory and suffix |
| `awk` | pattern scanning and processing language |
| `bc` | arbitrary-precision arithmetic language |
| `cal` | display calendar |
| `cat` | concatenate files |
| `chgrp` | change file group |
| `chmod` | change file mode |
| `chown` | change file owner |
| `cmp` | compare two files |
| `comm` | compare sorted files |
| `cp` | copy files |
| `cut` | extract fields/columns |
| `date` | display date and time |
| `dd` | convert and copy files |
| `df` | report filesystem disk space |
| `diff` | compare files line by line |
| `dirname` | extract directory |
| `du` | report disk usage |
| `echo` | write arguments |
| `env` | print environment |
| `expand` | convert tabs to spaces |
| `expr` | evaluate expressions |
| `false` | exit with status 1 |
| `find` | search for files in directory hierarchy |
| `fold` | wrap lines at width |
| `grep` | search files for patterns |
| `head` | print first N lines |
| `id` | print user/group IDs |
| `kill` | send signal to process |
| `link` | create hard link |
| `ln` | create hard/symbolic links |
| `logger` | write to syslog |
| `logname` | print login name |
| `ls` | list directory contents (-1, -a, -l, -R) |
| `mkdir` | create directories |
| `mkfifo` | create FIFO special file |
| `mktemp` | create temporary file/directory |
| `mv` | move/rename files |
| `nice` | run with altered priority |
| `nohup` | run immune to hangups |
| `od` | octal dump |
| `paste` | merge lines from files |
| `patch` | apply diff patches |
| `pax` | portable archive exchange |
| `pr` | paginate files |
| `printf` | format and print |
| `ps` | report process status |
| `pwd` | print working directory |
| `renice` | alter process priority |
| `rm` | remove files |
| `rmdir` | remove empty directories |
| `sed` | stream editor |
| `seq` | print number sequences |
| `sh` | POSIX shell |
| `sleep` | pause execution |
| `sort` | sort lines |
| `tail` | print last N lines |
| `tee` | copy stdin to stdout and files |
| `tar` | tape archive (create, extract, list) |
| `time` | measure command duration |
| `touch` | create file / update timestamps |
| `tr` | translate characters |
| `true` | exit with status 0 |
| `tty` | print terminal name |
| `uname` | print system information |
| `uniq` | filter duplicate lines |
| `unexpand` | convert spaces to tabs |
| `unlink` | remove a file |
| `wc` | count lines, words, bytes |
| `xargs` | build command lines from stdin |
| `yes` | repeatedly output a string |

## Not Yet Implemented

The following POSIX utilities are not yet implemented:

**Text processing:** (none remaining)

**File operations:** (none remaining)

**Diff/patch:** (none remaining)

**Editors:** `vi`, `ed`, `ex`

**Build tools:** `make`, `m4`, `lex`, `yacc`, `c99`

**Other:** `read`, `getopts`

## Architecture

- Each utility is a standalone Lua script in its own subdirectory
- The shell (`sh/`) is split into modules: lexer (lpeg), expander, executor, environment, test builtin, compound commands
- `notposix.c` is a small C module exposing syscalls not available in luaposix (currently `getpriority`/`setpriority`)
- All system interaction uses luaposix — no Lua `io` library in the shell
- Build system is meson; tests run via `meson test`

## License

ISC License — Copyright 2026 Nick Owens <mischief@offblast.org>

See [LICENSE](LICENSE) for details.

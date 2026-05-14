# sh

A POSIX shell implemented in Lua using lpeg and luaposix.

## Implemented

### Commands and Pipelines
- Simple commands with arguments
- Pipelines: `cmd1 | cmd2 | cmd3`
- Sequential lists: `cmd1; cmd2`
- AND lists: `cmd1 && cmd2`
- OR lists: `cmd1 || cmd2`
- Asynchronous lists: `cmd &`
- Line continuation with `\<newline>`

### Compound Commands
- `if/then/elif/else/fi`
- `while/do/done`
- `until/do/done`
- `for name in wordlist; do ...; done`
- Nesting of all compound commands
- Multiline compound commands (interactive and script)

### Quoting
- Single quotes: `'literal'`
- Double quotes: `"with $expansion"`
- Backslash escapes: `\ `

### Expansion
- Variable expansion: `$VAR`, `${VAR}`
- Command substitution: `$(cmd)`, `` `cmd` ``
- Special parameters: `$?`, `$$`, `$0`, `$#`, `$@`, `$*`, `$!`, `$-`

### Redirection
- Output: `> file`, `>> file`
- Input: `< file`
- File descriptor: `2> file`, `>&2`, `<&N`
- Fd close: `>&-`, `<&-`

### Built-in Commands
- `:` (noop)
- `echo`
- `true`, `false`
- `test` / `[`
- `cd`
- `exit`
- `exec`
- `export`
- `unset`
- `set` (`-x`, `+x`)
- `umask`
- `wait`
- `break`, `continue`

### Other Features
- Script file execution: `sh script.sh`
- `-c` option: `sh -c 'command'`
- Interactive prompt with `PS1` (parameter-expanded)
- Command tracing with `set -x` and `PS4`
- Tab completion for filenames (interactive)
- `$0` set correctly for scripts and `-c` mode

## Not Yet Implemented

### Expansion
- Tilde expansion (`~`, `~user`)
- Arithmetic expansion (`$((...))`)
- Parameter expansion modifiers (`${var:-default}`, `${#var}`, `${var%pat}`, etc.)
- Field splitting (IFS)
- Pathname/glob expansion (`*`, `?`, `[...]`)

### Compound Commands
- `case/esac`
- Subshell grouping: `( list )`
- Brace grouping: `{ list; }`

### Other
- Function definitions
- Here-documents (`<<EOF`)
- Signal handling / `trap`
- `.` (source/dot)
- `eval`
- `read`
- `shift`
- `readonly`
- `return`
- `getopts`
- Alias substitution
- `set -e` (errexit)
- Job control (`fg`, `bg`, `jobs`)
- History

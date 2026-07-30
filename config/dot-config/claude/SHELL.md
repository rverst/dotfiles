# Shell output policy

A pipe filters before Claude Code sees anything. A `tail -20` that shows the
wrong 20 lines cannot be widened — the rest never existed, and the only recovery
is re-running the command. That is slow for builds and wrong for anything with
side effects.

**Capture first, filter second**, whenever a command is slow, hits the network,
has side effects, or may produce more than a screenful:

```bash
D="${TMPDIR:-/tmp}/claude"; mkdir -p "$D"
npm test >"$D/test.log" 2>&1; echo "exit=$?"; tail -20 "$D/test.log"
```

Then widen against the file — `grep -n`, `sed -n '120,180p'`, `wc -l` — instead
of paying for the command a second time.

- Always redirect `2>&1`. The line you need is usually on stderr.
- Always echo the exit code. `cmd >f; tail f` returns *tail's* status, so a
  failing test suite looks like it passed.
- Run fast, local, read-only commands (`ls`, `git status`, `cat`) directly. This
  is about not repeating expensive work, not about avoiding pipes.
- An `rtk`-rewritten command stores rtk's *filtered* view. Use `rtk proxy <cmd>`
  when the raw output matters.

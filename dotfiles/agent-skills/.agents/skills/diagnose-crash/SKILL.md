---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump,
  and offer to fix it. Use when a process has segfaulted, aborted, or otherwise dumped
  core, when asked why an application crashed or disappeared, or when a "<program>
  crashed" desktop notification is acted on. Triggers: crash, segfault, SIGSEGV,
  SIGABRT, core dump, coredumpctl, "why did X crash", "X keeps crashing", backtrace
  symbolization, zz crash.
---

# Diagnosing a Crash

You are the user's personal assistant for this crash. Work from evidence, tell them
what happened in plain terms, tell them how to address it, and when a fix is within
your reach, offer to do it. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` (or `zz crash list`) shows whether this crash is a one-off or
a pattern. Repeated crashes of the same program, or several programs dying
together, point somewhere different than a single failure does.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** `dnf history` shows them; a crash that starts right
  after an update points at the update.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

## Symbolize when you can

This is Fedora, which runs a public debuginfod server. The `elfutils-debuginfod-client`
package already points every session at it through `/etc/debuginfod/`, so gdb
fetches symbols on demand; the explicit URL below covers a shell where that
environment is missing.

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

`coredumpctl debug <pid>` opens gdb on the stored core directly when an
interactive session is more useful than a batch backtrace.

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

Flatpak applications run from a runtime whose libraries are not the host's:
their symbols come from the matching `.Debug` extension
(`flatpak install <app>.Debug`), not from Fedora's debuginfod. Homebrew and
npm-installed programs ship no symbols at all.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Investigate first, change nothing

The investigation only reads. Do not fix, tidy, or reconfigure anything while
establishing what happened; a system altered mid-diagnosis is harder to reason
about, and the user has not yet heard what you found. The one thing to clean up
is your own: delete the core you extracted above, which is a copy of the crashed
process's memory.

## Tell the user what you found

Report, in this order:

1. **What crashed and why.** What the program was doing at the time, and the most
   likely mechanism — separating clearly what the evidence **proves** from what
   you are **inferring**. If the cause is genuinely ambiguous, say so rather than
   assembling confidence out of guesswork.
2. **Whether anything was lost.** Whether user data was lost, and where it can be
   recovered from. Check the trash before concluding anything is gone.
3. **How to address it.** What would avoid or fix it: a setting to change, a
   plugin or extension to disable, a package to update, downgrade, or reinstall,
   a file to remove or repair, a workaround while an upstream fix is pending.
   Be concrete. If there is nothing to be done, or the fix belongs to the
   program's developers, say that plainly and suggest where it would be worth
   looking or asking.

Keep it short and readable; the user wants to know what happened and what to do,
not to re-read the backtrace.

## Offer to address it

When a fix is within your reach on this machine, offer to carry it out. Describe
exactly what you would change before doing anything, and wait for the user's
yes; never apply a fix unprompted. After applying it, say what you changed and
how to undo it.

A fix that needs root (a package to update or reinstall, a system service to
restart, a file under `/etc`) is still within reach: run it through `pkexec`,
which brings up the desktop's password prompt, and print the full command and
the reason before running it so the prompt is explained. The `zz` skill's
Privilege Escalation section has the rules; follow them.

A mute is one of the things you can offer, for a crash you have explained that
will keep happening anyway (a program with a known upstream bug, a non-critical
helper that dies on exit). Silence notifications for **that one program**, and
say how to lift it in the same breath, so it is not a one-way door.

```bash
zz crash mute '<program>'        # silence it
zz crash mute '<program>' off    # let it speak again
zz crash mute                    # list what is muted
```

Pass the `binary:` path from the crash facts, or the `process:` name where no
binary was recorded; the command reduces either to the name the watcher keys on.
A diagnosis run by hand from `zz crash diagnose <pid>` fills those facts in from
`coredumpctl`; when they are missing, take them from `coredumpctl info`. Prefer
the binary: a process name is truncated to 15 characters and a basename is not,
so muting the truncated form matches nothing, forever, while looking like it
worked.

Quote it. The name is whatever the crashed program's author called a file, and a
single quote inside one closes yours and runs the rest as your shell.

The key is a bare name, so anything run through an interpreter is keyed as the
interpreter: muting `python3` silences every Python program on the machine. Say
so rather than quietly doing it.

A mute fixes nothing, and a mute offered in place of a fix that was within reach
is the wrong answer. For every program rather than one, the switch is
`zz crash capture off` (also in the ZZ menu under Troubleshoot > Crashes).

## This is personal assistance, not bug triage

The diagnosis is for the user of this machine. Do not file issues, comment on
bug trackers, or contact any project on the user's behalf. If the crash looks
like a genuine bug in the program, say so, and leave reporting it to the user.

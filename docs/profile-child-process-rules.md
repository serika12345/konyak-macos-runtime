# Profile Child-Process Rules

Konyak's macOS Wine runtime accepts validated, declarative child-process
argument rules through `KONYAK_CHILD_PROCESS_RULES`. The parent Konyak process
sets the variable only for an executable with a bound compatibility profile.
Program settings cannot override this reserved variable, and the process
runner clears any inherited value when a request has no validated rules.

## Version 1 Protocol

Each line contains one executable suffix and one argument:

```text
<executable suffix><TAB><argument><LF>
```

The final line does not require a trailing line feed. Matching is
ASCII case-insensitive and compares the suffix with the child application
path. Wine appends the argument only when the command line does not already
contain that token.

Profile validation enforces the runtime limits before launch:

- at most 64 arguments across all rules
- at most 65,535 UTF-16 code units after serialization
- executable suffixes are 1 to 1,024 printable ASCII code units
- arguments are 1 to 8,192 code units and are unquoted tokens containing no
  NUL, space, tab, line break, or double quote

Version 1 deliberately accepts single command-line tokens rather than arbitrary
command fragments. Supporting quoted Windows argv values requires a later
protocol version with matching encoder and parser behavior.

## Runtime Boundary

The hook runs in Wine's Unix `ntdll!NtCreateUserProcess` implementation. This
is the final common process-creation boundary before Wine sends the startup
parameters to wineserver, including for 32-bit parents under Wine32-on-64.
Konyak does not patch the PE `kernelbase.dll`, select applications, load a
profile database, execute a shell or script, or load external profile code.
The runtime receives only the validated serialized rules.

The command line is replaced only for the duration of `NtCreateUserProcess` and
the original `RTL_USER_PROCESS_PARAMETERS.CommandLine` is restored before the
call returns. A rule is ignored if the resulting Windows command line would not
fit in `UNICODE_STRING`.

This contract is currently implemented only by Konyak's macOS Wine runtime.
The Linux request builder does not propagate the variable, and the Linux Wine
runtime does not include the hook.

## Verification

`scripts/check-wine32on64-runtime.zsh` verifies that the host Unix `ntdll.so`
artifact contains the compiled contract marker.
`scripts/smoke-wine32on64-launch.zsh` then performs real nested `CreateProcess`
launches with x86_64 and i386 parents. It verifies case-insensitive suffix
matching, non-matching isolation, exactly-once argument insertion, and the
32-bit-parent to 64-bit-child path.

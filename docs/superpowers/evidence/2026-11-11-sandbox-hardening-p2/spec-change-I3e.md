Task: 2026-11-11-sandbox-hardening
Class: phase

# Proposed spec change S-4: I3e narrowed to the host sockets a sandbox is given

**Status: applied.** Approved by the user on 2026-11-12 with the phase 2 plan, option
(a) ("a"); changes 1 and 2 applied to the spec as worded below.
Raised by the phase 2 planner (Ola) as question Q2; text by the spec's author (Hania,
`author-answers.md` in this directory, Q1 and Q2). The phase 2 plan is written on
option (a) and names this file as its one open decision. Revised after the plan review
(`plan-review.md`, I3 and M2): change 1 adds a second residual-risk line, and change 2
is part of option (a).

## Why

I3e reads: "By default a sandbox reaches no host daemon that acts on a client's
request." It was written from finding C2 (the host's sound server), and phase 2, the
phase that establishes it, names only sound. Read literally it is wider: every
display mode but `none` talks to a server on the host (the host's compositor under
`wayland`, which `auto` picks on a host with a Wayland session; a server the host
starts for the sandbox under `xpra` and `nested`; evidence S15 and S16), so no phase
as planned establishes it. What the display paths share with the host is M2, phase
10. The wording is the defect, not the phase.

## Change 1 (the decision): replace I3e

In "Invariants", replace the bullet **I3e** with:

> - **I3e** By default the toolchain gives a sandbox no host daemon's socket but its
>   display's, so the host's sound server, a daemon that acts on a client's request,
>   is out of its reach. The display server of the chosen mode (the host's compositor
>   under `wayland`, a server the host starts for the sandbox under `xpra` and
>   `nested`) is outside this invariant: what it shares with the host is M2, phase 10,
>   and `--display=host`, which shares the host's own X server, is a mode the
>   toolchain names unsafe. A sandbox the user opted into host audio is outside this
>   invariant, and the toolchain says so when the option is given. Phase 2.

In "Residual risk the user accepts with this spec", add after the bullet that begins
"A sandbox the user opted into host audio":

> - The display server a sandbox talks to by default: until phase 10 what M2 names,
>   and after it whatever that server does on a client's request, which is the
>   server's own code and not this toolchain's.
> - A network service the host offers on the address by which every sandbox reaches
>   the host (`host.docker.internal`, given on purpose so that a sandbox can use the
>   host's services): no phase takes that address away, and what such a service does
>   on a client's request is its own code and not this toolchain's.

Why the second line: the old words "reaches no host daemon" also covered a host
service listening on that address, which every sandbox's compose file maps to the host
(`create-ai-sandbox.sh`, the `extra_hosts` entry of the compose writer). The new I3e
speaks of sockets the toolchain gives and leaves such services out, so the spec says
so as a residual risk. No such service has been shown and no phase was given one; it is
not a deferred entry because no failure a user can reach has been shown.

The check the plan adds for it: O7 (a default sandbox's compose file binds no host
socket but the display's), with the search S16 in this directory's evidence file.

## Change 2 (part of option (a), wording only): the phase 2 block

The spec's author settled from the spec that an `--audio` given after phase 2 is
remembered like the other options of creation (Q1, answer (a)). The plan's O4 (a bare
run after `--audio` keeps audio on) is checked against this reading, so the spec's
sentence must state it rather than leave it to be read out. In "Phase 2", replace
"a re-creation without an explicit `--audio` turns audio off and says so." with:

> a re-creation without an explicit `--audio` turns such a setting off and says so. A
> request made with `--audio` from this phase on is remembered like the other options
> of creation, until `--no-audio`.

## Options for the user

- **(a) Approve changes 1 and 2** (recommended). Phase 2 goes ahead as planned: sound
  only, plus O7. The spec then says in its residual risks that a sandbox still talks
  to its display server and still reaches network services the host offers on
  `host.docker.internal`.
- **(b) Keep I3e as worded.** Phase 2 must then also take the display servers, and the
  sandbox's route to services on the host, out of the default. For the display that is
  in effect `--display=none` by default: windows of programs in a sandbox no longer
  appear unless asked for. That changes what the user sees and does, and is re-planned
  as a different phase goal.

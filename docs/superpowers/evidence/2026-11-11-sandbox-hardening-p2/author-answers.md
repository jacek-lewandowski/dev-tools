Task: 2026-11-11-sandbox-hardening
Class: phase

# Answers of the spec's author to the phase 2 planner

Hania (planner 1, the spec's author slot), 2026-11-12. Spec at `0c4c10f`. Read: the
phase 2 plan's "Questions for the spec's author" with PA1, PA7, O4 and the data block;
evidence S2, S15 and S16; the spec's I3e, I4, I6, U1, C-MODULES, the phase 2 and phase
10 blocks and the residual risks; the user's decisions (U1); findings C2 and M2 by key;
`create-ai-sandbox.sh` around the stored display mode, the `auto` mode and the compose
writer's `extra_hosts` entry.

Revised the same day after the plan review (`plan-review.md`): I3 (Q2, a residual-risk
line for host network services), M2 (Q1, the wording is part of option (a)) and M6
(Q2, the claim about host sockets rests on S16).

## Q1: is an `--audio` given after phase 2 remembered?

**Kind: settled by the spec. Answer (a), the plan's PA1.**

- U1 is "off by default, on per sandbox": a choice that belongs to the sandbox, not to
  one run.
- C-MODULES gives `create.d/options.sh` "options remembered in `.env`". That is the
  convention for every option of creation, and the spec makes no exception for audio.
- The subject of the phase 2 sentence is "A setting remembered from the time when on
  was the default". The clause after the colon ("a re-creation without an explicit
  `--audio` turns audio off and says so") says what happens to such a setting. It does
  not say what happens to a request made after the phase. The old value cannot be told
  apart from a real request because both cases wrote the same value (evidence S2). A
  value written only by `--audio` from this phase on can be told apart, so the reason
  for the sentence does not reach it.
- The tree keeps a deliberate choice that loosens isolation in the same way.
  `create-ai-sandbox.sh` keeps a stored display mode when a run gives none, so that a
  bare run does not "undo a deliberate --display=host" (its comment above the
  stored-mode block).
- I4 and I6: a bare re-creation, the form of phase 1's batch B2, does not change an
  explicit choice. O3's warning on every run that keeps the request is what tells the
  user it is still on.

The answer needs no change of meaning. The sentence can be made unambiguous without
changing it, and goes with the spec change of Q2. In the phase 2 block,
replace "a re-creation without an explicit `--audio` turns audio off and says so."
with:

> a re-creation without an explicit `--audio` turns such a setting off and says so. A
> request made with `--audio` from this phase on is remembered like the other options
> of creation, until `--no-audio`.

The plan's O4 (a bare run after `--audio` keeps audio on) is checked against this
reading, so the wording is part of option (a) of Q2 (`spec-change-I3e.md`, change 2)
and not proposed on its own.

## Q2: does I3e reach the display servers?

**Kind: a gap that needs a change of the spec's text. Recommended: (a), narrow I3e.**

I3e was written from finding C2: the host's sound server, reached by default, does
what a client asks with the user's rights. It is "Phase 2", and the phase 2 block names
only sound. The words "no host daemon that acts on a client's request" are wider than
that. By default a sandbox also talks to a display server on the host. Under
`wayland`, which `auto` picks on a host with a Wayland session, that is the host's
compositor. Under `xpra` and `nested` it is a server the host starts for the sandbox
(evidence S15). Read literally, phase 2 cannot establish I3e. The spec's own placement
also points to the narrow reading:
- what the display paths share with the host (the clipboard, unmarked windows) is M2,
  phase 10; no phase is given the display servers' own code;
- `auto` never picks `host`, which the tree already calls unsafe.

So the wording is the defect, not the phase.

**Proposed text.** In "Invariants", replace the bullet **I3e** with:

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

**What the new wording claims, checked against the tree.** By default, after phase 2,
the only host socket bound into a sandbox is the display's. The plan evidence's search
S16 (`2026-11-11-sandbox-hardening-p2-plan.md` in this directory, 29 hits on `dd0146a`
and on phase 1's `7156737`, each read) finds two kinds of host-side socket bind: the
display mode's (the compositor's socket, or the per-sandbox X socket directory, or
under `host` the host's own) and the sound socket, which phase 2 removes. Its other
hits are inside the image or the container (among them the inner Docker's socket under
`--with-docker`), and the compose writer's remaining bind lines name directories and
files, no runtime directory and no socket. The plan's O7 turns this into its check:
the compose file of a default sandbox binds no host socket but the display's.

**Also narrowed, said so that it is not lost.** The old words "reaches no host daemon"
also covered a host service listening on the address by which a sandbox reaches the
host: every sandbox's compose file maps `host.docker.internal` to the host
(`create-ai-sandbox.sh`, the compose writer's `extra_hosts` entry, given on purpose so
that a sandbox can use the host's services). The new wording speaks of sockets the
toolchain gives and leaves such services out, so the proposed text adds the second
residual-risk line above to say so. No such service has been shown and no phase was
ever given one; it is not a deferred entry because no failure a user can reach has
been shown.

**Alternative (b), the user's if they decline (a).** Phase 2 also takes the display
servers out of the default. Every display mode but `none` talks to a server on the
host, so in effect the default display becomes `none`. That is an incompatible change of
what the user sees (GUI apps in a sandbox no longer appear unless asked for), so it is
not the author's to choose.

**For the user, one sentence.** The rule "by default a sandbox reaches no host
service" was written for the sound server; a sandbox's windows also go to a display
program on the host and a sandbox can still reach the host's network services at
`host.docker.internal`, so the rule is narrowed to the sockets the toolchain gives,
both are named as accepted risks, and the display's clipboard and window marking stay
with phase 10 as already planned.

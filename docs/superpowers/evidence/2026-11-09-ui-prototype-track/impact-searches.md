$ grep -rn -w ... rules roles skills README.md (search 1, after T1-T3)
rules/global.md:109:  spec reviews, scouts and writers on the cheaper tier, command runners on the
rules/global.md:284:| Spec author, phase planner, brief writer, reviewer, runner, scout, writer, prototyper | Retired at the next stop; a fresh agent in the same slot carries on from the files, under the same name. No note, no handover, no compaction. | Not reached: 250k is their ceiling. | The lead, from the token count at each stop. |
roles/README.md:20:  one tier pins it (runner `haiku`; implementer, prototyper, scout and writer

$ grep -n 'Writer' rules/global.md
181:  - Writer: one per text task, alive until its output is accepted. A
202:  - Writer: Basia, Michał, Dorota.

$ grep -rn 'command runners on the cheapest' rules roles
(rc 1)

$ grep -rn 'Tosia' rules roles
rules/global.md:203:  - Prototyper: Tosia, Franek, Julka.

$ grep -rn -i -w prototyper rules roles
rules/global.md:183:  - Prototyper: one per variant of a prototype round, given the prototype
rules/global.md:203:  - Prototyper: Tosia, Franek, Julka.
rules/global.md:284:| Spec author, phase planner, brief writer, reviewer, runner, scout, writer, prototyper | Retired at the next stop; a fresh agent in the same slot carries on from the files, under the same name. No note, no handover, no compaction. | Not reached: 250k is their ceiling. | The lead, from the token count at each stop. |
roles/prototyper.md:2:name: prototyper
roles/prototyper.md:37:- When you replace a retired prototyper in the same slot, start from the
roles/README.md:20:  one tier pins it (runner `haiku`; implementer, prototyper, scout and writer

$ head -5 roles/prototyper.md
---
name: prototyper
description: Builds one throw-away variant of a visual prototype from a prototype sheet, for the user to judge by eye; changes no product file, writes no test and commits nothing.
model: sonnet
---

$ grep -rn AGENT-MARK ui-prototype-track
(rc 1)

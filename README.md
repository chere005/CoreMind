# CoreMind

Feel free to clone it and copy the canon into your own apps, etc. This repo ships nothing itself.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

The canonical home of everything the Mind-suite apps share, and the check that
keeps their copies honest. It holds the shared bytes once, says exactly who
mirrors them, and proves the mirrors match.

**This is a reference repo, not a runtime dependency.** Nothing imports it,
nothing links against it, and it ships to no platform. The suite's doctrine is
that apps CLONE shared code and CHECKS keep the clones in lockstep, so what
lives here is canonical bytes, a manifest per consumer, and the drift check —
not a published package. Nothing here is for an end user: the audience is
whoever, person or agent, is changing a file that more than one app carries.

Its consumers are [CalMind](https://github.com/chere005/CalMind),
[ChefMind](https://github.com/chere005/ChefMind),
[MyCalMind](https://github.com/chere005/MyCalMind) and
[AcctMind](https://github.com/chere005/AcctMind), with
[WriteMind](https://github.com/chere005/WriteMind) in the suite for its release
lane only. They are expected as sibling checkouts of this one; `MIND_DIR`
overrides the parent directory.

## Running it

Node and npm; the lanes and the check are plain `/bin/sh`.

```sh
npm install
npm test          # the canon core suite itself: 634 tests, run HERE
npm run typecheck
npm run check     # every consumer with a checkout, against canon
```

CoreMind also owns the suite's release ORDER: `npm run dtp -- all` deploys,
tags and pushes every repo, core first, and `npm run tdtp -- all` puts each
repo's full test run in front of that.

## More

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — the map of the tree, the manifests
  and their modes, the deploy graph, how each platform ships, and the reasons
  each of them is the way it is.
- **[AGENTS.md](AGENTS.md)** — how to work in this repo: the standing rules and
  the traps.
- [LICENSE](LICENSE)

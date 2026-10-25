# CoreMind

Feel free to clone it and copy the canon into your own apps, etc. This repo ships nothing itself.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

The canonical home of everything the Mind-suite apps share, and the check
that keeps their copies honest. The suite's doctrine is that apps *clone*
shared code and *checks* keep the clones in lockstep, so this repo holds the
shared bytes once, a manifest per consumer saying exactly which files it
mirrors, and a drift check that compares each mirror with canon byte for
byte. It is a reference repo, not a runtime dependency: nothing imports it,
nothing links against it, it ships to no platform, and it is not for end
users. The audience is whoever, person or agent, is changing a file that more
than one app carries.

The consumers are [CalMind](https://github.com/chere005/CalMind),
[ChefMind](https://github.com/chere005/ChefMind),
[MyCalMind](https://github.com/chere005/MyCalMind) and
[AcctMind](https://github.com/chere005/AcctMind). Private targets, if any,
are named one per line in an untracked, gitignored `.private-targets` at the
checkout root (default none) and ride along after these. They are expected as sibling checkouts
of this one; `MIND_DIR` overrides the parent directory.

## Running it

Node and npm; the lanes and the check are plain `/bin/sh`.

```sh
npm install
npm test          # the canon core suite itself, run here
npm run typecheck
npm run check     # every consumer with a checkout, against canon
```

CoreMind also owns the suite's release order. `npm run dtp -- all`
propagates canon into every consumer, proves the check clean, then runs each
repo's own release lane in order, core first; `npm run tdtp -- all` puts each
repo's full test run in front of that. Every repo must be on `main` and clean
before it starts.

## More

[ARCHITECTURE.md](ARCHITECTURE.md) is the map of the tree, the manifests and
their modes, the deploy graph, how each platform ships, and the reasons each
of them is the way it is. [AGENTS.md](AGENTS.md) is how to work in this repo:
the standing rules and the traps. BSD 3-Clause; see [LICENSE](LICENSE).

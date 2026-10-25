# CoreMind

Feel free to clone it and copy the canon into your own apps, etc. This repo ships nothing itself.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

The one copy of the code the Mind apps share, and the check that keeps their copies identical.

- Consumers: [CalMind](https://github.com/chere005/CalMind), [ChefMind](https://github.com/chere005/ChefMind), [MyCalMind](https://github.com/chere005/MyCalMind), [AcctMind](https://github.com/chere005/AcctMind). Private targets, if any, go one per line in a gitignored `.private-targets` file.
- Apps clone the shared code. `npm run check` compares every clone with canon, byte for byte.
- Not a package. Nothing imports it.
- Expects the apps as sibling checkouts (`MIND_DIR` overrides).

## Run

```sh
npm install
npm test
npm run check
```

`npm run dtp -- all` releases the whole suite in order, core first. `tdtp` runs every test first.

Docs: [ARCHITECTURE](ARCHITECTURE.md) · [AGENTS](AGENTS.md). BSD 3-Clause.

# CoreMind

The one copy of the code the Mind apps share, and the check that keeps their copies identical.

## Disclaimer

Feel free to clone it and copy the canon into your own apps, etc. This repo ships nothing itself.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

## Quick start / Install

```sh
git clone https://github.com/chere005/CoreMind   # beside the app checkouts
cd CoreMind && npm install
```

## Platforms

- None. A reference repo; the apps are what ship.

## Usage

```sh
npm run check     # every app checkout, byte for byte against canon
npm test          # the shared core's own tests
```

Change a shared file here, then run the check; it tells you which app copies drifted.

## Notes

- Consumers: [CalMind](https://github.com/chere005/CalMind), [ChefMind](https://github.com/chere005/ChefMind), [MyCalMind](https://github.com/chere005/MyCalMind), [AcctMind](https://github.com/chere005/AcctMind). Private targets go one per line in a gitignored `.private-targets` file.
- Apps clone the shared code; nothing imports this repo.
- Expects the apps as sibling checkouts (`MIND_DIR` overrides).

## Building

Nothing to build. `npm run dtp -- all` releases the whole suite in order, core first; `tdtp` runs every test first.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): the tree, the manifests and their modes, the deploy graph.
- [AGENTS.md](AGENTS.md): rules for anyone, human or agent, changing the code.

## Contributing

Issues and pull requests are welcome. Read AGENTS.md first; `npm test` and `npm run check` must pass. BSD 3-Clause, see [LICENSE](LICENSE).

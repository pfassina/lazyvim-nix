# Contributing

Thanks for taking the time to contribute. A few guidelines to keep things smooth.

## Keep PRs focused

One PR should do one thing. If you're fixing a bug, fix only that bug; if you're adding a feature, add only that feature.

Please **don't** bundle in:

- Unrelated `data/plugins.json`, `data/extras.json`, or `data/treesitter-mappings.json` updates — these are maintained by the automated workflows (`update-plugins.yml`, etc.) and updating them by hand inside an unrelated PR creates noisy diffs and merge conflicts.
- Code-style refactors, formatting passes, or rename-only changes in files you're not otherwise touching.
- Drive-by fixes to other bugs you noticed — open a separate PR or issue for those.

If you spot something worth changing outside your PR's scope, that's great — open a follow-up PR for it. Mixed-scope PRs are much harder to review and will usually be sent back for splitting.

## Generated files

These files are generated and should not be hand-edited unless your PR's explicit purpose is to change generation:

- `data/plugins.json`
- `data/extras.json`
- `data/treesitter.json`
- `data/dependencies.json`
- `data/parser-manifest.json`

If you're adding or changing a plugin mapping, edit `data/mappings.json` and follow the process described in `INSTRUCTIONS.md` (Standard Operating Workflows → Workflow 2: Adding or Fixing a Plugin Mapping).

## Before opening a PR

Run the test suite:

```bash
nix-build test/ -A runAll
```

Or for a quick check during development:

```bash
./test/run-tests.sh --smoke-only
```

If your change touches the home-manager module, please also confirm it builds in a real config (`nix develop`, then evaluate against your own setup or one of the test fixtures).

## Commit messages and PR descriptions

- Keep them short and direct. Describe what changed and why; skip marketing language.
- One logical change per commit when reasonable.
- Reference the issue number if your PR closes one (`Closes #123`).

## Reporting bugs and requesting features

Open an issue at <https://github.com/pfassina/lazyvim-nix/issues>. For bugs, please include:

- Your `flake.nix` (or the relevant snippet)
- The error output
- Whether you can reproduce it on a clean checkout

Thanks!

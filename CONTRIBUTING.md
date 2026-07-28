# Contributing

GenTree is a small personal project, but focused fixes and improvements are welcome.

1. Install the pinned tools with `aftman install`.
2. Install packages with `wally install`.
3. Run `stylua --check src examples` and `selene src examples`.
4. Build the package with `rojo build package.project.json --output GenTree.rbxm`.
5. Open a pull request that explains the behavior change.

Public API changes should include a changelog entry. Releases use semantic versioning
and a matching `vX.Y.Z` Git tag.

# Contributing

GenTree is a small personal project, but I am happy to look at focused fixes and
improvements. My main request is that a change stays easy to understand—this project
is supposed to be readable from one end to the other.

1. Install the pinned tools with `aftman install`.
2. Install packages with `wally install`.
3. Run `stylua --check src examples` and `selene src examples`.
4. Build the package with `rojo build package.project.json --output GenTree.rbxm`.
5. Open a pull request and tell me what changed, why you chose it, and how you checked it.

Oh! If the public API changes, please add a changelog entry too. I use semantic
versioning and a matching `vX.Y.Z` Git tag for releases.

# Changelog

This is where I keep the short story of each GenTree release. I follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) so the history stays useful.

## [Unreleased]

### Fixed

- Reject negative `trunkLean` values before tree generation reaches an invalid random range.
- Reject non-positive `leafSize` components before creating invalid Roblox parts.
- Reject an empty `tagLeaves` value before foliage reaches CollectionService.

## [0.1.1] - 2026-07-29

### Changed

- Rewrote the project documentation in the personal voice I intended for GenTree.
- Explained the trunk, canopy, foliage, seeding, and forest algorithms narratively.
- Added direct references from each explanation to the relevant source module.
- Polished the example, contribution notes, issue template, and package description.

## [0.1.0] - 2026-07-29

### Added

- A complete procedural tree generator with trunks, tiered branches, and foliage.
- Deterministic generation through the `seed` option.
- Forest generation with uniform placement inside a radius.
- Wally and Rojo package manifests.
- Automated checks and tagged GitHub/Wally release workflow.
- Package documentation, architecture diagrams, and a runnable example.

[Unreleased]: https://github.com/devkyato/GenTree/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/devkyato/GenTree/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/devkyato/GenTree/releases/tag/v0.1.0

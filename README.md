# Tree Generator (Roblox / Luau)

I wanted a fully code-driven tree system I could drop into different projects,
so I built this little module that handles:

- Procedural trunk, branch, and foliage generation (no prebuilt models)
- Config-driven variants via `Config.Defaults.Tree`
- Async batching for large forests
- Optional growth → decay → regrow cycle using TweenService

## Folder layout

- `src/ReplicatedStorage/TreeGeneration`
  - `Generators/TreeGenerator.lua` – main system
  - `Generators/AsyncScheduler.lua` – simple task batcher
  - `Config.lua` – tunable settings
  - `Factory.lua` – small wrapper so other scripts can just call `Factory.spawnTree(...)`
- `src/ServerScriptService/TreeDemo.server.lua`
  - Minimal example that spawns a forest on the baseplate.

## Quick usage

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Factory = require(ReplicatedStorage.TreeGeneration.Factory)

-- single tree
Factory.spawnTree(Vector3.new(0, Workspace.Baseplate.Position.Y + 1, 0), Workspace)

-- animated tree
Factory.spawnAnimatedTree(Vector3.new(10, Workspace.Baseplate.Position.Y + 1, 0), Workspace)

-- forest
Factory.spawnForest(Vector3.new(0, Workspace.Baseplate.Position.Y + 1, 0), 80, 40, Workspace)

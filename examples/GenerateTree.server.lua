local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local GenTree = require(ServerScriptService.Packages.GenTree)

local generator = GenTree.new({
	seed = 2026,
	minHeight = 24,
	maxHeight = 32,
})

generator:Generate(Vector3.new(0, 0, 0), Workspace)
generator:GenerateForest(Vector3.new(45, 0, 0), 12, 30, Workspace)

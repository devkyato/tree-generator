local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local GenTree = require(ServerScriptService.Packages.GenTree)

-- I use a seed here so every Studio run starts with the same example.
local generator = GenTree.new({
	seed = 2026,
	minHeight = 24,
	maxHeight = 32,
})

-- One tree shows the basic call; the little forest shows the same generator at scale.
generator:Generate(Vector3.new(0, 0, 0), Workspace)
generator:GenerateForest(Vector3.new(45, 0, 0), 12, 30, Workspace)

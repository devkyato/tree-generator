local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TreeFactory = require(ReplicatedStorage.TreeGeneration:WaitForChild("Factory"))

local TreeGen = TreeFactory.new("Tree")

TreeGen:generateAnimated(Vector3.new(25, 0, 25), workspace)

local GENERATORS = script.Parent:WaitForChild("Generators")

local Factory    = {}
Factory.__index  = Factory

function Factory.new(treeType, customConfig)
	assert(type(treeType)=="string", "TreeType must be a string")
	
	local modName = treeType .. "Generator"
	local mod     = GENERATORS:FindFirstChild(modName)
	
	assert(mod, ("No generator found for '%s' at Generators/%s"):format(treeType, modName))
	
	local Generator = require(mod)
	local instance = Generator.new(customConfig)
	
	return setmetatable({ gen = instance }, Factory)
end

function Factory:generate(position: Vector3, parent: Instance?)
	return self.gen:generate(position, parent)
end

function Factory:generateAnimated(position: Vector3, parent: Instance?)
	return self.gen:generateAnimated(position, parent)
end

return Factory

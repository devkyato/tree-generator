--!strict

local Types = require(script.Parent.Types)

type Config = Types.Config
type Options = Types.Options

local Config = {}

-- I keep every visual decision here so the generation code can stay focused on shape.
local DEFAULTS: Config = {
	seed = nil,
	minHeight = 22,
	maxHeight = 30,
	trunkSegments = 9,
	trunkBaseRadius = 2.2,
	trunkTopRadius = 0.65,
	trunkLean = 1.4,
	branchTiers = 4,
	branchesPerTier = 5,
	branchLength = 11,
	branchLengthVariation = 3,
	branchRadius = 0.55,
	branchUpwardAngle = 24,
	leafClustersPerBranch = 3,
	leavesPerCluster = 4,
	leafSize = Vector3.new(3.6, 3.2, 3.6),
	leafSpread = 3.2,
	trunkColor = Color3.fromRGB(112, 82, 58),
	leafColor = Color3.fromRGB(66, 132, 73),
	trunkMaterial = Enum.Material.Wood,
	leafMaterial = Enum.Material.Grass,
	trunkCanCollide = true,
	branchesCanCollide = false,
	tagLeaves = "GenTreeLeaf",
	yieldEveryParts = 80,
}

local VALID_KEYS = {
	seed = true,
	minHeight = true,
	maxHeight = true,
	trunkSegments = true,
	trunkBaseRadius = true,
	trunkTopRadius = true,
	trunkLean = true,
	branchTiers = true,
	branchesPerTier = true,
	branchLength = true,
	branchLengthVariation = true,
	branchRadius = true,
	branchUpwardAngle = true,
	leafClustersPerBranch = true,
	leavesPerCluster = true,
	leafSize = true,
	leafSpread = true,
	trunkColor = true,
	leafColor = true,
	trunkMaterial = true,
	leafMaterial = true,
	trunkCanCollide = true,
	branchesCanCollide = true,
	tagLeaves = true,
	yieldEveryParts = true,
}

local function assertNumber(config: Config, key: string, minimum: number)
	local value = (config :: any)[key]
	assert(type(value) == "number" and value >= minimum, `{key} must be a number >= {minimum}`)
end

function Config.resolve(options: Options?): Config
	local resolved = table.clone(DEFAULTS)
	local mutable = resolved :: any

	-- Failing early made tuning much nicer than discovering a typo inside a half-built tree.
	if options then
		for key, value in options do
			assert(VALID_KEYS[key], `Unknown GenTree option "{key}"`)
			assert(
				typeof(value) == typeof((DEFAULTS :: any)[key])
					or (key == "seed" and type(value) == "number")
					or (key == "tagLeaves" and value == false),
				`Invalid type for GenTree option "{key}"`
			)
			mutable[key] = value
		end
	end

	assertNumber(resolved, "minHeight", 1)
	assertNumber(resolved, "maxHeight", 1)
	assert(resolved.maxHeight >= resolved.minHeight, "maxHeight must be greater than or equal to minHeight")
	assertNumber(resolved, "trunkSegments", 1)
	assertNumber(resolved, "trunkBaseRadius", 0.05)
	assertNumber(resolved, "trunkTopRadius", 0.05)
	assertNumber(resolved, "trunkLean", 0)
	assertNumber(resolved, "branchTiers", 1)
	assertNumber(resolved, "branchesPerTier", 1)
	assertNumber(resolved, "branchLength", 0.1)
	assertNumber(resolved, "branchLengthVariation", 0)
	assertNumber(resolved, "branchRadius", 0.05)
	assertNumber(resolved, "leafClustersPerBranch", 1)
	assertNumber(resolved, "leavesPerCluster", 1)
	assertNumber(resolved, "leafSpread", 0)
	assertNumber(resolved, "yieldEveryParts", 0)
	assert(
		resolved.tagLeaves == false or #resolved.tagLeaves > 0,
		"tagLeaves must be false or a non-empty string"
	)
	assert(
		resolved.leafSize.X > 0 and resolved.leafSize.Y > 0 and resolved.leafSize.Z > 0,
		"leafSize components must be greater than zero"
	)

	resolved.trunkSegments = math.floor(resolved.trunkSegments)
	resolved.branchTiers = math.floor(resolved.branchTiers)
	resolved.branchesPerTier = math.floor(resolved.branchesPerTier)
	resolved.leafClustersPerBranch = math.floor(resolved.leafClustersPerBranch)
	resolved.leavesPerCluster = math.floor(resolved.leavesPerCluster)
	resolved.yieldEveryParts = math.floor(resolved.yieldEveryParts)

	return table.freeze(resolved)
end

function Config.defaults(): Config
	return table.freeze(table.clone(DEFAULTS))
end

return table.freeze(Config)

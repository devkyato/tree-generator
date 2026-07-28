--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local Geometry = require(script.Parent.Geometry)
local Types = require(script.Parent.Types)

type Config = Types.Config
type GeneratorType = Types.Generator
type Options = Types.Options

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))

local Generator = {}
Generator.__index = Generator

local function getSeed(config: Config): number
	if config.seed ~= nil then
		return config.seed
	end

	return Random.new():NextInteger(1, 2 ^ 30)
end

function Generator.new(options: Options?): GeneratorType
	local self = setmetatable({
		Config = Config.resolve(options),
	}, Generator)

	return self :: any
end

function Generator:_yieldIfNeeded(partCount: number)
	local every = self.Config.yieldEveryParts
	if every > 0 and partCount % every == 0 then
		task.wait()
	end
end

function Generator:_makeLeaf(position: Vector3, random: Random, parent: Instance): Part
	local config = self.Config
	local sizeScale = random:NextNumber(0.72, 1.18)
	local colorScale = random:NextNumber(0.9, 1.08)

	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Shape = Enum.PartType.Ball
	leaf.Size = config.leafSize * sizeScale
	leaf.Color = Color3.new(
		math.clamp(config.leafColor.R * colorScale, 0, 1),
		math.clamp(config.leafColor.G * colorScale, 0, 1),
		math.clamp(config.leafColor.B * colorScale, 0, 1)
	)
	leaf.Material = config.leafMaterial
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanTouch = false
	leaf.CanQuery = true
	leaf.CastShadow = true
	leaf.Position = position
	leaf.Orientation =
		Vector3.new(random:NextNumber(-18, 18), random:NextNumber(0, 360), random:NextNumber(-18, 18))
	leaf.Parent = parent

	if config.tagLeaves then
		CollectionService:AddTag(leaf, config.tagLeaves)
	end

	return leaf
end

function Generator:Generate(position: Vector3, parent: Instance?): Model
	assert(typeof(position) == "Vector3", "position must be a Vector3")
	parent = parent or Workspace
	assert(parent ~= nil, "parent must be an Instance")

	local config = self.Config
	local seed = getSeed(config)
	local random = Random.new(seed)
	local height = random:NextNumber(config.minHeight, config.maxHeight)

	local model = Instance.new("Model")
	model.Name = "GenTree"
	model:SetAttribute("GenTree", true)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("Height", height)

	local trunkFolder = Instance.new("Folder")
	trunkFolder.Name = "Trunk"
	trunkFolder.Parent = model

	local branchesFolder = Instance.new("Folder")
	branchesFolder.Name = "Branches"
	branchesFolder.Parent = model

	local foliageFolder = Instance.new("Folder")
	foliageFolder.Name = "Foliage"
	foliageFolder.Parent = model

	local points = table.create(config.trunkSegments + 1)
	points[1] = position

	local segmentHeight = height / config.trunkSegments
	local partCount = 0

	for index = 1, config.trunkSegments do
		local progress = index / config.trunkSegments
		local previous = points[index]
		local lean = Vector3.new(
			random:NextNumber(-config.trunkLean, config.trunkLean),
			0,
			random:NextNumber(-config.trunkLean, config.trunkLean)
		) / config.trunkSegments
		local nextPoint = previous + Vector3.new(0, segmentHeight, 0) + lean
		points[index + 1] = nextPoint

		local startRadius = config.trunkBaseRadius
			+ (config.trunkTopRadius - config.trunkBaseRadius) * ((index - 1) / config.trunkSegments)
		local endRadius = config.trunkBaseRadius + (config.trunkTopRadius - config.trunkBaseRadius) * progress

		local segment = Geometry.partBetween(
			string.format("Trunk_%02d", index),
			previous,
			nextPoint,
			startRadius,
			endRadius,
			config.trunkColor,
			config.trunkMaterial,
			config.trunkCanCollide,
			trunkFolder
		)
		if index == 1 then
			model.PrimaryPart = segment
		end

		partCount += 1
		self:_yieldIfNeeded(partCount)
	end

	for tier = 1, config.branchTiers do
		local tierProgress = tier / (config.branchTiers + 1)
		local trunkProgress = 0.35 + tierProgress * 0.58
		local pointIndex = math.clamp(math.round(trunkProgress * config.trunkSegments) + 1, 2, #points)
		local origin = points[pointIndex]

		for branchIndex = 1, config.branchesPerTier do
			local angle = (tier * 0.65 + branchIndex) * GOLDEN_ANGLE + random:NextNumber(-0.18, 0.18)
			local upward = math.rad(config.branchUpwardAngle + random:NextNumber(-8, 8))
			local horizontal = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local direction = (horizontal * math.cos(upward) + Vector3.yAxis * math.sin(upward)).Unit
			local length = math.max(
				0.5,
				config.branchLength
					+ random:NextNumber(-config.branchLengthVariation, config.branchLengthVariation)
					- tierProgress * 2
			)
			local tip = origin + direction * length

			Geometry.partBetween(
				string.format("Branch_%02d_%02d", tier, branchIndex),
				origin,
				tip,
				config.branchRadius,
				config.branchRadius * 0.42,
				config.trunkColor,
				config.trunkMaterial,
				config.branchesCanCollide,
				branchesFolder
			)
			partCount += 1
			self:_yieldIfNeeded(partCount)

			for clusterIndex = 1, config.leafClustersPerBranch do
				local clusterProgress = clusterIndex / config.leafClustersPerBranch
				local clusterCenter = origin:Lerp(tip, 0.48 + clusterProgress * 0.52)

				for _ = 1, config.leavesPerCluster do
					local offset = Geometry.randomUnitVector(random)
						* random:NextNumber(config.leafSpread * 0.2, config.leafSpread)
					self:_makeLeaf(clusterCenter + offset, random, foliageFolder)
					partCount += 1
					self:_yieldIfNeeded(partCount)
				end
			end
		end
	end

	local crown = points[#points]
	for _ = 1, config.leavesPerCluster * 2 do
		local offset = Geometry.randomUnitVector(random)
			* random:NextNumber(config.leafSpread * 0.15, config.leafSpread)
		self:_makeLeaf(crown + offset, random, foliageFolder)
		partCount += 1
		self:_yieldIfNeeded(partCount)
	end

	model:SetAttribute("PartCount", partCount)
	model.Parent = parent
	return model
end

function Generator:GenerateForest(
	center: Vector3,
	count: number,
	radius: number,
	parent: Instance?
): { Model }
	assert(typeof(center) == "Vector3", "center must be a Vector3")
	assert(type(count) == "number" and count >= 0, "count must be a non-negative number")
	assert(type(radius) == "number" and radius >= 0, "radius must be a non-negative number")

	local models = table.create(math.floor(count))
	local random = Random.new(getSeed(self.Config))

	for index = 1, math.floor(count) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(random:NextNumber()) * radius
		local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local treeOptions = table.clone(self.Config) :: any
		treeOptions.seed = random:NextInteger(1, 2 ^ 30)
		models[index] = Generator.new(treeOptions):Generate(center + offset, parent)
	end

	return models
end

return Generator

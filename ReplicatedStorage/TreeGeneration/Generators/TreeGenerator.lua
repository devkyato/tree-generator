--!optimize 2
--!native
--!nonstrict

--[[
	TreeGenerator – my procedural tree / forest + growth-cycle system

	Quick idea of what I was going for:

	- I wanted trees that are *fully generated in code* (no prebuilt models), so I can
	  swap configs and instantly get different species / styles.
	- Everything hangs off a single config block (Config.Defaults["Tree"]) so designers
	  don’t have to touch the logic, they just tweak numbers.
	- The visuals are intentionally “classic Roblox”: blocky parts, stud surfaces,
	  but with just enough Perlin noise + golden-angle branching to feel organic.
	- There are two main modes:
		• generate(...) build a static tree
		• generateAnimated(...) same tree, but it grows, holds, decays, and then
		                          gets regenerated in a loop for ambience.

	This script is what I’m using as a little tech piece for HiddenDevs to show how
	I structure systems: config-driven, async-friendly, and fairly self-contained.
]]

local Workspace          = game:GetService("Workspace")
local CollectionService  = game:GetService("CollectionService")
local TweenService       = game:GetService("TweenService")

local Config             = require(script.Parent.Parent:WaitForChild("Config"))
local Async              = require(script.Parent.Parent:WaitForChild("AsyncScheduler"))

-- This is the key I use under Config.Defaults to pull in the base settings
local treeType = "Tree"

-- Type annotations ------------------------------------------------------------

--[[
	TreeConfig: all the knobs I expose for whoever tunes the trees.
	Most of these live in Config.Defaults[treeType] and can be overridden per-instance.
]]
export type TreeConfig = {
	MIN_HEIGHT: number,
	MAX_HEIGHT: number,
	TRUNK_WIDTH_RATIO: number,
	TRUNK_TAPER_RATIO: number,
	MAX_TILT: number?,
	NOISE_SCALE: number?,
	TRUNK_COLOR: Color3,

	BRANCH_COUNT: number,
	BRANCH_LENGTH_RATIO: number,
	BRANCH_THICKNESS_RATIO: number,
	BRANCH_TIER_COUNT: number?,
	BRANCHES_PER_TIER: number?,

	PHI_MIN: number, -- in DEGREES
	PHI_MAX: number, -- in DEGREES

	LEAF_SIZE_MIN: number,
	LEAF_SIZE_MAX: number,
	LEAF_COLOR: Color3,
	LEAF_CLUSTER_SIZE: number?,

	FOLIAGE_DENSITY: number?,
	LEAN_LIMIT_DEGREES: number?,
	TRUNK_SEGMENT_HEIGHT: number?,
	MIN_BRANCH_DISTANCE: number?,
	WIND_AFFECTED_TAG: string?,
	GOLDEN_ANGLE: number?, -- optional, in DEGREES
}

-- This is basically the public surface of the generator
export type TreeGeneratorObj = {
	cfg: TreeConfig,
	generate: (self: TreeGeneratorObj, pos: Vector3, parent: Instance?) -> Model,
	generateForest: (self: TreeGeneratorObj, center: Vector3, radius: number, count: number, parent: Instance?) -> {Model},
	generateAnimated: (self: TreeGeneratorObj, pos: Vector3, parent: Instance?) -> Model,
	_runGrowthCycle: (self: TreeGeneratorObj, model: Model) -> (),
}

export type TreeGeneratorModule = {
	new: (customConfig: {[string]: any}?) -> TreeGeneratorObj
}

local TreeGenerator = {} :: TreeGeneratorModule
TreeGenerator.__index = TreeGenerator

-- Constants -------------------------------------------------------------------

-- This is how many branch/foliage jobs I push into AsyncScheduler at once
local DEFAULT_BATCH_SIZE = 50

-- Surfaces I flip to studs to keep the “lego-ish” feel
local SURFACE_TYPES = { "Top", "Bottom", "Left", "Right", "Front", "Back" }

-- Debug configuration (I flip this on when I’m tuning)
local DEBUG = false
local function log(...: any)
	if DEBUG then
		warn(("[TreeGenerator:%s]"):format(treeType), ...)
	end
end

-- Utility functions -----------------------------------------------------------

local function randRange(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function clamp(value: number, minVal: number, maxVal: number): number
	return math.max(minVal, math.min(maxVal, value))
end

local function degreesToRadians(degrees: number): number
	return math.rad(degrees)
end

-- I snap sizes to whole studs to avoid weird fractional block sizes
local function quantizeSize(v: Vector3): Vector3
	-- snap to whole studs, minimum 1x1x1
	return Vector3.new(
		math.max(1, math.round(v.X)),
		math.max(1, math.round(v.Y)),
		math.max(1, math.round(v.Z))
	)
end

-- Give all faces stud surfaces so everything meshes together nicely
local function applyStudSurfaces(part: BasePart)
	for _, name in ipairs(SURFACE_TYPES) do
		part[name .. "Surface"] = Enum.SurfaceType.Studs
	end
end

-- I use this to slightly vary color so piles of leaves don’t look copy-pasted
local function jitterColor(base: Color3, maxDelta: number): Color3
	local function j(c: number)
		local v = c + randRange(-maxDelta, maxDelta)
		return clamp(v, 0, 1)
	end

	return Color3.new(
		j(base.R),
		j(base.G),
		j(base.B)
	)
end

--[[ 
	createLeafCluster

	This is the small helper I use whenever I want “a blob of leaves”:

	- I keep the leaves close together so you get a compact cluster instead
	  of random noise everywhere.
	- Each leaf has a tiny color offset and a bit of rotation so it feels
	  hand-placed even though it’s not.
	- Everything here is anchored and non-collidable because I don’t want the
	  tree to mess with gameplay physics by default.
]]
local function createLeafCluster(
	position: Vector3,
	size: number,
	color: Color3,
	parent: Instance,
	tag: string?
): ()
	-- tighter + fewer leaves (scales with cluster size but stays small)
	local leafCount = math.clamp(math.floor(size * 1.2), 2, 6)
	local radial = size * 0.6

	for _ = 1, leafCount do
		-- keep offsets close to center so clusters stay dense
		local offset = Vector3.new(
			randRange(-radial, radial),
			randRange(-radial * 0.2, radial * 0.6),
			randRange(-radial, radial)
		)

		-- make sure nothing flies too far out
		if offset.Magnitude > radial then
			offset = offset.Unit * radial
		end

		-- snapped cube-ish size (I like chunky leaves)
		local base = randRange(size * 0.5, size * 0.9)
		local leafSize = quantizeSize(Vector3.new(
			base,
			base,
			base
			))

		local leaf = Instance.new("Part")
		leaf.Name = "Leaf"
		leaf.Shape = Enum.PartType.Block
		leaf.Size = leafSize
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.Color = jitterColor(color, 0.07) -- small hue variation
		leaf.Material = Enum.Material.Plastic

		-- mild random orientation to break up repetition
		local yaw   = math.rad(math.random(0, 359))
		local pitch = math.rad(math.random(-8, 8))
		local roll  = math.rad(math.random(-8, 8))

		leaf.CFrame = CFrame.new(position)
			* CFrame.Angles(pitch, yaw, roll)
			* CFrame.new(offset)

		applyStudSurfaces(leaf)
		leaf.Parent = parent

		-- optional tag (I usually use this so a separate Wind system can find them)
		if tag then
			CollectionService:AddTag(leaf, tag)
		end
	end
end

-- Constructor -----------------------------------------------------------------

--[[
	new(customConfig?)

	This is where I wire the generator up to Config and apply local overrides.

	Flow:
	- Pull Config.Defaults[treeType] as the base.
	- Apply any per-call overrides with basic type checking.
	- Fill in defaults for optional fields so the rest of the code can assume
	  they exist.
	- Run a few sanity checks so the config fails fast instead of silently
	  building weird trees.
]]
function TreeGenerator.new(customConfig: {[string]: any}?): TreeGeneratorObj
	local baseCfg = Config.Defaults[treeType] :: TreeConfig?
	assert(baseCfg, ("No Config.Defaults[%q] defined"):format(treeType))

	-- clone defaults so I don’t mutate the shared config
	local cfg: TreeConfig = table.clone(baseCfg :: any)

	-- merge overrides
	if customConfig then
		for key, value in pairs(customConfig) do
			if cfg[key] ~= nil then
				if typeof(value) == typeof(cfg[key]) then
					cfg[key] = value
				else
					warn(("Type mismatch for config key %s: expected %s, got %s")
						:format(key, typeof(cfg[key]), typeof(value)))
				end
			else
				warn(("Unknown config key %s in TreeGenerator.new overrides"):format(key))
			end
		end
	end

	-- fill in fallback values for optional settings
	cfg.NOISE_SCALE          = cfg.NOISE_SCALE or 0.05
	cfg.TRUNK_SEGMENT_HEIGHT = cfg.TRUNK_SEGMENT_HEIGHT or 1
	cfg.FOLIAGE_DENSITY      = cfg.FOLIAGE_DENSITY or 0.5
	cfg.LEAF_CLUSTER_SIZE    = cfg.LEAF_CLUSTER_SIZE or cfg.LEAF_SIZE_MAX
	cfg.MIN_BRANCH_DISTANCE  = cfg.MIN_BRANCH_DISTANCE or 3
	cfg.BRANCH_TIER_COUNT    = cfg.BRANCH_TIER_COUNT or 3
	cfg.BRANCHES_PER_TIER    = cfg.BRANCHES_PER_TIER
		or math.max(1, math.floor(cfg.BRANCH_COUNT / math.max(cfg.BRANCH_TIER_COUNT, 1)))
	cfg.LEAN_LIMIT_DEGREES   = cfg.LEAN_LIMIT_DEGREES or 15 -- degrees

	-- quick validation so bad configs scream early
	assert(cfg.MIN_HEIGHT and cfg.MAX_HEIGHT, "MIN_HEIGHT and MAX_HEIGHT must be set")
	assert(cfg.MIN_HEIGHT > 0 and cfg.MAX_HEIGHT > 0, "Tree height must be > 0")
	assert(cfg.MIN_HEIGHT <= cfg.MAX_HEIGHT, "MIN_HEIGHT must be <= MAX_HEIGHT")

	assert(cfg.BRANCH_TIER_COUNT >= 1, "BRANCH_TIER_COUNT must be >= 1")
	assert(cfg.MIN_BRANCH_DISTANCE > 0, "MIN_BRANCH_DISTANCE must be > 0")
	assert(typeof(cfg.TRUNK_COLOR) == "Color3", "TRUNK_COLOR must be Color3")
	assert(typeof(cfg.LEAF_COLOR) == "Color3", "LEAF_COLOR must be Color3")

	-- keep lean within something that still looks stable
	cfg.LEAN_LIMIT_DEGREES = clamp(cfg.LEAN_LIMIT_DEGREES, 0, 60)

	local self = setmetatable({
		cfg = cfg,
	}, TreeGenerator) :: any

	return self
end

-- Generation ------------------------------------------------------------------

-- Tiny helper I use when I want to visualize positions while debugging
local function debugPoint(worldPos: Vector3)
	if not DEBUG then return end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DebugPoint"
	attachment.CFrame = CFrame.new(worldPos)
	attachment.Parent = Workspace
end

--[[
	generate(pos, parent?)

	This is the core static generation:

	1) I create a Model with three folders: Trunk, Branches, and Foliage.
	2) I build the trunk from bottom to top as a stack of segments, and store
	   the CFrame of each step so I can attach branches at different heights.
	   The trunk tilt is driven by Perlin noise to keep it slightly organic.
	3) I schedule branch + foliage jobs into an Async batch so this stays
	   friendly even when I’m spawning a forest.
]]
function TreeGenerator:generate(pos: Vector3, parent: Instance?): Model
	parent = parent or Workspace
	local cfg = (self :: any).cfg :: TreeConfig

	log("Generating tree at", pos)

	-- per-instance golden angle (I let this be configurable; otherwise I fall back
	-- to a standard golden-angle derived value)
	local goldenAngleRad = if cfg.GOLDEN_ANGLE
		then degreesToRadians(cfg.GOLDEN_ANGLE)
		else math.pi * 2 * 0.618033988749895

	-- Create model container
	local model = Instance.new("Model")
	model.Name = ("%s_Tree_%d"):format(treeType, math.random(10000, 99999))
	model.Parent = parent

	-- Root part: invisible anchor for the whole tree
	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Size = Vector3.new(2, 2, 2)
	rootPart.Transparency = 1
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CFrame = CFrame.new(pos)
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Organizational folders to keep Explorer clean
	local trunkFolder = Instance.new("Folder")
	trunkFolder.Name = "Trunk"
	trunkFolder.Parent = model

	local branchFolder = Instance.new("Folder")
	branchFolder.Name = "Branches"
	branchFolder.Parent = model

	local leafFolder = Instance.new("Folder")
	leafFolder.Name = "Foliage"
	leafFolder.Parent = model

	-- Initial orientation with random yaw so trees don’t all face the same way
	local initialYaw   = degreesToRadians(randRange(0, 360))
	local currentCFrame = rootPart.CFrame * CFrame.Angles(0, initialYaw, 0)

	-- Trunk generation --------------------------------------------------------

	local height        = randRange(cfg.MIN_HEIGHT, cfg.MAX_HEIGHT)
	local segmentHeight = math.max(0.1, cfg.TRUNK_SEGMENT_HEIGHT or 1)
	local segmentCount  = math.max(1, math.ceil(height / segmentHeight))

	log(("Trunk: height=%.2f, segments=%d"):format(height, segmentCount))

	local trunkSegments: {CFrame} = {}
	local baseWidth      = height * cfg.TRUNK_WIDTH_RATIO
	local leanLimitRad   = degreesToRadians(cfg.LEAN_LIMIT_DEGREES)

	for i = 1, segmentCount do
		local t = i / segmentCount
		-- I taper the trunk as I go up (simple linear blend)
		local segmentWidth = baseWidth * (1 - t * (1 - cfg.TRUNK_TAPER_RATIO))
		local segmentSize  = Vector3.new(segmentWidth, segmentHeight, segmentWidth)

		-- Procedural lean with Perlin noise in X/Z so each tree has its own character
		local noiseX = math.noise(pos.X * cfg.NOISE_SCALE, i * cfg.NOISE_SCALE, 0)
		local noiseZ = math.noise(pos.Z * cfg.NOISE_SCALE, i * cfg.NOISE_SCALE, 100)

		local tiltX = clamp(noiseX * 2, -1, 1) * leanLimitRad * 0.5
		local tiltZ = clamp(noiseZ * 2, -1, 1) * leanLimitRad * 0.5

		currentCFrame = currentCFrame * CFrame.Angles(tiltX, 0, tiltZ)

		local segment = Instance.new("Part")
		segment.Name = ("TrunkSegment_%d"):format(i)
		segment.Size = segmentSize
		segment.Anchored = true
		segment.CanCollide = true
		segment.Color = cfg.TRUNK_COLOR
		segment.Material = Enum.Material.Wood

		for _, surface in ipairs(SURFACE_TYPES) do
			segment[("%sSurface"):format(surface)] = Enum.SurfaceType.Studs
		end

		segment.CFrame = currentCFrame * CFrame.new(0, segmentHeight / 2, 0)
		segment.Parent = trunkFolder

		debugPoint(segment.Position)

		-- move up one segment for the next iteration
		currentCFrame = currentCFrame * CFrame.new(0, segmentHeight, 0)
		trunkSegments[i] = currentCFrame

		-- occasional trunk foliage so some trees feel a bit overgrown
		if math.random() < (cfg.FOLIAGE_DENSITY or 0.5) * 0.1 then
			local foliagePos = segment.Position + Vector3.new(
				randRange(-segmentWidth / 2, segmentWidth / 2),
				randRange(0, segmentHeight / 2),
				randRange(-segmentWidth / 2, segmentWidth / 2)
			)

			createLeafCluster(
				foliagePos,
				cfg.LEAF_SIZE_MIN,
				cfg.LEAF_COLOR,
				leafFolder,
				cfg.WIND_AFFECTED_TAG
			)
		end
	end

	-- Tasks for async batching (branches + foliage live here)
	local tasks = {}

	--[[
		makeBranchTask

		I wrap branch generation into a closure so I can queue it in the Async
		batcher. Each task:
		- Builds one main branch.
		- Adds a few sub-branches along it.
		- Sprinkles leaf clusters along the length and at the tip.
	]]
	local function makeBranchTask(
		tierIndex: number,
		branchIndex: number,
		originPos: Vector3,
		direction: Vector3,
		branchLength: number,
		branchThickness: number
	): () -> ()
		return function()
			local endPos   = originPos + direction * branchLength
			local midPoint = originPos + direction * (branchLength * 0.5)

			local branch = Instance.new("Part")
			branch.Name = ("Branch_T%d_B%d"):format(tierIndex, branchIndex)
			branch.Size = Vector3.new(branchThickness, branchLength, branchThickness)
			branch.Anchored = true
			branch.CanCollide = true
			branch.Color = cfg.TRUNK_COLOR
			branch.Material = Enum.Material.Wood

			-- I orient the branch so its Y axis aligns with the direction vector
			local upVector = Vector3.new(0, 1, 0)
			local axis     = upVector:Cross(direction)
			local dot      = clamp(upVector:Dot(direction), -1, 1)
			local angle    = math.acos(dot)

			if axis.Magnitude > 1e-4 then
				branch.CFrame = CFrame.new(midPoint) * CFrame.fromAxisAngle(axis.Unit, angle)
			else
				branch.CFrame = CFrame.new(midPoint)
			end

			branch.Parent = branchFolder
			debugPoint(endPos)

			-- Sub-branches ---------------------------------------------------
			-- Simple rule of thumb: longer branch and more sub-branches
			local subBranchCount = math.max(0, math.floor(branchLength / (cfg.MIN_BRANCH_DISTANCE or 1)))
			for subIdx = 1, subBranchCount do
				local t = subIdx / (subBranchCount + 1)
				local subPos = originPos + direction * (branchLength * t)

				local subDir = (direction + Vector3.new(
					randRange(-0.3, 0.3),
					randRange(-0.2, 0),
					randRange(-0.3, 0.3)
					)).Unit

				local subLength   = branchLength * 0.4
				local subEnd      = subPos + subDir * subLength
				local subMid      = subPos + subDir * (subLength * 0.5)
				local subBranch   = Instance.new("Part")
				subBranch.Name    = ("SubBranch_%d_%d"):format(branchIndex, subIdx)
				subBranch.Size    = Vector3.new(branchThickness * 0.6, subLength, branchThickness * 0.6)
				subBranch.Anchored = true
				subBranch.CanCollide = false
				subBranch.Color     = cfg.TRUNK_COLOR
				subBranch.Material  = Enum.Material.Wood
				subBranch.Transparency = 0.2

				local subAxis = Vector3.new(0, 1, 0):Cross(subDir)
				local subDot  = clamp(Vector3.new(0, 1, 0):Dot(subDir), -1, 1)
				local subAngle = math.acos(subDot)

				if subAxis.Magnitude > 1e-4 then
					subBranch.CFrame = CFrame.new(subMid) * CFrame.fromAxisAngle(subAxis.Unit, subAngle)
				else
					subBranch.CFrame = CFrame.new(subMid)
				end

				subBranch.Parent = branchFolder

				-- Foliage at sub-branch ends
				createLeafCluster(
					subEnd,
					cfg.LEAF_CLUSTER_SIZE or cfg.LEAF_SIZE_MAX,
					cfg.LEAF_COLOR,
					leafFolder,
					cfg.WIND_AFFECTED_TAG
				)
			end

			-- Primary foliage clusters along the main branch
			local clusterCount = math.floor(branchLength / 3) + 1
			for clusterIdx = 1, clusterCount do
				local t = clusterIdx / (clusterCount + 1)
				local clusterPos = originPos + direction * (branchLength * t)
				local clusterSize = randRange(cfg.LEAF_SIZE_MIN, cfg.LEAF_SIZE_MAX) * 1.5

				createLeafCluster(
					clusterPos,
					clusterSize,
					cfg.LEAF_COLOR,
					leafFolder,
					cfg.WIND_AFFECTED_TAG
				)
			end

			-- Extra foliage at branch tip to thicken the canopy
			createLeafCluster(
				endPos,
				(cfg.LEAF_CLUSTER_SIZE or cfg.LEAF_SIZE_MAX) * 1.2,
				cfg.LEAF_COLOR,
				leafFolder,
				cfg.WIND_AFFECTED_TAG
			)
		end
	end

	-- Branch tier generation ---------------------------------------------------

	--[[
		generateBranchTier(tierIndex, tierHeightFraction)

		Here I decide how many branches a “ring” gets and where they go.
		I use a golden-angle inspired theta and a random phi in a range so
		branches spiral around the trunk instead of lining up.
	]]
	local function generateBranchTier(tierIndex: number, tierHeightFraction: number)
		local trunkIndex = math.floor(segmentCount * tierHeightFraction)
		if trunkIndex < 1 or trunkIndex > #trunkSegments then return end

		local originCF = trunkSegments[trunkIndex]
		if not originCF then return end

		local tierBranches = cfg.BRANCHES_PER_TIER
			or math.max(1, math.floor(cfg.BRANCH_COUNT / cfg.BRANCH_TIER_COUNT))

		local originPosBase = originCF.Position

		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = { model }
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		for branchIdx = 1, tierBranches do
			local baseBranchLength = height * cfg.BRANCH_LENGTH_RATIO
				* (1 - tierHeightFraction * 0.3)
			local branchThickness = baseWidth * cfg.BRANCH_THICKNESS_RATIO
				* (1 - tierHeightFraction * 0.5)

			-- spherical distribution (theta = around trunk, phi = “lift”)
			local theta = branchIdx * goldenAngleRad
			local phi   = degreesToRadians(randRange(cfg.PHI_MIN, cfg.PHI_MAX))

			local dir = Vector3.new(
				math.cos(theta) * math.sin(phi),
				math.cos(phi),
				math.sin(theta) * math.sin(phi)
			)

			if dir.Magnitude < 1e-4 then
				dir = Vector3.new(0, 1, 0)
			else
				dir = dir.Unit
			end

			-- Tiny noise so tiers don’t look perfectly regular
			dir = (dir + Vector3.new(
				randRange(-0.2, 0.2),
				randRange(-0.1, 0.1),
				randRange(-0.2, 0.2)
				)).Unit

			local branchLength = baseBranchLength
			-- quick raycast: if something is in the way, I shorten the branch a bit
			if Workspace:Raycast(originPosBase, dir * baseBranchLength, raycastParams) then
				log("Branch collision detected, shortening branch")
				branchLength = baseBranchLength * 0.7
			end

			table.insert(tasks, makeBranchTask(
				tierIndex,
				branchIdx,
				originPosBase,
				dir,
				branchLength,
				branchThickness
				))
		end
	end

	-- Generate tiers
	if cfg.BRANCH_TIER_COUNT == 1 then
		-- Single-ring tree (I bias it a bit towards the upper half)
		generateBranchTier(1, 0.6)
	else
		-- Multiple tiers spread roughly from 30% up to ~90% of the trunk
		for tier = 1, cfg.BRANCH_TIER_COUNT do
			local heightFraction = 0.3 + (tier - 1) * (0.6 / (cfg.BRANCH_TIER_COUNT - 1))
			generateBranchTier(tier, heightFraction)
		end
	end

	-- Top foliage cluster to give the tree a crown
	table.insert(tasks, function()
		local topCF  = trunkSegments[#trunkSegments]
		local topPos = topCF.Position

		createLeafCluster(
			topPos,
			(cfg.LEAF_CLUSTER_SIZE or cfg.LEAF_SIZE_MAX) * 2,
			cfg.LEAF_COLOR,
			leafFolder,
			cfg.WIND_AFFECTED_TAG
		)
	end)

	-- Execute generation tasks asynchronously through my AsyncScheduler
	local batchSize = Config.BatchSize or DEFAULT_BATCH_SIZE
	Async:Batch(tasks, batchSize)

	log(("Tree generation complete: %s (jobs: %d)"):format(model.Name, #tasks))
	return model
end

-- Forest generation -----------------------------------------------------------

--[[
	generateForest(center, radius, count, parent?)

	This is just a small wrapper I wrote so I can throw down a whole patch
	of trees quickly:

	- I sample points in a disk (using sqrt(rand) to keep the density uniform).
	- For each point, I call generate(...) once.
	- I yield every 10 trees so the server doesn’t get a frame spike.
]]
function TreeGenerator:generateForest(
	center: Vector3,
	radius: number,
	count: number,
	parent: Instance?
): {Model}
	parent = parent or Workspace
	local models = {}

	log(("Generating jungle: center=%s, radius=%.2f, count=%d"):format(
		tostring(center), radius, count))

	for i = 1, count do
		local angle    = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * radius

		local offset = Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)

		local treePos = center + offset
		-- slight random Y offset so things don’t look laser-leveled
		treePos = Vector3.new(
			treePos.X,
			treePos.Y + randRange(-2, 2),
			treePos.Z
		)

		models[i] = (self :: any):generate(treePos, parent)

		if i % 10 == 0 then
			task.wait()
		end
	end

	return models
end

-- ============================================================================
-- Animation: trunk grow, branches grow, leaves grow, decay, regrow
-- ============================================================================

--[[
	_runGrowthCycle(model)

	This is the “life cycle” part of the system. I re-use the static tree that
	generate(...) created and drive a simple animation story on top of it:

	1) Trunk grows from bottom to top.
	2) Once a trunk segment is in, its branches grow out.
	3) Once a branch exists, its leaves grow.
	4) The tree holds at full health for a bit.
	5) Leaves dry out and fall.
	6) The wood darkens, fades, and the whole tree collapses.

	After this, generateAnimated(...) will destroy the old model and spawn
	a fresh one in the same place, giving a loop of growth and decay.
]]
function TreeGenerator:_runGrowthCycle(model: Model)
	local cfg = (self :: any).cfg :: TreeConfig

	local trunkFolder = model:FindFirstChild("Trunk")
	local branchFolder = model:FindFirstChild("Branches")
	local leafFolder = model:FindFirstChild("Foliage")
	if not (trunkFolder and branchFolder and leafFolder) then
		return
	end

	-- collect parts -----------------------------------------------------------
	local trunkParts = {} :: {BasePart}
	local branchParts = {} :: {BasePart}
	local leafParts = {} :: {BasePart}

	for _, inst in ipairs(trunkFolder:GetChildren()) do
		if inst:IsA("BasePart") then
			table.insert(trunkParts, inst)
		end
	end
	for _, inst in ipairs(branchFolder:GetChildren()) do
		if inst:IsA("BasePart") then
			table.insert(branchParts, inst)
		end
	end
	for _, inst in ipairs(leafFolder:GetChildren()) do
		if inst:IsA("BasePart") then
			table.insert(leafParts, inst)
		end
	end

	if #trunkParts == 0 and #branchParts == 0 then
		return
	end

	-- sort by height so I can treat them as bottom→top chains
	table.sort(trunkParts, function(a, b) return a.Position.Y < b.Position.Y end)
	table.sort(branchParts, function(a, b) return a.Position.Y < b.Position.Y end)
	table.sort(leafParts,   function(a, b) return a.Position.Y < b.Position.Y end)

	-- map branches to closest trunk segment (by Y) ---------------------------
	-- This way, when I grow trunk segment N, I also grow its child branches.
	local trunkToBranches: {[number]: {BasePart}} = {}
	for _, branch in ipairs(branchParts) do
		local closestIndex = 1
		local closestDist = math.huge
		for index, trunk in ipairs(trunkParts) do
			local dy = math.abs(branch.Position.Y - trunk.Position.Y)
			if dy < closestDist then
				closestDist = dy
				closestIndex = index
			end
		end
		local bucket = trunkToBranches[closestIndex]
		if not bucket then
			bucket = {}
			trunkToBranches[closestIndex] = bucket
		end
		table.insert(bucket, branch)
	end

	-- map leaves to closest branch so they animate with that branch ----------
	local branchToLeaves: {[BasePart]: {BasePart}} = {}
	if #branchParts > 0 then
		for _, leaf in ipairs(leafParts) do
			local closestBranch: BasePart? = nil
			local closestDist = math.huge
			for _, branch in ipairs(branchParts) do
				local d = (leaf.Position - branch.Position).Magnitude
				if d < closestDist then
					closestDist = d
					closestBranch = branch
				end
			end
			if closestBranch then
				local bucket = branchToLeaves[closestBranch]
				if not bucket then
					bucket = {}
					branchToLeaves[closestBranch] = bucket
				end
				table.insert(bucket, leaf)
			end
		end
	end

	-- store final sizes for scaling back up ----------------------------------
	local trunkFinalSize = {} :: {[BasePart]: Vector3}
	local branchFinalSize = {} :: {[BasePart]: Vector3}
	local leafFinalSize = {} :: {[BasePart]: Vector3}

	for _, p in ipairs(trunkParts) do
		trunkFinalSize[p] = p.Size
	end
	for _, p in ipairs(branchParts) do
		branchFinalSize[p] = p.Size
	end
	for _, p in ipairs(leafParts) do
		leafFinalSize[p] = p.Size
	end

	-- initial state: all parts tiny + invisible ------------------------------
	-- Here I squash everything into “stubs” so I can tween them up.
	for _, p in ipairs(trunkParts) do
		local finalSize = trunkFinalSize[p]
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Size = Vector3.new(finalSize.X, math.max(0.2, finalSize.Y * 0.05), finalSize.Z)
	end

	for _, p in ipairs(branchParts) do
		local finalSize = branchFinalSize[p]
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Size = Vector3.new(finalSize.X, math.max(0.2, finalSize.Y * 0.05), finalSize.Z)
	end

	for _, p in ipairs(leafParts) do
		local finalSize = leafFinalSize[p]
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Size = finalSize * 0.2
	end

	---------------------------------------------------------------------------
	-- GROWTH PHASE (TweenService)
	-- I stagger growth so it feels like the tree is building itself:
	-- 1) trunk grows bottom→top
	-- 2) when a segment is done, its branches grow
	-- 3) once a branch exists, its leaves pop in
	---------------------------------------------------------------------------

	local trunkGrowTotal = 3 -- seconds total for full trunk growth
	local segCount = math.max(#trunkParts, 1)
	local perSegmentTime = trunkGrowTotal / segCount

	for trunkIndex, trunk in ipairs(trunkParts) do
		if not trunk.Parent then break end

		local finalSize = trunkFinalSize[trunk]
		local segTween = TweenService:Create(
			trunk,
			TweenInfo.new(perSegmentTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				Size = finalSize,
				Transparency = 0,
			}
		)

		segTween:Play()
		segTween.Completed:Wait()

		if trunk.Parent then
			trunk.CanCollide = true
		end

		-- grow branches attached to this trunk segment
		local attachedBranches = trunkToBranches[trunkIndex]
		if attachedBranches then
			for _, branch in ipairs(attachedBranches) do
				if not branch.Parent then continue end

				local bFinalSize = branchFinalSize[branch]
				branch.Size = Vector3.new(
					bFinalSize.X,
					math.max(0.2, bFinalSize.Y * 0.05),
					bFinalSize.Z
				)
				branch.Transparency = 1
				branch.Anchored = true
				branch.CanCollide = false

				local bTween = TweenService:Create(
					branch,
					TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						Size = bFinalSize,
						Transparency = 0,
					}
				)

				bTween:Play()
				bTween.Completed:Wait()

				if branch.Parent then
					branch.CanCollide = true
				end

				-- grow leaves attached to this branch
				local attachedLeaves = branchToLeaves[branch]
				if attachedLeaves then
					for _, leaf in ipairs(attachedLeaves) do
						if not leaf.Parent then continue end

						local lFinalSize = leafFinalSize[leaf]
						leaf.Size = lFinalSize * 0.2
						leaf.Transparency = 1
						leaf.Anchored = true
						leaf.CanCollide = false

						local lTween = TweenService:Create(
							leaf,
							TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
							{
								Size = lFinalSize,
								Transparency = 0,
							}
						)

						lTween:Play()
						lTween.Completed:Wait()

						if leaf.Parent then
							local windTag = cfg.WIND_AFFECTED_TAG or "WindLeaf"
							CollectionService:AddTag(leaf, windTag)
						end
					end
				end
			end
		end
	end

	-- any stray leaves still invisible, snap them to final state
	for _, leaf in ipairs(leafParts) do
		if leaf.Parent and leaf.Transparency > 0 then
			leaf.Transparency = 0
			leaf.Size = leafFinalSize[leaf]
			leaf.CanCollide = false
			local windTag = cfg.WIND_AFFECTED_TAG or "WindLeaf"
			CollectionService:AddTag(leaf, windTag)
		end
	end

	-- let the tree chill at full health for a bit
	task.wait(5)

	---------------------------------------------------------------------------
	-- DECAY PHASE (TweenService)
	-- I reverse the story:
	--   leaves discolor, fade, fall, then
	--   wood darkens, fades, collapses
	---------------------------------------------------------------------------

	local decayLeafTime = 1.2
	local deadLeafColor = Color3.new(0.3, 0.2, 0.1)

	for _, leaf in ipairs(leafParts) do
		if leaf.Parent then
			local tween = TweenService:Create(
				leaf,
				TweenInfo.new(decayLeafTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Color = deadLeafColor,
					Transparency = 1,
				}
			)
			tween:Play()
		end
	end

	task.wait(decayLeafTime)

	-- let leaves physically fall away
	for _, leaf in ipairs(leafParts) do
		if leaf.Parent then
			local windTag = cfg.WIND_AFFECTED_TAG or "WindLeaf"
			if CollectionService:HasTag(leaf, windTag) then
				CollectionService:RemoveTag(leaf, windTag)
			end
			if CollectionService:HasTag(leaf, "WindShake") then
				CollectionService:RemoveTag(leaf, "WindShake")
			end
			leaf.Anchored = false -- gravity takes over here
		end
	end

	task.wait(2)

	-- wood decay
	local woodyParts = {} :: {BasePart}
	for _, p in ipairs(trunkParts) do woodyParts[#woodyParts + 1] = p end
	for _, p in ipairs(branchParts) do woodyParts[#woodyParts + 1] = p end

	local deadWoodColor = Color3.new(0.25, 0.25, 0.25)
	local woodDecayTime = 1.5

	for _, p in ipairs(woodyParts) do
		if p.Parent then
			local tween = TweenService:Create(
				p,
				TweenInfo.new(woodDecayTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Color = deadWoodColor,
					Transparency = 0.9,
				}
			)
			tween:Play()
		end
	end

	task.wait(woodDecayTime)

	-- unanchor the “dead” wood so the trunk and branches collapse too
	for _, p in ipairs(woodyParts) do
		if p.Parent then
			p.Anchored = false
		end
	end

	task.wait(2)
end

-- Public API: same generation, but with growth/decay/regrow loop --------------

--[[
	generateAnimated(pos, parent?)

	This is the entry point I use when I want the full life cycle:

	- I generate a static tree once.
	- In a separate thread, I run _runGrowthCycle on that Model.
	- When the cycle finishes, I destroy the old tree and generate a new one
	  at the same root position.
	- The loop repeats as long as the parent container is still alive.

	Note: If you keep references to the Model yourself, those will go stale
	over time because I destroy and recreate it between cycles. I usually just
	treat this as a visual system and let it manage its own instances.
]]
function TreeGenerator:generateAnimated(pos: Vector3, parent: Instance?): Model
	parent = parent or Workspace

	local model = (self :: any):generate(pos, parent)

	task.spawn(function()
		local selfGen = self :: any
		local rootPos = pos
		local parentRef = parent
		local currentModel = model

		while parentRef and parentRef.Parent do
			if not currentModel or not currentModel.Parent then break end

			selfGen:_runGrowthCycle(currentModel)

			if not currentModel.Parent then break end
			local p = currentModel.Parent
			currentModel:Destroy()
			if not p then break end

			parentRef = p
			currentModel = selfGen:generate(rootPos, parentRef)
		end
	end)

	return model
end

return TreeGenerator

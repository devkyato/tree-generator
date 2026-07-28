--!strict

local Geometry = {}

function Geometry.partBetween(
	name: string,
	startPosition: Vector3,
	endPosition: Vector3,
	startRadius: number,
	endRadius: number,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean,
	parent: Instance
): Part
	local delta = endPosition - startPosition
	local length = delta.Magnitude
	local radius = (startRadius + endRadius) / 2
	assert(length > 0, "Cannot create a zero-length tree part")

	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, radius * 2, radius * 2)
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanTouch = canCollide
	part.CanQuery = true
	part.CastShadow = true

	local midpoint = startPosition:Lerp(endPosition, 0.5)
	part.CFrame = CFrame.lookAt(midpoint, endPosition) * CFrame.Angles(0, math.pi / 2, 0)
	part.Parent = parent

	return part
end

function Geometry.randomUnitVector(random: Random): Vector3
	local z = random:NextNumber(-1, 1)
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(math.max(0, 1 - z * z))

	return Vector3.new(radius * math.cos(angle), z, radius * math.sin(angle))
end

return table.freeze(Geometry)

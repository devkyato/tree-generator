--!strict

export type Config = {
	seed: number?,
	minHeight: number,
	maxHeight: number,
	trunkSegments: number,
	trunkBaseRadius: number,
	trunkTopRadius: number,
	trunkLean: number,
	branchTiers: number,
	branchesPerTier: number,
	branchLength: number,
	branchLengthVariation: number,
	branchRadius: number,
	branchUpwardAngle: number,
	leafClustersPerBranch: number,
	leavesPerCluster: number,
	leafSize: Vector3,
	leafSpread: number,
	trunkColor: Color3,
	leafColor: Color3,
	trunkMaterial: Enum.Material,
	leafMaterial: Enum.Material,
	trunkCanCollide: boolean,
	branchesCanCollide: boolean,
	tagLeaves: string | false,
	yieldEveryParts: number,
}

export type Options = { [string]: any }

export type Generator = {
	Config: Config,
	Generate: (self: Generator, position: Vector3, parent: Instance?) -> Model,
	GenerateForest: (
		self: Generator,
		center: Vector3,
		count: number,
		radius: number,
		parent: Instance?
	) -> { Model },
}

return nil

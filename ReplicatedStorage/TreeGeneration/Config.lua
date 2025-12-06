local Config = {}

-- how many parts to create per batch before yielding
Config.BatchSize = 50

-- Default parameters *by tree type*
Config.Defaults = {
	Tree = {
		MIN_HEIGHT = 25,
		MAX_HEIGHT = 30,

		TRUNK_WIDTH_RATIO    = 0.06,
		TRUNK_TAPER_RATIO    = 0.3,

		TRUNK_COLOR          = Color3.fromRGB(117, 84, 59), -- brown
		LEAF_COLOR           = Color3.fromRGB(73, 119, 67), -- green

		BRANCH_COUNT         = 32,
		BRANCH_LENGTH_RATIO  = 0.5,
		BRANCH_THICKNESS_RATIO = 0.3,

		BRANCH_TIER_COUNT    = 3,
		BRANCHES_PER_TIER    = 8,

		-- angles in DEGREES (more upward-ish)
		PHI_MIN              = 25,
		PHI_MAX              = 65,

		-- leaves
		LEAF_SIZE_MIN        = 0.7,
		LEAF_SIZE_MAX        = 2.3,
		LEAF_CLUSTER_SIZE    = 0.75,
		FOLIAGE_DENSITY      = 0.5,

		-- misc
		LEAN_LIMIT_DEGREES   = 8,
		NOISE_SCALE          = 0.03,
		TRUNK_SEGMENT_HEIGHT = 1.3,
		MIN_BRANCH_DISTANCE  = 4,
		WIND_AFFECTED_TAG    = "WindLeaf",
	}

}

return Config

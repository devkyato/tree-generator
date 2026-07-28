--!strict

local Config = require(script.Config)
local Generator = require(script.Generator)
local Types = require(script.Types)

type Generator = Types.Generator
type Options = Types.Options

local GenTree = {}

GenTree.Version = "0.1.0"
GenTree.DefaultConfig = Config.defaults()

function GenTree.new(options: Options?): Generator
	return Generator.new(options)
end

function GenTree.generate(position: Vector3, parent: Instance?, options: Options?): Model
	return Generator.new(options):Generate(position, parent)
end

return table.freeze(GenTree)

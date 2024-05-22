local backend = require("vox.backend")

local default_config = {
	backend = backend,
	wait_time = 25,

	modes = {
		c = "Command",
		i = "Insert",
		n = "Normal",
		v = "Visual",
		V = "Visual line",
	},

	postprocess = nil,

	char_map = {
		["("] = "L par",
		[")"] = "R par",
		["{"] = "L brace",
		["}"] = "R brace",
		["["] = "L bracket",
		["]"] = "R bracker",
		["<"] = "L angle",
		[">"] = "R angle",
		["."] = "period",
		[","] = "comma",
		[";"] = "semi colon",
		[":"] = "colon",
		['"'] = "double quote",
		["'"] = "quote",
		["`"] = "tick",
		["~"] = "tilde",
	},
}

local config = {}

local M = {}

M.get = function(key)
	return config[key]
end

M.setup = function(user_config)
	config = vim.tbl_deep_extend("force", {}, default_config)

	user_config = user_config or {}
	for key, value in pairs(user_config) do
		config[key] = value
	end

	local pattern = {}
	for k, _ in pairs(config.char_map) do
		table.insert(pattern, string.format("%%%s", k))
	end

	config._char_map_pattern = string.format("[%s]", table.concat(pattern, ""))
end

return M

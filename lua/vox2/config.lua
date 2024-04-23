local default_config = {
	rate = 1.0,
	pitch = 1.0,
	volume = 1.0,
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
		if config[key] ~= nil then
			config[key] = value
		end
	end
end

return M

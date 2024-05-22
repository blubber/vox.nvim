local config = require("vox.config")

local M = {}

M.expand_special_chars = function(utterances)
	local result = {}
	local pattern = config.get("_char_map_pattern")
	local char_map = config.get("char_map")

	if pattern == nil then
		return utterances
	end

	for _, u in ipairs(utterances) do
		local start = 1

		while true do
			local a, b = string.find(u.text, pattern, start)
			if a == nil then
				table.insert(result, { text = string.sub(u.text, start), source = u.source, event = u.event })
				break
			end

			local text = string.sub(u.text, start, a - 1)
			local expanded = char_map[string.sub(u.text, a, b)]

			table.insert(result, { text = text, source = u.source, event = u.event })
			table.insert(result, { text = expanded, source = u.source, special = true, event = u.event })

			start = b + 1
		end
	end

	return result
end

return M

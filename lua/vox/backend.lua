local M = {}

local default_config = {}
_VoxBackendConfig = _VoxBackendConfig or {}

M.setup = function(user_config)
	user_config = user_config or {}
	_VoxBackendConfig = vim.tbl_deep_extend("force", default_config, user_config)
	return M
end

function M:speak(utterances)
	local routing = _VoxBackendConfig.routing or {}
	local body = {}

	for _, u in ipairs(utterances) do
		local voice = routing[u.source] or "__default"
		if u.special then
			voice = _VoxBackendConfig.special_char_voice or voice
		end

		table.insert(body, { text = u.text, voice = voice })
	end

	local json = vim.fn.json_encode(body)
	local request = string.format(
		[[
POST /speak HTTP/1.1
Host: 127.0.0.1:1729
User-Agent: curl/8.4.0
Accept: */*
Content-Type: application/json
Content-Length: %d
	]],
		#json
	) .. string.format("\n\n%s", json)

	local client = vim.uv.new_tcp()
	client:connect("127.0.0.1", 1729, function(err)
		if err == nil then
			client:write(request)
			client:shutdown()
			client:close()
		end
	end)
end

return M

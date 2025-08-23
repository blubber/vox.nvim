local M = {}

local defaults = {
    routing = {
        linenr = "__default",
        line = "__default",
        diagnostic = "__default",
        special = "__default",
        meta = "__default",
    },
}

local state = {
    opts = {},
}

function M.setup(opts)
    state.opts = vim.tbl_deep_extend("force", defaults, opts or {})

    return M
end

local function get_voice(source)
    local parts = {}
    for part in string.gmatch(source, "[^.]+") do
        table.insert(parts, part)
    end

    for i = #parts, 1, -1 do
        local key = table.concat(parts, ".", 1, i)
	local voice = state.opts.routing[key]

        if voice ~= nil then
            return voice
        end
    end

    return nil
end

function M.speak(utterances)
    local body = {}

    for _, u in ipairs(utterances) do
        local voice = get_voice(u.source)
        table.insert(body, { text = u.content, voice = voice })
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

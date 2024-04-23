local curl = require 'plenary.curl'

local M = {}
local config = {}

local cursor_pos = { 1, 0 }

local function flatten(t)
  if type(t) ~= 'table' then
    return t
  end

  local result = {}
  for i = 1, #t do
    if type(t[i]) == 'table' then
      local tt = flatten(t[i])
      for u = 1, #tt do
        result[#result + 1] = tt[u]
      end
    else
      result[#result + 1] = t[i]
    end
  end

  return result
end

local function event_handler(event)
  local utterances = {}
  local interrupt = true

  if event.event == 'CursorMoved' then
    local lnum = event.new_cursor_pos[1]
    local lnum_delta = math.abs(event.new_cursor_pos[1] - event.old_cursor_pos[1])

    if lnum_delta > 0 and not config.sources.lnum.muted then
      table.insert(utterances, { text = string.format('%d', lnum), source = 'lnum', interrupt = interrupt })
      interrupt = false
    end
    if lnum_delta > 0 and not config.sources.line.muted then
      local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
      table.insert(utterances, { text = line, source = 'line', interrupt = interrupt })
      interrupt = false
    end
    if lnum_delta > 0 and config.sources.extmark.muted == false then
      local extmarks = vim.api.nvim_buf_get_extmarks(0, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true, type = 'virt_text' })
      for _, extmark in ipairs(extmarks) do
        local virt_texts = flatten(extmark[4].virt_text)
        for i = 1, #virt_texts do
          table.insert(utterances, {
            text = virt_texts[i],
            source = 'virt_text',
            interrupt = interrupt,
          })
          interrupt = false
        end
      end
    end
  end

  return utterances
end

local function configure_autocmds()
  local group = vim.api.nvim_create_augroup('vox', { clear = true })
  local create = vim.api.nvim_create_autocmd

  create('CursorMoved', {
    callback = function(_)
      local new_cursor_pos = vim.api.nvim_win_get_cursor(0)
      M.handle_event {
        event = 'CursorMoved',
        old_cursor_pos = cursor_pos,
        new_cursor_pos = new_cursor_pos,
      }
      cursor_pos = new_cursor_pos
    end,
    group = group,
  })
end

local function postprocess_utterance(utterance)
  local mods = config.sources[utterance.source]

  if mods == nil then
    return utterance
  end

  if mods.muted then
    return nil
  end

  utterance.rate = utterance.rate * (mods.rate or 1.0)
  utterance.pitch = utterance.pitch * (mods.pitch or 1.0)
  utterance.volume = utterance.volume * (mods.volume or 1.0)

  return utterance
end

function M.VoxdBackend(port, verbose)
  local backend = { verbose = verbose, port = port or 1729 }

  function backend:old_request(command, body)
    local url = string.format('http://localhost:%d/%s', self.port, command)
    if body ~= nil then
      body = vim.fn.json_encode(body)
    end
    return curl.post(url, {
      body = body,
      headers = { content_type = 'application/json' },
      timeout = 0.5,
    })
  end

  function backend:request(command, body)
    local json = ''
    if body ~= nil then
      json = vim.fn.json_encode(body)
    end

    local request_data = string.format(
      [[
POST /%s HTTP/1.1
Host: localhost:1729
User-Agent: curl/8.4.0
Accept: */*
Accept-Encoding: deflate, gzip
Content-Type: application/json
Content-Length: %d
    ]],
      command,
      #json
    )

    request_data = request_data .. string.format('\n\n%s', json)

    local client = vim.uv.new_tcp()
    client:connect('127.0.0.1', self.port, function(err)
      client:write(request_data)
      client:shutdown()
      client:close()
    end)
  end

  function backend:interrupt() end

  function backend:speak(utterance)
    local status, err = pcall(function()
      backend:request('speak', utterance)
    end)

    if not status and self.verbose then
      vim.print(err)
    end

    return status
  end

  return backend
end

config = {
  pitch = 1.0,
  rate = 1.0,
  volume = 1.0,

  backend = M.VoxdBackend(),
  event_handler = nil,
  postprocess = nil,

  sources = {
    lnum = {
      muted = false,
      pitch = 1.2,
      rate = 1,
      2,
    },
    line = { muted = false },
    text = { muted = false },
    extmark = {
      muted = false,
      pitc = 0.9,
      rate = 0.9,
    },
  },
}

local CommandHandlers = {
  mute = function(args)
    if #args == 0 or args[1] == '*' then
      for _, conf in pairs(config.sources) do
        conf.muted = true
      end
    else
      for i = 1, #args do
        local conf = config.sources[args[i]]
        if conf ~= nil then
          conf.muted = true
        end
      end
    end
  end,
  unmute = function(args)
    if #args == 0 or args[1] == '*' then
      for _, conf in pairs(config.sources) do
        conf.muted = false
      end
    else
      for i = 1, #args do
        local conf = config.sources[args[i]]
        if conf ~= nil then
          conf.muted = false
        end
      end
    end
  end,
  toggle = function(args)
    if #args == 0 or args[1] == '*' then
      for _, conf in pairs(config.sources) do
        conf.muted = not conf.muted
      end
    else
      for i = 1, #args do
        local conf = config.sources[args[i]]
        if conf ~= nil then
          conf.muted = not conf.muted
        end
      end
    end
  end,

  speak = function(_, ev)
    local lines = vim.api.nvim_buf_get_lines(0, ev.line1, ev.line2, false)
    local utterances = { { text = string.format('%d', ev.line1), source = 'lnum' } }

    for i = 1, #lines do
      table.insert(utterances, { text = lines[i], source = 'line', interrupt = false })
    end

    table.insert(utterances, { text = string.format('%d', ev.line2), source = 'lnum', interrupt = false })

    M.speak(utterances)
  end,
}

M.setup = function(user_config)
  config = vim.tbl_deep_extend('force', config, user_config)

  configure_autocmds()

  vim.api.nvim_create_user_command('Vox', function(ev)
    if #ev.fargs == 0 then
      return nil
    end

    local handler = CommandHandlers[ev.fargs[1]]
    if handler == nil then
      return nil
    end

    local args = {}
    for i = 2, #ev.fargs do
      args[#args + 1] = ev.fargs[i]
    end

    handler(args, ev)
  end, { nargs = '*', range = true })
end

M.handle_event = function(event)
  local handler = config.event_handler
  local utterances = {}

  if handler then
    utterances = handler(event, event_handler)
  else
    utterances = event_handler(event)
  end

  M.speak(utterances)
end

function M.speak(utterance)
  if #utterance > 0 then
    for i = 1, #utterance do
      M.speak(utterance[i])
    end
    return
  end

  local text = string.gsub(utterance.text or '', '^%s*(.-)%s*$', '%1')

  local u = {
    pitch = config.pitch * (utterance.pitch or 1.0),
    rate = config.rate * (utterance.rate or 1.0),
    volume = config.volume * (utterance.volume or 1.0),
    interrupt = true,
    text = text,
    source = utterance.source,
  }

  if utterance.interrupt == false then
    u.interrupt = false
  end

  if config.postprocess then
    u = config.postprocess(u, postprocess_utterance)
  else
    u = postprocess_utterance(u)
  end
  if u ~= nil then
    config.backend:speak(u)
  end
end

return M

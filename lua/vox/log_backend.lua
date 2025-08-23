local Path = require 'plenary.path'

local M = {}

local state = {}

function M.setup(filename)
  state.path = Path:new(filename)
end

function M.speak(utterances)
  state.path:write('-----------------------\n', 'a')
  for _, utterance in ipairs(utterances) do
    local source = utterance.source or 'default'
    local line = string.format('[%s]  ::  %s\n', source, utterance.content)
    state.path:write(line, 'a')
  end
end

return M

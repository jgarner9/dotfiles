local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""))
end

function M.greet(name)
  return "hi " .. trim(name)
end

M.shout = function(name)
  return M.greet(name):upper()
end

return M

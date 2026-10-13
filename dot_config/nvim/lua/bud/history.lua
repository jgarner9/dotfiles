-- Chats saved per project, so starting a new chat never loses an old one.
-- One JSON file per chat in stdpath("data")/bud/chats/<project hash>/.
local util = require("bud.util")

local M = {}

local function dir(root)
  return util.dir("data") .. "/chats/" .. vim.fn.sha256(root):sub(1, 16)
end

--- chat: { id, root, title, created, updated, session_id, model, lines }
function M.save(chat)
  if not chat.id or not chat.root or not chat.lines or #chat.lines == 0 then
    return
  end
  chat.updated = util.now()
  chat.created = chat.created or chat.updated
  util.write(dir(chat.root) .. "/" .. chat.id .. ".json", vim.json.encode(chat))
end

--- Saved chats for a project, newest first.
function M.list(root)
  local out = {}
  for _, path in ipairs(vim.fn.glob(dir(root) .. "/*.json", false, true)) do
    local ok, chat = pcall(vim.json.decode, util.read(path) or "", { luanil = { object = true, array = true } })
    if ok and type(chat) == "table" and chat.id then
      table.insert(out, chat)
    end
  end
  table.sort(out, function(a, b)
    return (a.updated or 0) > (b.updated or 0)
  end)
  return out
end

function M.delete(chat)
  os.remove(dir(chat.root) .. "/" .. chat.id .. ".json")
end

--- Opens a picker of this project's chats; cb(chat) with the choice.
function M.pick(root, cb)
  local chats = M.list(root)
  if #chats == 0 then
    util.notify("No saved chats for " .. vim.fn.fnamemodify(root, ":~"))
    return
  end
  vim.ui.select(chats, {
    prompt = "Bud chats · " .. vim.fn.fnamemodify(root, ":t"),
    format_item = function(c)
      return ("%s  %s"):format(os.date("%m-%d %H:%M", c.updated or 0), c.title or "untitled")
    end,
  }, function(chat)
    if chat then
      cb(chat)
    end
  end)
end

return M

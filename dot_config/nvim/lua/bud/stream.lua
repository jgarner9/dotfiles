-- The Claude CLI's stream-json protocol: newline-delimited JSON both ways.
local M = {}

--- Returns feed(chunk): call with each stdout chunk, and with nil at EOF.
--- on_event gets every decoded object, in order. Partial lines are buffered.
function M.decoder(on_event)
  local buf = ""
  local function emit(line)
    if line:match("%S") then
      local ok, ev = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
      if ok and type(ev) == "table" then
        on_event(ev)
      end
    end
  end
  return function(chunk)
    if chunk == nil then
      if buf ~= "" then
        local rest = buf
        buf = ""
        emit(rest)
      end
      return
    end
    buf = buf .. chunk
    while true do
      local nl = buf:find("\n", 1, true)
      if not nl then
        break
      end
      local line = buf:sub(1, nl - 1)
      buf = buf:sub(nl + 1)
      emit(line)
    end
  end
end

--- Text from a streaming text delta event, else nil.
function M.text_delta(ev)
  if ev.type ~= "stream_event" or type(ev.event) ~= "table" then
    return nil
  end
  local e = ev.event
  if e.type == "content_block_delta" and type(e.delta) == "table" and e.delta.type == "text_delta" then
    return e.delta.text
  end
end

--- One user turn, encoded for --input-format stream-json.
function M.user_message(text)
  return vim.json.encode({ type = "user", message = { role = "user", content = text } }) .. "\n"
end

return M

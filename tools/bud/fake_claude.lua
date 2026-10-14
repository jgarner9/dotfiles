-- A fake `claude` CLI for Bud's tests. It speaks the same stream-json
-- protocol as `claude -p --input-format stream-json --output-format
-- stream-json --include-partial-messages`, and reads its behavior from the
-- JSON file in $FAKE_CLAUDE_CONTROL at every turn, so a test can change
-- replies without restarting a warm process:
--   { "replies": ["first", "second"],  -- popped in order; default: echo
--     "delay_ms": 0,                     -- between streamed chunks
--     "tool": { "name": "Bash", "input": { "command": "rg -n foo" } },
--     "error": "message" }               -- answer with an error result
-- Every process appends { args, cwd } to $FAKE_CLAUDE_LOG (one JSON line).
io.stdout:setvbuf("no")

local args = {}
for i = 1, #(_G.arg or {}) do
  args[i] = _G.arg[i]
end

local function out(obj)
  io.stdout:write(vim.json.encode(obj), "\n")
end

local function has(flag)
  for _, a in ipairs(args) do
    if a == flag then
      return true
    end
  end
end

local function value(flag)
  for i, a in ipairs(args) do
    if a == flag then
      return args[i + 1]
    end
  end
end

if args[1] == "auth" and args[2] == "status" then
  out({
    loggedIn = os.getenv("FAKE_CLAUDE_LOGGED_IN") ~= "0",
    authMethod = os.getenv("FAKE_CLAUDE_AUTH") or "claude.ai",
  })
  os.exit(0)
end
if has("--version") then
  io.stdout:write("9.9.9 (Fake Claude)\n")
  os.exit(0)
end

local log = os.getenv("FAKE_CLAUDE_LOG")
if log then
  local f = io.open(log, "a")
  if f then
    f:write(vim.json.encode({ args = args, cwd = vim.uv.cwd() }), "\n")
    f:close()
  end
end

local function control()
  local path = os.getenv("FAKE_CLAUDE_CONTROL")
  if not path then
    return {}, nil
  end
  local f = io.open(path, "r")
  if not f then
    return {}, path
  end
  local data = f:read("*a")
  f:close()
  local ok, c = pcall(vim.json.decode, data)
  return ok and type(c) == "table" and c or {}, path
end

local function pop_reply()
  local c, path = control()
  local reply
  if type(c.replies) == "table" and #c.replies > 0 then
    reply = table.remove(c.replies, 1)
    local f = io.open(path, "w")
    if f then
      f:write(vim.json.encode(c))
      f:close()
    end
  end
  return reply, c
end

local session = value("--resume") or ("fake-" .. tostring(vim.uv.hrtime()))
local turns = 0

for line in io.lines() do
  local ok, msg = pcall(vim.json.decode, line)
  if ok and type(msg) == "table" and msg.type == "user" then
    turns = turns + 1
    if turns == 1 then
      out({ type = "system", subtype = "init", session_id = session, model = value("--model") })
    end
    local content = msg.message and msg.message.content or ""
    local reply, c = pop_reply()
    if c.error then
      out({
        type = "result",
        subtype = "error_during_execution",
        is_error = true,
        result = c.error,
        session_id = session,
      })
    else
      reply = reply or ("echo: " .. (content:match("([^\n]*)$") or content))
      if c.tool then
        out({
          type = "assistant",
          session_id = session,
          message = {
            role = "assistant",
            content = { { type = "tool_use", id = "t1", name = c.tool.name, input = c.tool.input or {} } },
          },
        })
      end
      out({
        type = "stream_event",
        session_id = session,
        event = { type = "content_block_start", index = 0, content_block = { type = "text", text = "" } },
      })
      local i = 1
      while i <= #reply do
        local chunk = reply:sub(i, i + 4)
        i = i + 5
        if (c.delay_ms or 0) > 0 then
          vim.uv.sleep(c.delay_ms)
        end
        out({
          type = "stream_event",
          session_id = session,
          event = { type = "content_block_delta", index = 0, delta = { type = "text_delta", text = chunk } },
        })
      end
      out({
        type = "assistant",
        session_id = session,
        message = { role = "assistant", content = { { type = "text", text = reply } } },
      })
      out({
        type = "result",
        subtype = "success",
        is_error = false,
        result = reply,
        session_id = session,
        usage = { input_tokens = #content, output_tokens = #reply },
        total_cost_usd = 0.001,
        permission_denials = c.denials or {},
      })
    end
  end
end

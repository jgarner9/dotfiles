-- Talks to the Claude Code CLI, so every request runs on your subscription.
--
-- Each Claude process is `claude -p` in stream-json mode on both ends: Bud
-- writes one JSON line per user turn to stdin and reads events from stdout.
-- A process keeps its conversation for as long as it lives, which gives two
-- uses:
--   chat:  one long-lived process per chat (provider.Proc), resumed with
--          --resume after a cancel or a restart.
--   quick, write here, name suggestions: one fresh Haiku process kept warm
--          (the spare), used for exactly one request, then replaced in the
--          background, so these never share history.
local config = require("bud.config")
local instructions = require("bud.instructions")
local log = require("bud.log")
local stream = require("bud.stream")
local tools = require("bud.tools")
local util = require("bud.util")

local M = {}

-- requests in flight, for the statusline spinner
M.active = 0
-- usage of the last finished request: { input, output, cost, model }
M.last = nil

local listeners = {}
-- every process Bud started, so they all stop when Neovim exits
local all = {}

--- Calls fn() whenever M.active or M.last changes.
function M.on_change(fn)
  table.insert(listeners, fn)
end

local function changed()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

---@class bud.Proc
---@field spec table
---@field obj vim.SystemObj?
---@field session_id string?
---@field turn table?
---@field dead boolean
local Proc = {}
Proc.__index = Proc
M.Proc = Proc

--- The command line for a process spec:
---   model, root, system_file, args (extra flags), resume, persist
function M.command(spec)
  local cmd = {
    config.claude,
    "-p",
    "--input-format",
    "stream-json",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--model",
    spec.model,
  }
  if spec.system_file then
    vim.list_extend(cmd, { "--append-system-prompt-file", spec.system_file })
  end
  vim.list_extend(cmd, spec.args or {})
  if spec.resume then
    vim.list_extend(cmd, { "--resume", spec.resume })
  end
  if not spec.persist then
    table.insert(cmd, "--no-session-persistence")
  end
  return cmd
end

function Proc.spawn(spec)
  local self = setmetatable({ spec = spec, session_id = spec.resume, stderr = {}, dead = false }, Proc)
  local feed = stream.decoder(function(ev)
    self:_event(ev)
  end)
  local ok, obj = pcall(vim.system, M.command(spec), {
    cwd = spec.root,
    stdin = true,
    text = true,
    stdout = function(_, data)
      vim.schedule(function()
        feed(data)
      end)
    end,
    stderr = function(_, data)
      if data then
        vim.schedule(function()
          table.insert(self.stderr, data)
        end)
      end
    end,
  }, function(out)
    vim.schedule(function()
      self:_exit(out)
    end)
  end)
  if not ok then
    self.dead = true
    self.spawn_error = tostring(obj)
  else
    self.obj = obj
    all[self] = true
  end
  return self
end

function Proc:alive()
  return not self.dead and self.obj ~= nil
end

--- Sends one user turn. handlers: on_text(delta, text), on_tool(name, input),
--- on_done(text, result_event), on_error(message, info).
function Proc:send(text, handlers)
  handlers = handlers or {}
  if not self:alive() then
    local msg = self.spawn_error or "Claude process is not running"
    vim.schedule(function()
      if handlers.on_error then
        handlers.on_error(msg, {})
      end
    end)
    return
  end
  self.turn = { handlers = handlers, text = "", started = vim.uv.hrtime(), blocks = 0 }
  self.obj:write(stream.user_message(text))
end

function Proc:busy()
  return self.turn ~= nil
end

--- Stops the process. A turn in flight ends with on_error("Cancelled").
--- SIGTERM first; SIGKILL if it's still around a second later.
function Proc:kill()
  if self.obj and not self.dead then
    self.cancelled = true
    pcall(self.obj.kill, self.obj, 15)
    vim.defer_fn(function()
      if not self.dead then
        pcall(self.obj.kill, self.obj, 9)
      end
    end, 1000)
  end
end

--- Closes stdin, so the process exits once it is idle.
function Proc:close()
  if self.obj and not self.dead then
    pcall(self.obj.write, self.obj, nil)
  end
end

function Proc:_event(ev)
  if ev.session_id then
    self.session_id = ev.session_id
  end
  local turn = self.turn
  -- after a cancel, whatever is still in the pipe is dropped
  if not turn or self.cancelled then
    return
  end
  local h = turn.handlers
  if ev.type == "stream_event" and type(ev.event) == "table" then
    local e = ev.event
    if e.type == "content_block_start" and type(e.content_block) == "table" and e.content_block.type == "text" then
      -- a second text block (after a tool call) starts a new paragraph
      if turn.text ~= "" and h.on_text then
        turn.text = turn.text .. "\n\n"
        h.on_text("\n\n", turn.text)
      end
    end
    local delta = stream.text_delta(ev)
    if delta and delta ~= "" then
      turn.text = turn.text .. delta
      if h.on_text then
        h.on_text(delta, turn.text)
      end
    end
  elseif ev.type == "assistant" and type(ev.message) == "table" then
    for _, block in ipairs(ev.message.content or {}) do
      if block.type == "tool_use" and h.on_tool then
        h.on_tool(block.name, block.input or {})
      end
    end
  elseif ev.type == "result" then
    self.turn = nil
    turn.ms = (vim.uv.hrtime() - turn.started) / 1e6
    if ev.is_error and turn.text == "" then
      if h.on_error then
        h.on_error(ev.result or ev.subtype or "Claude returned an error", { result = ev, ms = turn.ms })
      end
      return
    end
    if turn.text == "" and type(ev.result) == "string" and ev.result ~= "" then
      turn.text = ev.result
      if h.on_text then
        h.on_text(ev.result, turn.text)
      end
    end
    if h.on_done then
      h.on_done(turn.text, ev, turn.ms)
    end
  end
end

function Proc:_exit(out)
  self.dead = true
  all[self] = nil
  local turn = self.turn
  self.turn = nil
  if self.on_exit then
    self.on_exit(self, out)
  end
  if turn and turn.handlers.on_error then
    local msg
    if self.cancelled then
      msg = "Cancelled"
    else
      local err = vim.trim(table.concat(self.stderr))
      msg = err ~= "" and err or ("Claude exited with code %d"):format(out.code or -1)
    end
    turn.handlers.on_error(msg, { cancelled = self.cancelled, code = out.code })
  end
end

-- The spare: one warm Haiku process, used once.
local spare = { proc = nil, sig = nil }

local function shared_spec(model, root)
  local path, hash = instructions.path("shared", root)
  local spec = { model = model, root = root, system_file = path, args = tools.no_tool_args() }
  spec.sig = table.concat({ model, root, hash }, "\0")
  return spec
end

--- Starts the spare for this root if it isn't already waiting.
function M.prewarm(root, model)
  if not config.warm or not util.executable(config.claude) then
    return
  end
  model = model or config.models.quick
  local spec = shared_spec(model, root or util.root())
  if spare.proc and spare.sig == spec.sig and spare.proc:alive() then
    return
  end
  M.drop_spare()
  spare.proc = Proc.spawn(spec)
  spare.sig = spec.sig
end

function M.drop_spare()
  if spare.proc then
    spare.proc:close()
    spare.proc:kill()
  end
  spare.proc, spare.sig = nil, nil
end

local function take(spec)
  local proc
  if spare.proc and spare.sig == spec.sig and spare.proc:alive() and not spare.proc:busy() then
    proc = spare.proc
    spare.proc, spare.sig = nil, nil
  else
    proc = Proc.spawn(spec)
  end
  if config.warm and spec.model == config.models.quick then
    vim.defer_fn(function()
      M.prewarm(spec.root, spec.model)
    end, 200)
  end
  return proc
end

--- One request on a fresh process. opts:
---   mode      "quick" | "write" | "name" | "spawn" (prompts.lua)
---   model     defaults to config.models[mode]
---   root      project root (the process's cwd)
---   prompt    the full message
---   request   the user's own words, for the log
---   on_text, on_done, on_error   as in Proc:send
--- Returns a handle with :cancel().
function M.request(opts)
  local root = opts.root or util.root()
  local model = opts.model or config.models[opts.mode] or config.models.quick
  local prompts = require("bud.prompts")
  local proc, message
  if opts.mode == "spawn" then
    proc = Proc.spawn({
      model = model,
      root = root,
      system_file = instructions.path("spawn", root),
      args = tools.no_tool_args(),
    })
    message = opts.prompt
  else
    proc = take(shared_spec(model, root))
    message = prompts.wrap(opts.mode, opts.prompt)
  end
  M.active = M.active + 1
  changed()
  local finished = false
  local function finish()
    if finished then
      return false
    end
    finished = true
    M.active = math.max(0, M.active - 1)
    proc:close()
    changed()
    return true
  end
  proc:send(message, {
    on_text = opts.on_text,
    on_done = function(text, ev, ms)
      if not finish() then
        return
      end
      M.last = { model = model, usage = ev.usage, cost = ev.total_cost_usd }
      log.add({
        mode = opts.mode,
        model = model,
        root = root,
        request = opts.request,
        prompt = message,
        response = text,
        usage = ev.usage,
        cost = ev.total_cost_usd,
        duration_ms = ms,
      })
      changed()
      if opts.on_done then
        opts.on_done(text, ev)
      end
    end,
    on_error = function(msg, info)
      if not finish() then
        return
      end
      log.add({ mode = opts.mode, model = model, root = root, request = opts.request, prompt = message, error = msg })
      if opts.on_error then
        opts.on_error(msg, info)
      end
    end,
  })
  return {
    proc = proc,
    cancel = function()
      proc:kill()
    end,
  }
end

--- Marks a chat turn as started/finished for the statusline.
function M.track(delta, last)
  M.active = math.max(0, M.active + delta)
  if last then
    M.last = last
  end
  changed()
end

function M.shutdown()
  M.drop_spare()
  for p in pairs(all) do
    p:kill()
  end
end

return M

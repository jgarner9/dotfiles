-- The script spawner: describe a script, pick where it goes, name it, and
-- Bud writes it, checks it (bash -n and shellcheck, or go vet and go build),
-- retries once with the errors if a check fails, and opens the result.
--
-- "Save to" takes a path from the project root (Enter alone = the root), or
-- @bin to put it in your dotfiles so dotsync delivers it everywhere:
--   Bash -> <chezmoi source>/dot_local/bin/executable_<name>
--   Go   -> <chezmoi source>/tools/cmd/<name>/main.go
local config = require("bud.config")
local provider = require("bud.provider")
local util = require("bud.util")
local win = require("bud.ui.win")

local M = {}

local notify_id = "bud_spawn"

local function say(msg, level, keep)
  util.notify(msg, level, { id = notify_id, title = "Bud spawner", timeout = keep and false or nil })
end

function M.chezmoi_source()
  if M._source then
    return M._source
  end
  if util.executable("chezmoi") then
    local ok, res = pcall(function()
      return vim.system({ "chezmoi", "source-path" }, { text = true }):wait(5000)
    end)
    if ok and res.code == 0 and vim.trim(res.stdout or "") ~= "" then
      M._source = vim.trim(res.stdout)
      return M._source
    end
  end
  local guess = vim.fn.expand("~/.local/share/chezmoi")
  if vim.fn.isdirectory(guess) == 1 then
    M._source = guess
    return guess
  end
end

--- A name from the description, used when no suggestion is ready.
function M.slug(desc)
  local skip = {
    a = true,
    an = true,
    the = true,
    that = true,
    ["and"] = true,
    to = true,
    of = true,
    ["for"] = true,
    it = true,
    script = true,
    which = true,
    with = true,
  }
  local words = {}
  for w in desc:lower():gmatch("[%a%d]+") do
    if not skip[w] then
      table.insert(words, w)
      if #words == 3 then
        break
      end
    end
  end
  return #words > 0 and table.concat(words, "-") or "script"
end

--- Cleans a model's name suggestion down to a safe command name.
function M.clean_name(text)
  local line = vim.trim((text or ""):match("[^\n]*") or "")
  line = line:gsub("[`'\"]", ""):lower()
  local go = line:match("%.go$") ~= nil
  line = line:gsub("%.go$", ""):gsub("%.sh$", "")
  line = line:gsub("[^%w%-_]+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  if line == "" then
    return nil
  end
  return line .. (go and ".go" or "")
end

--- Where the script goes. Returns { path, kind, bin, name, base, cwd, root };
--- root is where Claude runs (the project, or the dotfiles source for @bin).
function M.target(root, where, name)
  local kind = name:match("%.go$") and "go" or "bash"
  local base = name:gsub("%.go$", "")
  where = vim.trim(where or "")
  if where == "@bin" then
    local src = M.chezmoi_source()
    if not src then
      return nil, "@bin needs chezmoi (no source directory found)"
    end
    if kind == "go" then
      return {
        path = ("%s/tools/cmd/%s/main.go"):format(src, base),
        kind = kind,
        bin = true,
        name = base,
        base = base,
        cwd = src .. "/tools",
        src = src,
        root = src,
      }
    end
    return {
      path = ("%s/dot_local/bin/executable_%s"):format(src, base),
      kind = kind,
      bin = true,
      name = base,
      base = base,
      src = src,
      root = src,
    }
  end
  where = where:gsub("^%./", ""):gsub("^/", ""):gsub("/+$", "")
  local dir = where == "" and root or (root .. "/" .. where)
  return { path = dir .. "/" .. name, kind = kind, bin = false, name = name, base = base, cwd = dir, root = root }
end

function M.prompt(desc, t, prev)
  local lines = {
    ("Write a %s for this:"):format(t.kind == "go" and "Go program (package main)" or "Bash script"),
    desc,
    "",
  }
  if t.bin then
    table.insert(lines, ("It will be installed on the user's PATH and run as `%s`."):format(t.name))
  else
    table.insert(lines, ("It will be saved as %s and run directly."):format(vim.fn.fnamemodify(t.path, ":~")))
  end
  if prev then
    vim.list_extend(lines, {
      "",
      "Your previous version failed these checks:",
      "```",
      prev.errors,
      "```",
      "",
      "Previous version:",
      "```",
      prev.code,
      "```",
      "",
      "Fix it and reply with the whole file again.",
    })
  end
  return table.concat(lines, "\n")
end

--- The checks for a target, as commands: { name, cmd, cwd }.
function M.checks(t)
  local list = {}
  if t.kind == "bash" then
    table.insert(list, { name = "bash -n", cmd = { "bash", "-n", t.path } })
    if util.executable("shellcheck") then
      table.insert(list, { name = "shellcheck", cmd = { "shellcheck", "-x", "-f", "gcc", t.path } })
    end
  elseif util.executable("go") then
    local null = vim.fn.has("win32") == 1 and "NUL" or "/dev/null"
    if t.bin then
      local pkg = "./cmd/" .. t.base
      table.insert(list, { name = "go vet", cmd = { "go", "vet", pkg }, cwd = t.cwd })
      table.insert(list, { name = "go build", cmd = { "go", "build", "-o", null, pkg }, cwd = t.cwd })
    else
      table.insert(list, { name = "go vet", cmd = { "go", "vet", t.path }, cwd = t.cwd })
      table.insert(list, { name = "go build", cmd = { "go", "build", "-o", null, t.path }, cwd = t.cwd })
    end
  end
  return list
end

--- Runs the checks in order. cb(results), each { name, ok, output }.
function M.run_checks(t, cb)
  local list = M.checks(t)
  local results = {}
  local function step(i)
    local c = list[i]
    if not c then
      return cb(results)
    end
    local ok, err = pcall(vim.system, c.cmd, { text = true, cwd = c.cwd }, function(out)
      vim.schedule(function()
        local output = vim.trim((out.stdout or "") .. (out.stderr or ""))
        table.insert(results, { name = c.name, ok = out.code == 0, output = output })
        step(i + 1)
      end)
    end)
    if not ok then
      table.insert(results, { name = c.name, ok = false, output = tostring(err) })
      step(i + 1)
    end
  end
  step(1)
end

local function failed(results)
  local out = {}
  for _, r in ipairs(results) do
    if not r.ok then
      table.insert(out, ("%s:\n%s"):format(r.name, r.output))
    end
  end
  return #out > 0 and table.concat(out, "\n\n") or nil
end

local function summary(results)
  if #results == 0 then
    return "no checks available"
  end
  local parts = {}
  for _, r in ipairs(results) do
    table.insert(parts, (r.ok and config.icons.ok or "✗") .. " " .. r.name)
  end
  return table.concat(parts, " · ")
end

local function write_file(t, code)
  if code:sub(-1) ~= "\n" then
    code = code .. "\n"
  end
  util.write(t.path, code)
  if t.kind == "bash" then
    vim.uv.fs_chmod(t.path, tonumber("755", 8))
  end
end

local function install(t, cb)
  if not t.bin then
    return cb(nil)
  end
  local cmd, opts
  if t.kind == "go" then
    cmd = { "go", "install", "./cmd/" .. t.base }
    opts = { cwd = t.cwd, env = { GOBIN = vim.fn.expand("~/.local/bin") }, text = true }
  else
    if not util.executable("chezmoi") then
      return cb("chezmoi not found; run chezmoi apply later")
    end
    cmd = { "chezmoi", "apply", "--no-tty", vim.fn.expand("~/.local/bin/") .. t.base }
    opts = { text = true }
  end
  pcall(vim.system, cmd, opts, function(out)
    vim.schedule(function()
      cb(out.code ~= 0 and vim.trim((out.stderr or "") .. (out.stdout or "")) or nil)
    end)
  end)
end

--- Opens the written file in a float to look over.
function M.show(t, results)
  local buf = vim.fn.bufadd(t.path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  local width = math.min(100, vim.o.columns - 8)
  local height = math.min(math.max(10, vim.api.nvim_buf_line_count(buf)), vim.o.lines - 8)
  local w = win.open(buf, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = win.title(config.icons.spawn, vim.fn.fnamemodify(t.path, ":~:."), config.models.spawn),
    title_pos = "center",
    footer = { { " " .. summary(results) .. " · q close ", "BudFooter" } },
    footer_pos = "right",
  })
  vim.wo[w].number = true
  vim.wo[w].wrap = false
  vim.keymap.set("n", "q", function()
    win.close(w)
  end, { buffer = buf, nowait = true, desc = "Bud: close script float" })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(w),
    once = true,
    callback = function()
      pcall(vim.keymap.del, "n", "q", { buffer = buf })
    end,
  })
  return w
end

--- Generates, writes and checks. Retries once with the check errors.
function M.generate(desc, t, cb)
  local attempt = 0
  local function go(prev)
    attempt = attempt + 1
    say(
      ("%s Writing %s with %s%s"):format(
        config.icons.spawn,
        t.name,
        config.models.spawn,
        attempt > 1 and " (fixing check errors)" or ""
      ),
      nil,
      true
    )
    provider.request({
      mode = "spawn",
      model = config.models.spawn,
      root = t.root or util.root(),
      prompt = M.prompt(desc, t, prev),
      request = desc,
      on_done = function(text)
        local code = util.strip_fences(text)
        if vim.trim(code) == "" then
          say("The model returned an empty script", vim.log.levels.ERROR)
          return cb and cb(false)
        end
        write_file(t, code)
        say(("%s Checking %s"):format(config.icons.spawn, t.name), nil, true)
        M.run_checks(t, function(results)
          local errors = failed(results)
          if errors and attempt < 2 then
            return go({ errors = errors, code = code })
          end
          -- a script that still fails its checks stays where it is, uninstalled
          install(errors and { bin = false } or t, function(install_err)
            local msg = ("%s %s\n%s"):format(
              errors and config.icons.warn or config.icons.ok,
              vim.fn.fnamemodify(t.path, ":~"),
              summary(results)
            )
            local level = errors and vim.log.levels.WARN or vim.log.levels.INFO
            if t.bin and not errors then
              msg = msg
                .. (
                  install_err and ("\nInstall failed: " .. install_err)
                  or "\nInstalled to ~/.local/bin. Commit and push your dotfiles to sync it everywhere."
                )
            end
            say(msg, level)
            M.show(t, results)
            if cb then
              cb(not errors, results)
            end
          end)
        end)
      end,
      on_error = function(msg)
        say("Spawner failed: " .. msg, vim.log.levels.ERROR)
        if cb then
          cb(false)
        end
      end,
    })
  end
  go(nil)
end

--- The three prompts, then generation.
function M.open()
  local root = util.root()
  vim.ui.input({ prompt = config.icons.spawn .. "What should the script do? " }, function(desc)
    if not desc or vim.trim(desc) == "" then
      return
    end
    desc = vim.trim(desc)
    -- draft a name while you type the path
    local suggestion
    local name_done = false
    provider.request({
      mode = "name",
      root = root,
      prompt = desc,
      request = desc,
      on_done = function(text)
        suggestion = M.clean_name(text)
        name_done = true
      end,
      on_error = function()
        name_done = true
      end,
    })
    vim.ui.input(
      { prompt = "Save to (from project root, Enter = root, @bin = dotfiles) ", completion = "dir" },
      function(where)
        if where == nil then
          return
        end
        if not name_done then
          vim.wait(2500, function()
            return name_done
          end, 50)
        end
        local default = suggestion or M.slug(desc)
        vim.ui.input({ prompt = "Name (end with .go for Go) ", default = default }, function(name)
          if name == nil then
            return
          end
          name = vim.trim(name)
          if name == "" then
            name = default
          end
          local t, err = M.target(root, where, name)
          if not t then
            return say(err, vim.log.levels.ERROR)
          end
          local function run()
            M.generate(desc, t)
          end
          if vim.uv.fs_stat(t.path) then
            vim.ui.select(
              { "Overwrite", "Cancel" },
              { prompt = vim.fn.fnamemodify(t.path, ":~") .. " exists" },
              function(choice)
                if choice == "Overwrite" then
                  run()
                end
              end
            )
          else
            run()
          end
        end)
      end
    )
  end)
end

return M

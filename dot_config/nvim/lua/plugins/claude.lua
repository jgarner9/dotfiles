-- Claude Code integration via sidekick.nvim (CLI terminal only; NES/Copilot is intentionally off).
--   <leader>ac  toggle chat      <leader>aq  quick ask (opens chat)   <leader>aS  inline snippet (headless)
--   <leader>ar  resume last session      <leader>aa  focus chat
--   Inside the chat: <leader>ac (terminal-normal mode) or <a-c> (any mode) hides it

--- Selection (visual) or current line, plus file context, as a prompt-ready string.
local function context_block()
  local mode = vim.fn.mode()
  local text
  if mode:match("^[vV\22]") then
    text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode }), "\n")
  else
    text = vim.api.nvim_get_current_line()
  end
  return ("File: %s (%s)\n```%s\n%s\n```"):format(vim.fn.expand("%:p"), vim.bo.filetype, vim.bo.filetype, text)
end

--- Run `claude -p` headless and show the reply in a float; `y` yanks the code, `i` inserts it below the cursor.
local function inline(question, code_only)
  local ctx = context_block()
  local target = { buf = vim.api.nvim_get_current_buf(), row = vim.api.nvim_win_get_cursor(0)[1] }
  local system = code_only and "Reply with ONLY a single fenced code block. No explanation."
    or "Be concise. Answer directly."
  local win = Snacks.win({
    text = { "Thinking…" },
    ft = "markdown",
    width = 0.6,
    height = 0.5,
    border = "rounded",
    title = " Claude ",
    wo = { wrap = true, conceallevel = 2 },
    keys = { q = "close" },
  })
  vim.system({
    "claude", "-p", "--no-session-persistence",
    "--disallowed-tools", "Edit", "Write", "Bash", "NotebookEdit",
    "--append-system-prompt", system,
  }, { stdin = question .. "\n\n" .. ctx, text = true, cwd = vim.fn.getcwd() }, function(res)
    vim.schedule(function()
      if not win:valid() then
        return
      end
      local out = vim.trim(res.code == 0 and res.stdout or ("claude exited %d\n%s"):format(res.code, res.stderr))
      local code = out:match("```[^\n]*\n(.-)\n```")
      vim.bo[win.buf].modifiable = true
      vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, vim.split(out, "\n"))
      vim.bo[win.buf].modifiable = false
      local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, fn, { buffer = win.buf, desc = desc, nowait = true })
      end
      map("y", function()
        vim.fn.setreg("+", code or out)
        vim.notify("Yanked " .. (code and "code block" or "reply"))
        win:close()
      end, "Yank code")
      map("i", function()
        win:close()
        if vim.api.nvim_buf_is_valid(target.buf) then
          vim.api.nvim_buf_set_lines(target.buf, target.row, target.row, false, vim.split(code or out, "\n"))
        end
      end, "Insert below cursor")
    end)
  end)
end

local function ask(code_only)
  local visual = vim.fn.mode():match("^[vV\22]")
  if visual then
    vim.cmd("normal! \27") -- leave visual mode so the '< '> marks are set; context_block re-reads via getpos
  end
  vim.ui.input({ prompt = code_only and "Snippet: " or "Ask Claude: " }, function(q)
    if q and q ~= "" then
      inline(q, code_only)
    end
  end)
end

return {
  {
    "folke/sidekick.nvim",
    opts = {
      nes = { enabled = false },
      copilot = { status = { enabled = false } },
      cli = {
        win = {
          keys = {
            -- space is typed text in terminal-insert mode, so <leader>ac can't work there; <a-c> hides from insert mode
            hide_alt_c = { "<a-c>", "hide", mode = "nt", desc = "hide the terminal window" },
          },
        },
        mux = { enabled = true, backend = "zellij" }, -- sessions survive nvim restarts
        tools = {
          -- sidekick doesn't wire up a tool's `continue` flag, so expose it as its own tool
          claude_continue = { cmd = { "claude", "--continue" }, is_proc = "\\<claude\\>" },
        },
      },
    },
    -- stylua: ignore
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
      { "<leader>ac", function()
          -- sidekick's toggle() only refocuses when you're already inside the terminal, so hide explicitly
          if vim.bo.filetype == "sidekick_terminal" then
            require("sidekick.cli").hide()
          else
            require("sidekick.cli").toggle({ name = "claude", focus = true })
          end
        end, desc = "Claude Chat Toggle" },
      { "<leader>aa", function() require("sidekick.cli").focus({ name = "claude" }) end, desc = "Claude Focus", mode = { "n", "t" } },
      { "<leader>ar", function() require("sidekick.cli").toggle({ name = "claude_continue", focus = true }) end, desc = "Claude Resume Last" },
      { "<leader>aq", function()
          vim.ui.input({ prompt = "Ask Claude: " }, function(q)
            if q and q ~= "" then
              require("sidekick.cli").send({ name = "claude", msg = q .. "\n\n{this}", focus = true, submit = true })
            end
          end)
        end, mode = { "n", "x" }, desc = "Claude Quick Ask (chat)" },
      { "<leader>aS", function() ask(true) end, mode = { "n", "x" }, desc = "Claude Snippet (inline)" },
      { "<leader>aA", function() ask(false) end, mode = { "n", "x" }, desc = "Claude Answer (inline)" },
      { "<leader>at", function() require("sidekick.cli").send({ name = "claude", msg = "{this}" }) end, mode = { "x", "n" }, desc = "Send This" },
      { "<leader>af", function() require("sidekick.cli").send({ name = "claude", msg = "{file}" }) end, desc = "Send File" },
      { "<leader>av", function() require("sidekick.cli").send({ name = "claude", msg = "{selection}" }) end, mode = "x", desc = "Send Selection" },
      { "<leader>ap", function() require("sidekick.cli").prompt() end, mode = { "n", "x" }, desc = "Claude Prompt Picker" },
      { "<leader>ad", function() require("sidekick.cli").close() end, desc = "Detach Claude Session" },
    },
  },
}

local config = require("bud.config")
local sync = require("bud.sync")

local function fake_dotsync(T, json, code)
  T.bin(
    "dotsync",
    ("#!/bin/sh\necho \"$@\" > %q\ncat <<'JSON'\n%s\nJSON\nexit %d\n"):format(
      T.work .. "/dotsync.args",
      json,
      code or 0
    )
  )
end

local function run(T, force)
  sync.run(force)
  T.wait(function()
    return not sync.running
  end)
end

return {
  {
    "synced: one notice with the restart hint when nvim config changed",
    function(T)
      fake_dotsync(
        T,
        '{"status":"synced","message":"ok","changed":["dot_zshrc","dot_config/nvim/init.lua"],"drift":[],"nvim_changed":true}'
      )
      local notes = T.notifications()
      run(T, false)
      T.eq(sync.last.status, "synced")
      T.eq(#notes, 1)
      T.contains(notes[1].msg, "Dotfiles synced (2 files)")
      T.contains(notes[1].msg, "restart Neovim")
      T.eq(vim.trim(vim.fn.readfile(T.work .. "/dotsync.args")[1]), "--json")
    end,
  },
  {
    "quiet results stay quiet unless forced",
    function(T)
      fake_dotsync(
        T,
        '{"status":"skipped_throttle","message":"ran 10s ago","changed":[],"drift":[],"nvim_changed":false}'
      )
      local notes = T.notifications()
      run(T, false)
      T.eq(#notes, 0)
      run(T, true)
      T.eq(#notes, 1)
      T.eq(vim.trim(vim.fn.readfile(T.work .. "/dotsync.args")[1]), "--json --force")
    end,
  },
  {
    "drift warns with the files and shows in the statusline",
    function(T)
      fake_dotsync(
        T,
        '{"status":"skipped_drift","message":"x","changed":["a"],"drift":[".zshrc"],"nvim_changed":false}'
      )
      local notes = T.notifications()
      run(T, false)
      T.eq(notes[1].level, vim.log.levels.WARN)
      T.contains(notes[1].msg, "- .zshrc")
      T.contains(require("bud.ui.statusline").text(), config.icons.warn)
    end,
  },
  {
    "errors and garbage output are reported",
    function(T)
      fake_dotsync(T, '{"status":"error","message":"pull failed","changed":[],"drift":[],"nvim_changed":false}', 1)
      local notes = T.notifications()
      run(T, false)
      T.contains(notes[1].msg, "Dotfile sync failed: pull failed")
      T.bin("dotsync", "#!/bin/sh\necho oops >&2\nexit 3\n")
      run(T, false)
      T.eq(sync.last.status, "error")
      T.eq(sync.last.message, "oops")
    end,
  },
}

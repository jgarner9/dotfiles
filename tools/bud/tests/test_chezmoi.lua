local config = require("bud.config")
local chezmoi = require("bud.chezmoi")

-- A fake $HOME with ~/.config/app managed, and a fake chezmoi that lists it
-- and logs every other call.
local function setup(T)
  local home = T.project({
    [".config/app/app.conf"] = "x",
    [".config/other/other.conf"] = "x",
  })
  local log = T.work .. "/chezmoi.log"
  vim.fn.delete(log)
  T.bin(
    "chezmoi",
    ([[#!/bin/sh
if [ "$1" = managed ]; then
  printf '%%s\n' %q %q %q
  exit 0
fi
echo "$@" >> %q
if [ -n "$CHEZMOI_FAIL" ]; then echo "$CHEZMOI_FAIL" >&2; exit 1; fi
]]):format(home .. "/.config", home .. "/.config/app", home .. "/.config/app/app.conf", log)
  )
  local old_home = vim.env.HOME
  vim.env.HOME = home
  config.options.chezmoi.enabled = true
  chezmoi.invalidate()
  local function done()
    vim.env.HOME = old_home
    config.options.chezmoi.enabled = false
    vim.env.CHEZMOI_FAIL = nil
  end
  local function calls()
    T.wait(chezmoi.idle)
    return vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
  end
  return home, calls, done
end

return {
  {
    "managed files are re-added, new ones in a managed folder are added",
    function(T)
      local home, calls, done = setup(T)
      local notes = T.notifications()
      chezmoi.saved(home .. "/.config/app/app.conf")
      chezmoi.saved(home .. "/.config/app/new.conf")
      local got = calls()
      done()
      T.eq(got, {
        "re-add " .. home .. "/.config/app/app.conf",
        "add " .. home .. "/.config/app/new.conf",
      })
      notes = vim.tbl_filter(function(n)
        return n.opts and n.opts.title == "chezmoi"
      end, notes)
      T.eq(#notes, 1)
      T.contains(notes[1].msg, "new.conf to chezmoi")
      T.ok(chezmoi.managed[home .. "/.config/app/new.conf"])
    end,
  },
  {
    "files outside managed folders, or only in skipped ones, are left alone",
    function(T)
      local home, calls, done = setup(T)
      chezmoi.saved(home .. "/.config/other/other.conf")
      chezmoi.saved(home .. "/.config/loose.conf")
      chezmoi.saved(home .. "/notes.txt")
      chezmoi.saved("/tmp/elsewhere.txt")
      local got = calls()
      done()
      T.eq(got, {})
    end,
  },
  {
    "saving through a buffer runs it; failures warn",
    function(T)
      local home, calls, done = setup(T)
      local notes = T.notifications()
      vim.env.CHEZMOI_FAIL = "boom"
      vim.cmd.edit(vim.fn.fnameescape(home .. "/.config/app/app.conf"))
      vim.cmd("silent write")
      local got = calls()
      done()
      T.eq(got, { "re-add " .. home .. "/.config/app/app.conf" })
      local warn = vim.tbl_filter(function(n)
        return n.opts and n.opts.title == "chezmoi"
      end, notes)[1]
      T.eq(warn.level, vim.log.levels.WARN)
      T.contains(warn.msg, "boom")
    end,
  },
  {
    "disabled does nothing",
    function(T)
      local home, calls, done = setup(T)
      config.options.chezmoi.enabled = false
      chezmoi.saved(home .. "/.config/app/app.conf")
      local got = calls()
      done()
      T.eq(got, {})
    end,
  },
}

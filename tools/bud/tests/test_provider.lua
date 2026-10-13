local provider = require("bud.provider")
local log = require("bud.log")

local function request(T, opts)
  local res = { deltas = {} }
  opts.on_text = function(delta, full)
    table.insert(res.deltas, delta)
    res.text = full
  end
  opts.on_done = function(text, ev)
    res.done, res.text, res.ev = true, text, ev
  end
  opts.on_error = function(msg, info)
    res.done, res.error, res.info = true, msg, info
  end
  res.handle = provider.request(opts)
  return res
end

return {
  {
    "a request streams text and finishes",
    function(T)
      local root = T.project({})
      local res = request(T, { mode = "quick", root = root, prompt = "what is 2+2", request = "what is 2+2" })
      T.wait(function()
        return res.done
      end)
      T.eq(res.error, nil)
      T.eq(res.text, "echo: what is 2+2")
      T.ok(#res.deltas > 1, "streamed in chunks")
      T.eq(provider.active, 0)
      T.eq(provider.last.usage.output_tokens, #"echo: what is 2+2")
    end,
  },
  {
    "quick requests use haiku, no tools, no session, the shared instructions",
    function(T)
      provider.drop_spare()
      local before = #T.claude_runs()
      local res = request(T, { mode = "quick", root = T.project({}), prompt = "hi" })
      T.wait(function()
        return res.done
      end)
      local run = T.claude_runs()[before + 1]
      local args = table.concat(run.args, " ")
      T.contains(args, "--model haiku")
      T.contains(args, "--tools  --strict-mcp-config")
      T.contains(args, "--no-session-persistence")
      T.match(args, "instructions%-shared%-")
      T.contains(args, "--input-format stream-json")
    end,
  },
  {
    "the warm spare is used once, then replaced",
    function(T)
      provider.drop_spare()
      local root = T.project({})
      provider.prewarm(root)
      local before = #T.claude_runs()
      T.wait(function()
        return #T.claude_runs() > before - 1
      end)
      local res = request(T, { mode = "quick", root = root, prompt = "one" })
      T.wait(function()
        return res.done
      end)
      -- the request ran on the spare, and a new spare started after it
      T.wait(function()
        return #T.claude_runs() == before + 1
      end, 3000, "one replacement spare")
      local res2 = request(T, { mode = "write", root = root, prompt = "two" })
      T.wait(function()
        return res2.done
      end)
      T.eq(res2.text, "echo: two", "fresh process: no history from the first request")
    end,
  },
  {
    "mode instructions travel with the message",
    function(T)
      local root = T.project({})
      local res = request(T, { mode = "write", root = root, prompt = "do it" })
      T.wait(function()
        return res.done
      end)
      local e = log.entries()[1]
      T.contains(e.prompt, "<instructions>")
      T.contains(e.prompt, "Reply with ONLY the code to insert")
      T.eq(e.mode, "write")
      T.eq(e.response, "echo: do it")
    end,
  },
  {
    "cancel ends with a cancelled error",
    function(T)
      T.control({ delay_ms = 100, replies = { string.rep("x", 200) } })
      local res = request(T, { mode = "quick", root = T.project({}), prompt = "slow" })
      T.wait(function()
        return res.text ~= nil
      end)
      res.handle.cancel()
      T.wait(function()
        return res.done
      end)
      T.eq(res.error, "Cancelled")
      T.ok(res.info.cancelled)
      T.eq(provider.active, 0)
    end,
  },
  {
    "an error result reaches on_error and the log",
    function(T)
      T.control({ error = "rate limited" })
      local res = request(T, { mode = "quick", root = T.project({}), prompt = "x", request = "x" })
      T.wait(function()
        return res.done
      end)
      T.eq(res.error, "rate limited")
      T.eq(log.entries()[1].error, "rate limited")
    end,
  },
  {
    "a missing CLI fails cleanly",
    function(T)
      local config = require("bud.config")
      local saved = config.options.claude
      config.options.claude = "/nonexistent/claude"
      provider.drop_spare()
      local res = request(T, { mode = "quick", root = T.project({}), prompt = "x" })
      T.wait(function()
        return res.done
      end)
      T.ok(res.error)
      config.options.claude = saved
    end,
  },
  {
    "a long-lived process keeps history and can resume",
    function(T)
      local root = T.project({})
      local p = provider.Proc.spawn({ model = "sonnet", root = root, persist = true })
      local done = 0
      p:send("first", {
        on_done = function()
          done = done + 1
        end,
      })
      T.wait(function()
        return done == 1
      end)
      T.match(p.session_id, "^fake%-")
      p:send("second", {
        on_done = function()
          done = done + 1
        end,
      })
      T.wait(function()
        return done == 2
      end)
      local sid = p.session_id
      p:kill()
      T.wait(function()
        return p.dead
      end)
      local p2 = provider.Proc.spawn({ model = "sonnet", root = root, persist = true, resume = sid })
      local got
      p2:send("third", {
        on_done = function()
          got = p2.session_id
        end,
      })
      T.wait(function()
        return got
      end)
      T.eq(got, sid)
      local args = table.concat(T.claude_runs()[#T.claude_runs()].args, " ")
      T.contains(args, "--resume " .. sid)
      T.ok(not args:find("no-session-persistence", 1, true))
      p2:close()
    end,
  },
}

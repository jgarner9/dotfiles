local stream = require("bud.stream")
local util = require("bud.util")

return {
  {
    "decoder joins lines split across chunks",
    function(T)
      local got = {}
      local feed = stream.decoder(function(ev)
        table.insert(got, ev)
      end)
      feed('{"type":"a"}\n{"ty')
      feed('pe":"b"}\n\n')
      feed('{"type":"c"}')
      T.eq(#got, 2)
      feed(nil)
      T.eq(
        vim.tbl_map(function(e)
          return e.type
        end, got),
        { "a", "b", "c" }
      )
    end,
  },
  {
    "decoder skips lines that aren't JSON",
    function(T)
      local got = {}
      local feed = stream.decoder(function(ev)
        table.insert(got, ev)
      end)
      feed('warning: something\n{"type":"ok"}\n')
      T.eq(#got, 1)
      T.eq(got[1].type, "ok")
    end,
  },
  {
    "text_delta reads only text deltas",
    function(T)
      T.eq(
        stream.text_delta({
          type = "stream_event",
          event = { type = "content_block_delta", delta = { type = "text_delta", text = "hi" } },
        }),
        "hi"
      )
      T.eq(
        stream.text_delta({
          type = "stream_event",
          event = { type = "content_block_delta", delta = { type = "input_json_delta", partial_json = "{" } },
        }),
        nil
      )
      T.eq(stream.text_delta({ type = "assistant" }), nil)
    end,
  },
  {
    "user_message is one stream-json line",
    function(T)
      local line = stream.user_message("hello\nworld")
      T.eq(line:sub(-1), "\n")
      T.eq(select(2, line:gsub("\n", "")), 1)
      local msg = vim.json.decode(line)
      T.eq(msg, { type = "user", message = { role = "user", content = "hello\nworld" } })
    end,
  },
  {
    "strip_fences keeps only the code",
    function(T)
      T.eq(util.strip_fences("```lua\nlocal x = 1\n```"), "local x = 1")
      T.eq(util.strip_fences("Here you go:\n```go\nfmt.Println()\n```\nDone."), "fmt.Println()")
      T.eq(util.strip_fences("```sh\necho hi\n"), "echo hi\n")
      T.eq(util.strip_fences("\nplain\n\n"), "plain")
    end,
  },
  {
    "truncate and relpath",
    function(T)
      T.eq(util.truncate("a  b\nc", 10), "a b c")
      T.eq(util.truncate("abcdefghij", 5), "abcd…")
      T.eq(util.relpath("/x/y/z.lua", "/x"), "y/z.lua")
      T.eq(util.relpath("", "/x"), "[No Name]")
    end,
  },
  {
    "uuid looks like a v4 uuid",
    function(T)
      T.match(util.uuid(), "^%x+%-%x+%-4%x+%-[89ab]%x+%-%x+$")
    end,
  },
}

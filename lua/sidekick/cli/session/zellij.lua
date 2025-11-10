local Config = require("sidekick.config")
local Config = require("sidekick.config")
local Util = require("sidekick.util")

---@class sidekick.cli.muxer.Zellij: sidekick.cli.Session
---@field mux_pane_id string
---@field zellij string
local M = {}
M.__index = M
M.priority = 50
M.external = false

M.tpl = [[
layout {
    pane command="{cmd}" {
      borderless true
      focus true
      name "{name}"
      close_on_exit true
      {args}
   }
}
session_serialization false
]]

---@return sidekick.cli.terminal.Cmd?
function M:terminal()
  local layout = M.tpl
  layout = layout:gsub("{cmd}", self.tool.cmd[1])
  layout = layout:gsub("{name}", self.tool.name)
  if #self.tool.cmd == 1 then
    layout = layout:gsub("{args}", "")
  else
    local args = vim.list_slice(self.tool.cmd, 2)
    layout = layout:gsub("{args}", "args " .. table.concat(
      vim.tbl_map(function(a)
        return ("%q"):format(a)
      end, args),
      " "
    )) --[[@as string]]
  end

  local session = self.sid

  local layout_file = Config.state("zellij-layout-" .. session .. ".kdl")
  vim.fn.writefile(vim.split(layout, "\n"), layout_file)
  Util.set_state(session, { tool = self.tool.name, cwd = self.cwd })

  return {
    cmd = { "zellij", "--layout", layout_file, "attach", "--create", session },
    env = {
      ZELLIJ = false,
      ZELLIJ_SESSION_NAME = false,
      ZELLIJ_PANE_ID = false,
    },
  }
end

---@return sidekick.cli.terminal.Cmd?
function M:start()
  if vim.env.ZELLIJ and Config.cli.mux.create ~= "terminal" then
    Util.warn({
      ("Zellij does not support `opts.cli.mux.create = %q`."):format(Config.cli.mux.create),
      ("Falling back to `%q`."):format("terminal"),
      "Please update your config.",
    })
  end
  -- Zellij's scripting API is too limited, so
  -- always run embedded sessions
  return self:terminal()
end

---@return sidekick.cli.terminal.Cmd?
function M:attach()
  -- Zellij's scripting API is too limited, so
  -- always run embedded sessions
  return self:terminal()
end

function M.sessions()
  local sessions = Util.exec({ "zellij", "list-sessions", "-ns" }, { notify = false }) or {}
  local ret = {} ---@type sidekick.cli.session.State[]
  local Terminal = require("sidekick.cli.terminal")

  local function find_pids(sid)
    local pids = {} ---@type integer[]
    for _, t in pairs(Terminal.terminals) do
      if t.mux_backend == "zellij" and t.mux_session == sid then
        vim.list_extend(pids, t.pids or {})
      end
    end
    return pids
  end

  for _, s in ipairs(sessions) do
    local state = Util.get_state(s)
    if state then
      ret[#ret + 1] = {
        id = "zellij: " .. s,
        cwd = state.cwd,
        tool = state.tool,
        mux_session = s,
        mux_pane_id = "zellij:" .. s,
        pids = find_pids(s),
      }
    end
  end
  return ret
end

function M:send(text)
  -- Sending keys is intentionally unsupported; rely on terminal child
  require("sidekick.util").warn({ "Zellij backend cannot send text directly." })
end

function M:submit()
  -- No direct submit; noop
end

function M:focus()
  -- Focus handled by embedded terminal
  return self
end

function M:blur()
  return self
end

-- function M:dump()
--   do
--     -- sigh, another broken zellij feature
--     -- dump-screen doesn't include ansi escape sequences
--     -- just the raw text
--     return
--   end
--   local tmp = Config.state("zellij-dump.txt")
--   local ok = Util.exec({ "zellij", "-s", self.mux_session, "action", "dump-screen", "-f", tmp }, {
--     notify = true,
--   })
--   if not ok then
--     return
--   end
--   local f = io.open(tmp, "r")
--   if not f then
--     return
--   end
--   vim.fn.delete(tmp)
--   local content = f:read("*a")
--   f:close()
--   return content
-- end

return M

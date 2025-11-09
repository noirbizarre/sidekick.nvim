---@class sidekick.cli.session.Opencode: sidekick.cli.Session
---@field port number
---@field pid number
---@field base_url string
local M = {}
M.__index = M
M.priority = 20
M.external = true

function M.sessions()
  local Procs = require("sidekick.cli.procs")
  local Util = require("sidekick.util")

  -- Get listening ports for all listening TCP processes (single lsof call)
  local lines = Util.exec({ "lsof", "-w", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-Fn", "-Fp" }, { notify = false }) or {}

  local ports = {} ---@type table<number, number>
  local current_pid ---@type number?
  for _, line in ipairs(lines) do
    local pid = line:match("^p(%d+)$")
    if pid then
      current_pid = tonumber(pid)
    else
      local port = line:match("^n.*:(%d+)$")
      if port and current_pid then
        ports[current_pid] = tonumber(port)
      end
    end
  end

  -- Optional tmux pane discovery (only if tmux exists)
  local panes_by_pid = {} ---@type table<number,{pane_id:string,session_name:string}>
  if vim.fn.executable("tmux") == 1 then
    local PANE_FORMAT = "#{session_id}:#{pane_id}:#{pane_pid}:#{session_name}"
    local pane_lines = Util.exec({ "tmux", "list-panes", "-a", "-F", PANE_FORMAT }, { notify = false }) or {}
    for _, line in ipairs(pane_lines) do
      local session_id, pane_id, pane_pid, session_name = line:match("^(%$%d+):(%%%d+):(%d+):(.-)$")
      if pane_id and pane_pid and session_name then
        local pid = tonumber(pane_pid)
        if pid then
          panes_by_pid[pid] = { pane_id = pane_id, session_name = session_name, session_id = session_id }
        end
      end
    end
  end

  local ret = {} ---@type sidekick.cli.session.State[]
  for pid, port in pairs(ports) do
    local proc = vim.api.nvim_get_proc(pid)
    if proc and proc.name == "opencode" then
      local pane = panes_by_pid[pid]
      ret[#ret + 1] = {
        id = "opencode-" .. pid,
        pid = pid,
        tool = "opencode",
        cwd = Procs.cwd(pid) or "",
        port = port,
        pids = Procs.pids(pid),
        mux_session = pane and pane.session_name or tostring(pid),
        tmux_pane_id = pane and pane.pane_id or nil,
        base_url = ("http://localhost:%d"):format(port),
      }
    end
  end
  return ret
end

function M:attach() end

function M:focus()
  if self.tmux_pane_id and vim.fn.executable("tmux") == 1 then
    local Util = require("sidekick.util")
    Util.exec({ "tmux", "select-pane", "-t", self.tmux_pane_id })
    if self.tool.mux_focus then
      Util.exec({ "tmux", "send-keys", "-t", self.tmux_pane_id, "Escape", "[", "I" })
    end
  end
  return self
end

function M:is_running()
  return self.pid and vim.api.nvim_get_proc(self.pid) ~= nil
end

function M:send(text)
  require("sidekick.util").curl(self.base_url .. "/tui/append-prompt", {
    method = "POST",
    data = { text = text },
  })
end

function M:submit()
  require("sidekick.util").curl(self.base_url .. "/tui/submit-prompt", {
    method = "POST",
    data = {},
  })
end

-- only register on Unix-like systems with lsof available
if vim.fn.has("win32") == 0 and vim.fn.executable("lsof") == 1 then
  require("sidekick.cli.session").register("opencode", M)
end

---@type sidekick.cli.Config
return {
  cmd = { "opencode" },
  env = {
    OPENCODE_THEME = "system",
  },
  is_proc = "\\<opencode\\>",
  url = "https://github.com/sst/opencode",
  continue = { "--continue" },
  native_scroll = true,
}

---@module 'luassert'

local Cli = require("sidekick.cli")
local Session = require("sidekick.cli.session")

-- We test that focusing operations fall back to session:focus() when
-- there is no terminal backend (external mux session).
-- We stub Session.sessions() to simulate an existing running external session
-- that is not yet attached. Attaching should call our overridden focus method
-- exactly once when focus is requested.

local Config = require("sidekick.config")

describe("cli focus fallback", function()
  local focused
  local original_sessions
  local original_attach
  local original_new

  before_each(function()
    focused = 0
    original_sessions = Session.sessions
    original_attach = Session.attach
    original_new = Session.new

    -- Create a fake external session state returned by Session.sessions()
    local fake_state = {
      id = "fake-session-id",
      sid = "fake-session-id",
      cwd = vim.fn.getcwd(),
      tool = "copilot", -- pick an existing tool to avoid missing tool logic
      backend = "tmux",
      started = true,
      external = true,
      is_running = function()
        return true
      end,
      attach = function(self)
        return self
      end,
      focus = function(self)
        focused = focused + 1
        return self
      end,
      is_attached = function(self)
        return false -- start unattached
      end,
    }

    -- Return our fake session list
    Session.sessions = function()
      return { fake_state }
    end

    -- Ensure attach just returns the provided session (no terminal spawn)
    Session.attach = function(session)
      -- simulate attachment
      local attached = false
      if session.is_attached then
        attached = session:is_attached()
      end
      session.is_attached = function(self)
        return true
      end
      if session.focus then
        session:focus()
      end
      return session
    end

    -- Keep Session.new behavior but allow creating a matching session if needed
    Session.new = function(opts)
      local s = original_new(opts)
      s.backend = "tmux"
      s.started = true
      s.external = true
      function s:is_running()
        return true
      end
      function s:attach()
        return nil
      end
      function s:focus()
        focused = focused + 1
        return self
      end
      return s
    end
  end)

  after_each(function()
    Session.sessions = original_sessions
    Session.attach = original_attach
    Session.new = original_new
  end)

  it("calls session:focus() on toggle when initially attaching", function()
    Cli.toggle({ name = "copilot", focus = true })
    vim.wait(20)
    assert.are.equal(1, focused)
  end)

  it("does not call session:focus() when focus explicitly disabled", function()
    Cli.toggle({ name = "copilot", focus = false })
    assert.are.equal(0, focused)
  end)

  it("calls session:focus() on focus() without terminal", function()
    Cli.focus({ name = "copilot" })
    vim.wait(20)
    assert.are.equal(1, focused)
  end)
end)

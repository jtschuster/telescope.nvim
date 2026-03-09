local async = require "plenary.async"

describe("get_workspace_symbols_requester", function()
  local original_buf_request_all

  before_each(function()
    original_buf_request_all = vim.lsp.buf_request_all
  end)

  after_each(function()
    vim.lsp.buf_request_all = original_buf_request_all
    -- Force module reload so each test gets a fresh requester
    package.loaded["telescope.builtin.__lsp"] = nil
  end)

  it("returns locations for a single non-stale request", function()
    vim.lsp.buf_request_all = function(_, _, _, callback)
      -- Simulate a fast LSP server responding with no symbols
      vim.schedule(function()
        callback {}
      end)
      return function() end
    end

    local lsp_module = require "telescope.builtin.__lsp"
    local requester = lsp_module._get_workspace_symbols_requester(0, {})

    local result = nil
    local done = false

    async.run(function()
      result = requester "test"
      done = true
    end)

    vim.wait(5000, function()
      return done
    end)

    assert(done, "request did not complete in time")
    -- No client results → empty locations
    assert.are.same({}, result)
  end)

  it("returns empty table for stale request when a newer request has started", function()
    vim.lsp.buf_request_all = function(_, _, _, callback)
      -- Return a cancel function that triggers the callback with empty results
      -- (simulating: cancellation causes the LSP to respond)
      return function()
        callback {}
      end
    end

    local lsp_module = require "telescope.builtin.__lsp"
    local requester = lsp_module._get_workspace_symbols_requester(0, {})

    local result1 = nil
    local done1 = false

    -- Start first request — will yield at rx() since callback hasn't been called
    async.run(function()
      result1 = requester "first"
      done1 = true
    end)

    -- First request is now blocked at rx(), waiting for tx1 to be called
    assert(not done1, "first request should be blocked at rx()")

    -- Start second request — this increments current_request_id and calls cancel(),
    -- which fires the old tx (via our mock), unblocking the first request's rx()
    async.run(function()
      -- We don't need the result; just starting this triggers cancel() on request 1
      requester "second"
    end)

    -- The first request should now be unblocked and detect it's stale
    vim.wait(5000, function()
      return done1
    end)

    assert(done1, "first request was not unblocked by cancel")
    assert.are.same({}, result1)
  end)

  it("sequential non-overlapping requests each return normally", function()
    local call_count = 0

    vim.lsp.buf_request_all = function(_, _, _, callback)
      call_count = call_count + 1
      -- Respond immediately via schedule (no symbols)
      vim.schedule(function()
        callback {}
      end)
      return function() end
    end

    local lsp_module = require "telescope.builtin.__lsp"
    local requester = lsp_module._get_workspace_symbols_requester(0, {})

    local result1 = nil
    local result2 = nil
    local done1 = false
    local done2 = false

    -- Sequential non-overlapping requests should both return normally (not stale)
    async.run(function()
      result1 = requester "first"
      done1 = true
    end)

    vim.wait(5000, function()
      return done1
    end)

    async.run(function()
      result2 = requester "second"
      done2 = true
    end)

    vim.wait(5000, function()
      return done2
    end)

    assert(done1, "first sequential request did not complete")
    assert(done2, "second sequential request did not complete")
    assert.are.same({}, result1)
    assert.are.same({}, result2)
    assert.are.same(2, call_count)
  end)
end)

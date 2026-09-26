local M = {}

---@param root string
---@return string
function M.system_path(root)
  return vim.fs.joinpath(vim.fn.stdpath('cache'), 'intellij', vim.fn.sha256(root):sub(1, 12))
end

---@return boolean
function M.ready()
  local server = require('intellij.server')
  local dir = server.dir()
  local problem = not dir and 'server not installed, run :IntelliJ install'
    or not server.eula_accepted(dir) and 'EULA not accepted, run :IntelliJ eula'
  if problem then
    vim.notify_once('intellij: ' .. problem, vim.log.levels.WARN)
  end
  return not problem
end

---@param dispatchers vim.lsp.rpc.Dispatchers
---@param config vim.lsp.ClientConfig
---@return vim.lsp.rpc.Client
function M.cmd(dispatchers, config)
  local server = require('intellij.server')
  local dir = server.dir()
  if not dir then
    error('intellij: server not installed, run :IntelliJ install', 0)
  end
  if not server.eula_accepted(dir) then
    error('intellij: EULA not accepted, run :IntelliJ eula', 0)
  end
  local root = config.root_dir or vim.fn.getcwd()
  local argv = {
    server.executable(dir),
    '--stdio',
    '--system-path',
    M.system_path(root),
    '--eula',
    assert(server.eula_hash(dir)),
  }

  local env = {}
  local jvm_options = require('intellij.config').get().jvm_options
  if #jvm_options > 0 then
    local current = vim.env.IJ_JAVA_OPTIONS
    local extra = table.concat(jvm_options, ' ')
    env.IJ_JAVA_OPTIONS = current and current ~= '' and (current .. ' ' .. extra) or extra
  end

  -- The launcher writes debug output to stdout whenever IJ_LAUNCHER_DEBUG is set, and
  -- vim.system() cannot unset inherited variables, so hide it while spawning.
  local debug = vim.env.IJ_LAUNCHER_DEBUG
  vim.env.IJ_LAUNCHER_DEBUG = nil
  local ok, rpc = pcall(vim.lsp.rpc.start, argv, dispatchers, { cwd = root, env = env })
  vim.env.IJ_LAUNCHER_DEBUG = debug
  if not ok then
    error(rpc, 0)
  end
  return rpc
end

---@param bufnr integer
---@return string?
local function outermost_pom(bufnr)
  local dir = vim.fs.root(bufnr, 'pom.xml')
  while dir do
    local parent = vim.fs.dirname(dir)
    if parent == dir or not vim.uv.fs_stat(vim.fs.joinpath(parent, 'pom.xml')) then
      break
    end
    dir = parent
  end
  return dir
end

---@param bufnr integer
---@param on_dir fun(root_dir?: string)
function M.root_dir(bufnr, on_dir)
  local root = vim.fs.root(bufnr, {
    { 'settings.gradle', 'settings.gradle.kts', 'MODULE.bazel', 'WORKSPACE', 'WORKSPACE.bazel' },
  }) or outermost_pom(bufnr) or vim.fs.root(bufnr, {
    { 'pom.xml', 'build.gradle', 'build.gradle.kts', 'BUILD.bazel' },
    '.git',
  })
  if root then
    on_dir(root)
  end
end

---@param config? vim.lsp.ClientConfig
---@return table
function M.init_options(config)
  local opts = {
    intellijExtensions = true,
    defaultSdk = require('intellij.config').get().java_home,
  }
  return vim.tbl_deep_extend('force', opts, config and config.init_options or {})
end

---@param params lsp.InitializeParams
---@param config vim.lsp.ClientConfig
function M.before_init(params, config)
  params.initializationOptions = M.init_options(config)
end

local exit_hints = {
  [7] = 'this server build has expired, run :IntelliJ install to update',
  [11] = 'EULA not accepted, run :IntelliJ eula',
}

---@param code integer
function M.on_exit(code)
  local hint = exit_hints[code]
  if hint then
    vim.schedule(function()
      vim.notify('intellij: ' .. hint, vim.log.levels.ERROR)
    end)
  end
end

---@class intellij.ImportFolder
---@field folderUri string
---@field tool? string
---@field status 'SUCCESS'|'FAILED'|'BLOCKED'
---@field message? string

---@class intellij.WorkspaceImportState
---@field phase 'IN_PROGRESS'|'FINISHED'|'FAILED'|'CANCELLED'
---@field folders? intellij.ImportFolder[]

---@class intellij.ImportLog
---@field type integer
---@field message string
---@field tool? string
---@field started? boolean
---@field failed? boolean
---@field succeeded? boolean

---@param client_id integer
---@param msg string
---@param status 'running'|'success'|'failed'
local function progress(client_id, msg, status)
  vim.api.nvim_echo({ { msg } }, status ~= 'running', {
    kind = 'progress',
    id = 'intellij.import.' .. client_id,
    source = 'intellij',
    title = 'intellij',
    status = status,
  })
end

local phase_message = {
  FINISHED = 'workspace imported',
  FAILED = 'workspace import failed',
  CANCELLED = 'workspace import cancelled',
}

--- The server numbers document versions by counting changes from 0, while
--- Neovim uses the buffer's changedtick, so its versioned edits always look
--- stale once the buffer has been modified. Drop the versions before applying.
---@param edit? lsp.WorkspaceEdit
---@return lsp.WorkspaceEdit?
function M.unversion(edit)
  for _, change in ipairs(edit and edit.documentChanges or {}) do
    if change.textDocument then
      change.textDocument.version = vim.NIL
    end
  end
  return edit
end

---@type table<string, lsp.Handler>
M.handlers = {
  ['textDocument/rename'] = function(err, result, ctx, config)
    return vim.lsp.handlers['textDocument/rename'](err, M.unversion(result), ctx, config)
  end,

  ---@param result lsp.ApplyWorkspaceEditParams
  ['workspace/applyEdit'] = function(err, result, ctx, config)
    if result then
      M.unversion(result.edit)
    end
    return vim.lsp.handlers['workspace/applyEdit'](err, result, ctx, config)
  end,

  ---@param result intellij.WorkspaceImportState
  ['intellij/workspaceImportState'] = function(_, result, ctx)
    local failed = {}
    for _, folder in ipairs(result.folders or {}) do
      if folder.status ~= 'SUCCESS' then
        failed[#failed + 1] = ('%s (%s): %s'):format(
          vim.uri_to_fname(folder.folderUri),
          folder.tool or folder.status:lower(),
          folder.message or folder.status
        )
      end
    end
    local msg = phase_message[result.phase]
    if not msg then
      progress(ctx.client_id, 'importing workspace', 'running')
      return
    end
    if #failed > 0 then
      msg = phase_message.FAILED
    end
    progress(ctx.client_id, msg, msg == phase_message.FINISHED and 'success' or 'failed')
    if #failed > 0 then
      vim.notify(
        'intellij: workspace import failed for\n' .. table.concat(failed, '\n'),
        vim.log.levels.WARN
      )
    end
  end,

  ---@param result intellij.ImportLog
  ['intellij/importLog'] = function(_, result, ctx)
    if result.started then
      progress(ctx.client_id, result.message, 'running')
    end
    vim.lsp.log.info('intellij/importLog', result.message)
  end,

  ---@param result { content: string }
  ['intellij/copyToClipboard'] = function(_, result)
    vim.fn.setreg('+', result.content)
  end,
}

---@type table<string, fun(command: lsp.Command, ctx: table)>
M.commands = {
  ['editor.action.triggerParameterHints'] = function()
    vim.lsp.buf.signature_help()
  end,
  -- Sent after postfix templates such as `.var` to name the introduced variable.
  ['editor.action.rename'] = function(_, ctx)
    vim.lsp.buf.rename(nil, {
      bufnr = ctx.bufnr,
      filter = function(client)
        return client.id == ctx.client_id
      end,
    })
  end,
  ['jetbrains.navigateToLocation'] = function(command, ctx)
    local uri, line, character = unpack(command.arguments or {})
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local pos = { line = line, character = character }
    vim.lsp.util.show_document(
      { uri = uri, range = { start = pos, ['end'] = pos } },
      client and client.offset_encoding or 'utf-16',
      { focus = true }
    )
  end,
}

for name, fn in pairs(M.commands) do
  vim.lsp.commands[name] = vim.lsp.commands[name] or fn
end

---@param bufnr? integer
---@return vim.lsp.Client?
function M.client(bufnr)
  return vim.lsp.get_clients({ name = 'intellij', bufnr = bufnr })[1]
end

---@param bufnr? integer
function M.reload(bufnr)
  local client = M.client(bufnr)
  if not client then
    vim.notify('intellij: no client attached', vim.log.levels.WARN)
    return
  end
  client:request(
    'intellij/reloadWorkspace',
    { initializationOptions = M.init_options(client.config) },
    function(err)
      if err then
        vim.notify('intellij: reload failed: ' .. err.message, vim.log.levels.ERROR)
      end
    end,
    bufnr
  )
end

return M

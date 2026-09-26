local M = {}

local known_keys = {
  filetypes = true,
  server_dir = true,
  data_dir = true,
  java_home = true,
  jvm_options = true,
}

local conflicting = { 'jdtls', 'kotlin_lsp' }

-- Highest GLIBC_* symbol version referenced by the bundled JBR in server 263.x.
local min_glibc = '2.28'

---@return string?
local function glibc_version()
  local ok, res = pcall(function()
    return vim.system({ 'getconf', 'GNU_LIBC_VERSION' }, { text = true }):wait()
  end)
  return ok and res.code == 0 and (res.stdout or ''):match('glibc%s+([%d.]+)') or nil
end

local function check_platform()
  local target, err = require('intellij.server').target()
  if not target then
    vim.health.error(err .. '; no server build exists for it')
    return
  end
  vim.health.ok('Platform: ' .. target)
  if not vim.startswith(target, 'linux') then
    return
  end
  local glibc = glibc_version()
  if not glibc then
    vim.health.error('Could not detect glibc (musl-based systems are not supported)', {
      'The server requires glibc >= ' .. min_glibc,
    })
  elseif vim.version.lt(glibc, min_glibc) then
    vim.health.error(('glibc %s is too old; the server requires >= %s'):format(glibc, min_glibc))
  else
    vim.health.ok('glibc ' .. glibc)
  end
end

local function check_user_config()
  local g = vim.g.intellij
  if g == nil then
    return
  end
  if type(g) ~= 'table' then
    vim.health.error('vim.g.intellij must be a table, got ' .. type(g))
    return
  end
  for key in pairs(g) do
    if not known_keys[key] then
      vim.health.warn(('Unknown key in vim.g.intellij: %s'):format(tostring(key)))
    end
  end
end

---@param config intellij.Config
local function check_server(config)
  local server = require('intellij.server')
  local dir = server.dir()
  if not dir then
    vim.health.error('IntelliJ server not found', { 'Run :IntelliJ install', 'Or set server_dir' })
    return
  end
  vim.health.ok('Server directory: ' .. dir)
  local exe = server.executable(dir)
  if vim.fn.executable(exe) == 1 then
    vim.health.ok('Executable: ' .. exe)
  else
    vim.health.error('Server executable missing or not executable: ' .. exe)
  end
  if server.eula_accepted(dir) then
    vim.health.ok('EULA accepted')
  else
    vim.health.warn('EULA not accepted; the server will not start', { 'Run :IntelliJ eula' })
  end
  if config.server_dir then
    vim.health.info('server_dir overrides installed servers')
  end
end

---@param config intellij.Config
local function check_java(config)
  local java_home = config.java_home
  if not java_home or java_home == '' then
    vim.health.warn('java_home is not set (JAVA_HOME is empty)', {
      'Set java_home or JAVA_HOME; it is sent as defaultSdk for project import',
    })
  elseif not vim.uv.fs_stat(java_home) then
    vim.health.warn('java_home does not exist: ' .. java_home, {
      'It is sent as defaultSdk for project import',
    })
  else
    vim.health.ok('java_home: ' .. java_home)
  end
  for _, tool in ipairs({ 'mvn', 'gradle' }) do
    if vim.fn.executable(tool) == 1 then
      vim.health.info(tool .. ' found: ' .. vim.fn.exepath(tool))
    else
      vim.health.info(tool .. ' not found on PATH (project wrappers may still work)')
    end
  end
end

local function check_lsp()
  if vim.lsp.is_enabled('intellij') then
    vim.health.ok('intellij LSP config is enabled')
  else
    vim.health.warn('intellij LSP config is not enabled', {
      "Call require('intellij').setup()",
      "Or call vim.lsp.enable('intellij')",
    })
  end
  local ours = {}
  for _, ft in ipairs(vim.lsp.config.intellij.filetypes or {}) do
    ours[ft] = true
  end
  for _, name in ipairs(conflicting) do
    if vim.lsp.is_enabled(name) then
      local ok, cfg = pcall(function()
        return vim.lsp.config[name]
      end)
      local fts = ok and cfg and cfg.filetypes or {}
      local overlap = vim.tbl_filter(function(ft)
        return ours[ft]
      end, fts)
      if #overlap > 0 then
        vim.health.warn(
          ('%s is also enabled for %s and will conflict'):format(name, table.concat(overlap, ', ')),
          { ("Disable it with vim.lsp.enable('%s', false)"):format(name) }
        )
      end
    end
  end
end

function M.check()
  vim.health.start('intellij.nvim')
  if vim.fn.has('nvim-0.12') == 1 then
    vim.health.ok('Neovim >= 0.12')
  else
    vim.health.error('Neovim >= 0.12 is required')
    return
  end

  check_user_config()
  local ok, config = pcall(require('intellij.config').get)
  if not ok then
    vim.health.error('Invalid configuration: ' .. tostring(config))
    return
  end
  local filetypes = vim.lsp.config.intellij.filetypes or {}
  if #filetypes == 0 then
    vim.health.warn('filetypes is empty; the server will not attach to any buffer')
  else
    vim.health.ok('filetypes: ' .. table.concat(filetypes, ', '))
  end
  for _, tool in ipairs({ 'curl', 'unzip', 'tar' }) do
    if vim.fn.executable(tool) == 0 then
      vim.health.warn(tool .. ' not found; :IntelliJ install needs it')
    end
  end
  if vim.fn.executable('sha256sum') == 0 and vim.fn.executable('shasum') == 0 then
    vim.health.warn('sha256sum or shasum not found; :IntelliJ install needs one')
  end

  vim.health.start('intellij.nvim: platform')
  check_platform()

  vim.health.start('intellij.nvim: server')
  check_server(config)

  vim.health.start('intellij.nvim: java')
  check_java(config)

  vim.health.start('intellij.nvim: lsp')
  check_lsp()
end

return M

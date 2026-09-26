local config = require('intellij.config')

local M = {}

local PROGRESS_ID = 'intellij.install'
local OPEN_VSX = 'https://open-vsx.org/api/JetBrains/intellij-server/%s/latest'

local installing = false

---@param dir string
---@return string
function M.executable(dir)
  local name = vim.fn.has('win32') == 1 and 'intellij-server.exe' or 'intellij-server'
  return vim.fs.joinpath(dir, 'bin', name)
end

---@param dir string
---@return boolean
local function has_executable(dir)
  return vim.uv.fs_stat(M.executable(dir)) ~= nil
end

---@return string
local function servers_dir()
  return vim.fs.joinpath(config.get().data_dir, 'servers')
end

---@return string
local function eula_file()
  return vim.fs.joinpath(config.get().data_dir, 'eula')
end

---@param path string
---@return string?
local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  return content
end

--- Server directory: `config.server_dir` if set, else the highest installed version.
---@return string?
function M.dir()
  local cfg = config.get()
  if cfg.server_dir then
    return vim.fs.normalize(cfg.server_dir)
  end
  local root = servers_dir()
  local best, best_version
  for name, type in vim.fs.dir(root) do
    local version = type == 'directory' and vim.version.parse(name) or nil
    local dir = vim.fs.joinpath(root, name)
    if version and (not best_version or version > best_version) and has_executable(dir) then
      best, best_version = dir, version
    end
  end
  return best
end

--- First 16 hex chars of the sha256 of `<dir>/EULA.txt`.
---@param dir string
---@return string?
function M.eula_hash(dir)
  local content = read_file(vim.fs.joinpath(dir, 'EULA.txt'))
  return content and vim.fn.sha256(content):sub(1, 16) or nil
end

---@param dir string
---@return boolean
function M.eula_accepted(dir)
  local hash = M.eula_hash(dir)
  local stored = read_file(eula_file())
  return hash ~= nil and stored ~= nil and vim.trim(stored) == hash
end

---@param dir string
---@param cb fun(accepted: boolean)
function M.accept_eula(dir, cb)
  local path = vim.fs.joinpath(dir, 'EULA.txt')
  local hash = M.eula_hash(dir)
  if not hash then
    vim.notify('intellij: cannot read ' .. path, vim.log.levels.ERROR)
    return cb(false)
  end

  vim.cmd.tabnew()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, 'intellij://EULA')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path))
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  vim.ui.select(
    { 'Accept', 'Decline' },
    { prompt = 'IntelliJ server EULA (' .. path .. '):' },
    function(choice)
      local accepted = choice == 'Accept'
      if accepted then
        vim.fn.mkdir(config.get().data_dir, 'p')
        vim.fn.writefile({ hash }, eula_file())
      end
      if vim.api.nvim_win_is_valid(win) and #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(win, true)
      end
      cb(accepted)
    end
  )
end

---@return string? target
---@return string? err
function M.target()
  local uname = vim.uv.os_uname()
  local os = ({ Darwin = 'darwin', Linux = 'linux', Windows_NT = 'win32' })[uname.sysname]
  local arch = ({
    x86_64 = 'x64',
    amd64 = 'x64',
    AMD64 = 'x64',
    arm64 = 'arm64',
    aarch64 = 'arm64',
    ARM64 = 'arm64',
  })[uname.machine]
  if not (os and arch) then
    return nil, ('unsupported platform: %s %s'):format(uname.sysname, uname.machine)
  end
  return os .. '-' .. arch
end

---@param msg string
---@param status 'running'|'success'|'failed'
---@param percent? integer
local function progress(msg, status, percent)
  vim.api.nvim_echo({ { msg } }, status ~= 'running', {
    kind = 'progress',
    id = PROGRESS_ID,
    source = 'intellij',
    title = 'intellij',
    status = status,
    percent = percent,
    err = status == 'failed' or nil,
  })
end

---@param s string
---@return any? value
---@return string? err
local function decode(s)
  local ok, value = pcall(vim.json.decode, s)
  if not ok or type(value) ~= 'table' then
    return nil, 'invalid JSON: ' .. tostring(value)
  end
  return value
end

--- Downloads and unpacks the latest server for this platform into `<data_dir>/servers/<version>`.
---@param cb? fun(err?: string, dir?: string)
function M.install(cb)
  cb = cb or function() end
  if installing then
    return cb('install already in progress')
  end
  local tgt, terr = M.target()
  if not tgt then
    return cb(terr)
  end
  local sha_cmd = vim.fn.executable('sha256sum') == 1 and { 'sha256sum' }
    or vim.fn.executable('shasum') == 1 and { 'shasum', '-a', '256' }
    or nil
  if not sha_cmd then
    return cb('sha256sum or shasum is required')
  end
  installing = true

  local servers = servers_dir()
  -- Staging lives next to the final location so fs_rename never crosses filesystems.
  local staging = vim.fs.joinpath(servers, ('.staging-%d'):format(vim.uv.hrtime()))
  vim.fn.mkdir(staging, 'p')

  ---@param err? string
  ---@param dir? string
  local function finish(err, dir)
    installing = false
    vim.fs.rm(staging, { recursive = true, force = true })
    if err then
      progress('install failed: ' .. err, 'failed')
    else
      progress('installed ' .. dir, 'success', 100)
    end
    cb(err, dir)
  end

  ---@param cmd string[]
  ---@param on_ok fun(stdout: string)
  local function run(cmd, on_ok)
    vim.system(
      cmd,
      { text = true },
      vim.schedule_wrap(function(res)
        if res.code ~= 0 then
          local stderr = vim.trim(res.stderr or '')
          return finish(('%s exited with %d: %s'):format(table.concat(cmd, ' '), res.code, stderr))
        end
        local ok, err = pcall(on_ok, res.stdout or '')
        if not ok then
          finish(tostring(err))
        end
      end)
    )
  end

  local vsix = vim.fs.joinpath(staging, 'server.vsix')
  local extract = vim.fs.joinpath(staging, 'extract')

  progress('fetching release metadata for ' .. tgt, 'running', 0)
  run({ 'curl', '-fsSL', OPEN_VSX:format(tgt) }, function(meta_json)
    local meta, err = decode(meta_json)
    local url = meta and vim.tbl_get(meta, 'files', 'download')
    if not url then
      return finish(err or 'Open VSX response has no files.download')
    end
    progress('downloading extension', 'running', 5)
    run({ 'curl', '-fsSL', '-o', vsix, url }, function()
      run({ 'unzip', '-p', vsix, 'extension/server-bundle.json' }, function(bundle_json)
        local bundle, berr = decode(bundle_json)
        if not (bundle and bundle.url and bundle.version and bundle.sha256) then
          return finish(berr or 'server-bundle.json is missing url, version or sha256')
        end
        local dest = vim.fs.joinpath(servers, bundle.version)
        if has_executable(dest) then
          return finish(nil, dest)
        end
        local archive = vim.fs.joinpath(staging, bundle.archiveName or vim.fs.basename(bundle.url))
        progress('downloading intellij-server ' .. bundle.version, 'running', 10)
        run({ 'curl', '-fsSL', '-o', archive, bundle.url }, function()
          progress('verifying checksum', 'running', 80)
          run(vim.list_extend(vim.deepcopy(sha_cmd), { archive }), function(sum_out)
            local sum = (sum_out:match('^%s*(%x+)') or ''):lower()
            if sum ~= bundle.sha256:lower() then
              return finish(('sha256 mismatch: expected %s, got %s'):format(bundle.sha256, sum))
            end
            progress('extracting', 'running', 85)
            vim.fn.mkdir(extract, 'p')
            run({ 'tar', '-xf', archive, '-C', extract }, function()
              local src = vim.fs.joinpath(extract, 'intellij-server-' .. bundle.version)
              if not has_executable(src) then
                return finish('archive does not contain ' .. M.executable(src))
              end
              vim.fs.rm(dest, { recursive = true, force = true })
              local ok, rerr = vim.uv.fs_rename(src, dest)
              if not ok then
                return finish(('cannot move %s to %s: %s'):format(src, dest, rerr))
              end
              finish(nil, dest)
            end)
          end)
        end)
      end)
    end)
  end)
end

return M

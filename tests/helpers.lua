local M = {}

function M.reset()
  for name in pairs(package.loaded) do
    if name == 'intellij' or vim.startswith(name, 'intellij.') then
      package.loaded[name] = nil
    end
  end
  vim.g.intellij = nil
  vim.cmd('silent! %bwipeout!')
end

---@return string
function M.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return vim.uv.fs_realpath(dir)
end

---@param path string
---@param content? string
function M.write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'wb'))
  f:write(content or '')
  f:close()
end

---@param root string
---@param files string[]
function M.tree(root, files)
  for _, file in ipairs(files) do
    if vim.endswith(file, '/') then
      vim.fn.mkdir(vim.fs.joinpath(root, file), 'p')
    else
      M.write(vim.fs.joinpath(root, file))
    end
  end
end

--- Creates `<dir>/bin/intellij-server` and `<dir>/EULA.txt`.
---@param dir string
---@param eula? string
function M.fake_server(dir, eula)
  local exe = vim.fs.joinpath(dir, 'bin', 'intellij-server')
  M.write(exe, '#!/bin/sh\nexit 0\n')
  vim.uv.fs_chmod(exe, tonumber('755', 8))
  M.write(vim.fs.joinpath(dir, 'EULA.txt'), eula or 'terms\n')
end

---@param path string
---@return integer
function M.buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end

---@param expected any
---@param actual any
function M.eq(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

---@param fn function
---@param pattern string
function M.errors(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    error('expected an error matching ' .. pattern, 2)
  end
  if not tostring(err):find(pattern) then
    error(('error %q does not match %q'):format(tostring(err), pattern), 2)
  end
end

return M

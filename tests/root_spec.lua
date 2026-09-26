local h = require('helpers')

---@param root string
---@param files string[]
---@param file string
---@return string?
local function root_of(root, files, file)
  h.reset()
  h.tree(root, files)
  local found
  require('intellij.lsp').root_dir(h.buf(vim.fs.joinpath(root, file)), function(dir)
    found = dir
  end)
  return found
end

return {
  ['maven: contiguous pom chain picks outermost'] = function()
    local root = h.tmpdir()
    local files = { 'pom.xml', 'app/pom.xml', 'app/core/pom.xml', 'app/core/src/A.java' }
    h.eq(root, root_of(root, files, 'app/core/src/A.java'))
  end,

  ['maven: non-contiguous higher pom is not picked'] = function()
    local root = h.tmpdir()
    local files = { 'pom.xml', 'gap/mod/pom.xml', 'gap/mod/src/A.java' }
    h.eq(vim.fs.joinpath(root, 'gap', 'mod'), root_of(root, files, 'gap/mod/src/A.java'))
  end,

  ['gradle: settings.gradle wins over build.gradle'] = function()
    local root = h.tmpdir()
    local files = { 'settings.gradle', 'lib/build.gradle', 'lib/src/A.java' }
    h.eq(root, root_of(root, files, 'lib/src/A.java'))
  end,

  ['bazel: MODULE.bazel wins over BUILD.bazel'] = function()
    local root = h.tmpdir()
    local files = { 'MODULE.bazel', 'pkg/BUILD.bazel', 'pkg/A.java' }
    h.eq(root, root_of(root, files, 'pkg/A.java'))
  end,

  ['falls back to .git'] = function()
    local root = h.tmpdir()
    h.eq(root, root_of(root, { '.git/', 'src/A.java' }, 'src/A.java'))
  end,

  ['no root does not call on_dir'] = function()
    local root = h.tmpdir()
    h.eq(nil, root_of(root, { 'src/A.java' }, 'src/A.java'))
  end,
}

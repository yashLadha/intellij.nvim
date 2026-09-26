local h = require('helpers')

return {
  ['dir picks highest installed version'] = function()
    h.reset()
    local data = h.tmpdir()
    for _, version in ipairs({ '0.9.0', '1.2.0', '1.10.0' }) do
      h.fake_server(vim.fs.joinpath(data, 'servers', version))
    end
    vim.fn.mkdir(vim.fs.joinpath(data, 'servers', '2.0.0'), 'p')
    h.write(vim.fs.joinpath(data, 'servers', '3.0.0'))
    require('intellij.config').set({ data_dir = data })
    h.eq(vim.fs.joinpath(data, 'servers', '1.10.0'), require('intellij.server').dir())
  end,

  ['dir prefers server_dir'] = function()
    h.reset()
    local data, dir = h.tmpdir(), h.tmpdir()
    h.fake_server(vim.fs.joinpath(data, 'servers', '1.0.0'))
    require('intellij.config').set({ data_dir = data, server_dir = dir })
    h.eq(dir, require('intellij.server').dir())
  end,

  ['dir is nil without installs'] = function()
    h.reset()
    require('intellij.config').set({ data_dir = h.tmpdir() })
    h.eq(nil, require('intellij.server').dir())
  end,

  ['eula_hash and eula_accepted'] = function()
    h.reset()
    local data, dir = h.tmpdir(), h.tmpdir()
    h.fake_server(dir, 'license text\n')
    require('intellij.config').set({ data_dir = data, server_dir = dir })
    local server = require('intellij.server')
    local hash = server.eula_hash(dir)
    h.eq(vim.fn.sha256('license text\n'):sub(1, 16), hash)
    h.eq(nil, server.eula_hash(h.tmpdir()))
    h.eq(false, server.eula_accepted(dir))
    h.write(vim.fs.joinpath(data, 'eula'), hash .. '\n')
    h.eq(true, server.eula_accepted(dir))
    h.write(vim.fs.joinpath(data, 'eula'), 'stale')
    h.eq(false, server.eula_accepted(dir))
  end,
}

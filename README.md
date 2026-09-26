<p align="center">
  <img src="assets/banner.svg" alt="intellij.nvim" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Neovim-0.12%2B-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Neovim 0.12+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

Run JetBrains' [IntelliJ Language Server](https://blog.jetbrains.com/idea/2026/08/intellij-idea-goes-lsp/) in Neovim for Java and Kotlin, using the built-in LSP client. It attaches only to the filetypes you configure.

## Requirements

- Neovim 0.12+
- macOS, Windows, or Linux with glibc 2.28+ (x64 or arm64)
- A JDK, and Maven, Gradle or Bazel for project import
- `curl`, `unzip`, `tar`, `sha256sum` or `shasum` for the installer

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'yashLadha/intellij-neovim',
  main = 'intellij',
  ft = { 'java' },
  opts = { filetypes = { 'java' } },
}
```

Then run `:IntelliJ install` (downloads about 376 MB) and accept the EULA when prompted.

## Configuration

```lua
require('intellij').setup({
  filetypes = { 'java', 'kotlin' }, -- default { 'java' }
  java_home = '/path/to/jdk',        -- default $JAVA_HOME
  jvm_options = { '-Xmx4g' },
})
```

See `:help intellij-config` for `server_dir` and `data_dir`. Without `setup()`, set `vim.g.intellij` to the same table and call `vim.lsp.enable('intellij')`. Other LSP fields (`on_attach`, `capabilities`, `settings`, `init_options`) go through `vim.lsp.config('intellij', { ... })`.

For built-in completion:

```lua
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
    if client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})
```

Hover, definition, references, rename, code actions, formatting, diagnostics, inlay hints and hierarchies use the Neovim defaults (`:help lsp-defaults`). Definitions in the JDK or dependencies open as read-only `jar:` buffers.

## Commands

| Command | Description |
| --- | --- |
| `:IntelliJ install` | Install or update the server |
| `:IntelliJ eula` | Show and accept the EULA |
| `:IntelliJ reload` | Reimport the project |
| `:IntelliJ log` | Open the server log |

Run `:checkhealth intellij` when something does not work.

## Notes

- Preview builds expire after about 30 days; run `:IntelliJ install` again to update.
- Disable `jdtls` or `kotlin_lsp` for the same filetypes to avoid duplicate servers.
- The server is proprietary JetBrains software. The preview is free; later it requires an IntelliJ IDEA Ultimate subscription. This project is not affiliated with JetBrains.

## License

[MIT](LICENSE)

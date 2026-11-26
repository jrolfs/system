-- Load defaults i.e. nvim-lspconfig language servers
local nvlsp = require "nvchad.configs.lspconfig"

-- IMPORTANT: Use the new API
local servers = { "html", "cssls", "ts_ls", "clangd" }

-- lspconfig
for _, lsp in ipairs(servers) do
  vim.lsp.config[lsp] = {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

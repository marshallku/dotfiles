-- vtsls returns paths inside Yarn PnP zip caches (e.g.
-- /repo/.yarn/cache/foo-npm-1.0.0.zip/node_modules/foo/index.d.ts).
-- vim-rzip teaches netrw to read these so `gd` into a vendored type works.
return {
    "lbrayner/vim-rzip",
    cond = function() return not vim.g.vscode end,
    event = "BufReadPre",
}

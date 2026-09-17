{ config, lib, ... }:
let
  enabledServers = lib.pipe config.programs.nixvim.lsp.servers [
    (lib.filterAttrs (name: server: name != "*" && server.enable))
    builtins.attrNames
  ];
  luaList = lib.concatMapStringsSep ", " (n: ''"${n}"'') enabledServers;
in
{
  imports = lib.mapAttrsToList (name: _: ./. + "/${name}") (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.readDir ./.)
  );

  # nvim-lspconfig only ships default configs (cmd/root_markers/filetypes) for
  # `vim.lsp.config`; enabling happens per server below via `vim.lsp.enable`.
  programs.nixvim.plugins.lspconfig.enable = true;

  # A jj workspace has no .git, so every server rooting on it lands in
  # single-file mode. Mirror each .git marker with .jj at the same priority
  # (nested lists are priority tiers). Runs post, once lspconfig's defaults and
  # the per-server overrides are both in place.
  programs.nixvim.extraConfigLuaPost = ''
    do
      local function mirror(markers)
        local out = {}
        for _, m in ipairs(markers) do
          if type(m) == "table" then
            out[#out + 1] = mirror(m)
          else
            out[#out + 1] = m
            if m == ".git" then out[#out + 1] = ".jj" end
          end
        end
        return out
      end

      for _, name in ipairs({ ${luaList} }) do
        local markers = (vim.lsp.config[name] or {}).root_markers
        if markers ~= nil then
          vim.lsp.config(name, { root_markers = mirror(markers) })
        end
      end
    end
  '';
}

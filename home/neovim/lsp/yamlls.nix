{ ... }:
{
  programs.nixvim.lsp.servers.yamlls = {
    enable = true;
    config.settings.yaml = {
      schemaStore = {
        enable = true;
        url = "https://www.schemastore.org/api/json/catalog.json";
      };
      schemas = {
        "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/refs/tags/3.1.0/schemas/v3.0/schema.yaml" =
          [
            "openapi.yaml"
            "openapi.yml"
            "**/openapi/*.yaml"
          ];
        "https://json-schema.org/draft/2020-12/schema" = [
          "*.schema.yaml"
          "*.schema.json"
        ];
      };
    };
  };
}

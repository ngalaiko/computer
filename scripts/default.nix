# Build + push scripts; IMAGE/TAG/GHCR_USER/GHCR_TOKEN override the defaults.
{ pkgs }:
let
  registryEnv = ''
    image="''${IMAGE:-ghcr.io/ngalaiko/computer.exe}"
    tag="''${TAG:-latest}"
    ghcr_user="''${GHCR_USER:-ngalaiko}"
    ghcr_token="''${GHCR_TOKEN:-$(gh auth token)}"
  '';
in
rec {
  # One-time: grant gh the write:packages scope.
  ghcr-auth = pkgs.writeShellApplication {
    name = "ghcr-auth";
    runtimeInputs = [ pkgs.gh ];
    text = ''
      if gh auth status -h github.com >/dev/null 2>&1; then
        gh auth refresh -h github.com -s write:packages
      else
        gh auth login -h github.com -s write:packages -w
      fi
    '';
  };

  # `nix` comes from the caller's PATH so builds keep the host's config
  # (linux-builder offload on the Mac).
  push-image = pkgs.writeShellApplication {
    name = "push-image";
    runtimeInputs = [
      pkgs.skopeo
      pkgs.gh
      pkgs.gitMinimal
      pkgs.jujutsu
    ];
    text = ''
      system="''${1:?usage: push-image <x86_64-linux>}"
      if [ "$system" != x86_64-linux ]; then
        echo "unsupported system: $system (only the exe.dev x86_64 image is published)" >&2
        exit 1
      fi
      ${registryEnv}

      # GitHub runners ship a v1-format registries.conf that skopeo refuses
      conf="$(mktemp)"
      trap 'rm -f "$conf"' EXIT
      printf 'unqualified-search-registries = []\n' > "$conf"
      export CONTAINERS_REGISTRIES_CONF="$conf"

      mkdir -p dist
      nix build ".#packages.$system.exedev" \
        -o "dist/computer.exe.$system.tar.gz" --print-build-logs
      skopeo --insecure-policy copy \
        --dest-creds "$ghcr_user:$ghcr_token" \
        "docker-archive:dist/computer.exe.$system.tar.gz" \
        "docker://$image:$tag"

      # Publish the commit tags used by deployment. A single-arch image needs
      # no manifest list, but it still needs both the Git and jj revision tags.
      jj root >/dev/null 2>&1 || jj git init --colocate
      git_sha="$(git rev-parse --short HEAD)"
      jj_rev="$(jj log --no-graph -r '@' -T 'change_id.short()')"
      revisions=("$git_sha" "$jj_rev")
      if [ -n "''${GITHUB_SHA:-}" ]; then
        revisions+=("$GITHUB_SHA")
      fi
      for revision in "''${revisions[@]}"; do
        skopeo --insecure-policy copy \
          --src-creds "$ghcr_user:$ghcr_token" \
          --dest-creds "$ghcr_user:$ghcr_token" \
          "docker://$image:$tag" \
          "docker://$image:$revision"
      done
    '';
  };

  release = pkgs.writeShellApplication {
    name = "release";
    runtimeInputs = [ push-image ];
    text = ''
      push-image x86_64-linux
    '';
  };

  # In-place deploy: `nixos-rebuild switch` run on the box itself, which fetches
  # inputs from GitHub and the binary cache directly instead of through the
  # (often relayed) tailnet link. A local checkout is copied over once as a
  # flake source.
  #   DEPLOY_NODE   tailnet node / ssh host   (default: exedev)
  #   DEPLOY_FLAKE  flake ref                 (default: . = the working tree)
  deploy = pkgs.writeShellApplication {
    name = "deploy";
    runtimeInputs = [
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      node="''${DEPLOY_NODE:-exedev}"
      ref="''${DEPLOY_FLAKE:-.}"
      # accept-new so a fresh runner (CI) trusts the tailnet host key on first sight.
      ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
      export NIX_SSHOPTS="''${NIX_SSHOPTS:-''${ssh_opts[*]}}"

      case "$ref" in
        . | ./* | /* | path:* | git+file:*)
          ref="$(nix flake archive --json --to "ssh-ng://nikita@$node" "$ref" | jq -r .path)/hosts/exedev"
          ;;
        *\?*) ref="$ref&dir=hosts/exedev" ;;
        *) ref="$ref?dir=hosts/exedev" ;;
      esac

      # shellcheck disable=SC2029 # $ref expands client-side, by design
      exec ssh "''${ssh_opts[@]}" "nikita@$node" \
        "sudo nixos-rebuild switch --flake '$ref#exedev'"
    '';
  };
}

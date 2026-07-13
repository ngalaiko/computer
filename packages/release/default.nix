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
    ];
    text = ''
      system="''${1:?usage: push-image <aarch64-linux|x86_64-linux>}"
      case "$system" in
        aarch64-linux) arch=arm64 ;;
        x86_64-linux) arch=amd64 ;;
        *)
          echo "unsupported system: $system" >&2
          exit 1
          ;;
      esac
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
        "docker://$image:$tag-$arch"
    '';
  };

  # Arch images must already be pushed.
  push-manifest = pkgs.writeShellApplication {
    name = "push-manifest";
    runtimeInputs = [
      pkgs.regctl
      pkgs.gh
      pkgs.gitMinimal
      pkgs.jujutsu
    ];
    text = ''
      ${registryEnv}

      printf '%s' "$ghcr_token" | regctl registry login ghcr.io -u "$ghcr_user" --pass-stdin
      trap 'regctl registry logout ghcr.io || true' EXIT

      regctl index create "$image:$tag" \
        --ref "$image:$tag-amd64" \
        --ref "$image:$tag-arm64"

      # jj change ids derive from git history, so a fresh CI init tags the same rev
      jj root >/dev/null 2>&1 || jj git init --colocate
      git_sha="$(git rev-parse --short HEAD)"
      jj_rev="$(jj log --no-graph -r 'trunk()' -T 'change_id.short()')"
      for t in "$git_sha" "$jj_rev"; do
        regctl image copy "$image:$tag" "$image:$t"
      done
    '';
  };

  release = pkgs.writeShellApplication {
    name = "release";
    runtimeInputs = [
      push-image
      push-manifest
    ];
    text = ''
      push-image aarch64-linux
      push-image x86_64-linux
      push-manifest
    '';
  };
}

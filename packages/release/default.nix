# Release tooling: build the image and push it to ghcr.io. Impure by design
# (network + credentials), so these run *around* `nix build`, not inside it.
# Registry coordinates are baked in but overridable via IMAGE/TAG/GHCR_USER;
# GHCR_TOKEN falls back to `gh auth token`.
{ pkgs }:
let
  # Shared preamble for every script that talks to ghcr.io.
  registryEnv = ''
    image="''${IMAGE:-ghcr.io/ngalaiko/computer.exe}"
    tag="''${TAG:-latest}"
    ghcr_user="''${GHCR_USER:-ngalaiko}"
    ghcr_token="''${GHCR_TOKEN:-$(gh auth token)}"
  '';
in
rec {
  # One-time: grant gh the write:packages scope for GHCR pushes.
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

  # Build one arch image (-> dist/) and push it to $IMAGE:$TAG-<arch>.
  # `nix` itself comes from the caller's environment so local builds keep
  # using the host's config (linux-builder offload on the Mac).
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

      # skopeo refuses the v1-format registries.conf GitHub runners ship;
      # point it at a minimal v2 file of our own.
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

  # Stitch the pushed per-arch images into the multi-arch $TAG manifest and
  # copy it to immutable git-sha / jj-trunk tags. Arch images must exist.
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

      # CI checkouts are plain git; jj change ids are derived from git history,
      # so a colocated init there yields the same rev as the local repo.
      jj root >/dev/null 2>&1 || jj git init --colocate
      git_sha="$(git rev-parse --short HEAD)"
      jj_rev="$(jj log --no-graph -r 'trunk()' -T 'change_id.short()')"
      for t in "$git_sha" "$jj_rev"; do
        regctl image copy "$image:$tag" "$image:$t"
      done
    '';
  };

  # The whole release: both arches, then the manifest.
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

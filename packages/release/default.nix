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
      for revision in "$git_sha" "$jj_rev"; do
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

  # In-place deploy: build the system generation and activate it on the live box
  # WITHOUT recreating the VM. `nix` comes from the caller's PATH so it keeps the
  # host's substituters config.
  #   DEPLOY_NODE   tailnet node / ssh host   (default: computer)
  #   DEPLOY_SYSTEM target arch               (default: x86_64-linux — the box)
  #   DEPLOY_FLAKE  flake ref                 (default: . = the working tree)
  # The generation is always realised in the box's OWN store — never `nix copy`ed
  # in, which the box rejects as unsigned. How the box gets the sources depends on
  # the ref:
  #   * a remote flakeref (github:…/<sha>, CI): the box fetches + builds it itself
  #     over SSH, so NOTHING is pushed from the runner — no trust/signature issue.
  #   * a local path (`.`, the Mac): eval locally and push the working tree into
  #     the box's store to build there (needs a trusted user — nikita is).
  deploy = pkgs.writeShellApplication {
    name = "deploy";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      node="''${DEPLOY_NODE:-computer}"
      target="''${DEPLOY_SYSTEM:-x86_64-linux}"
      ref="''${DEPLOY_FLAKE:-.}"
      # accept-new so a fresh runner (CI) trusts the tailnet host key on first sight.
      ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
      export NIX_SSHOPTS="''${NIX_SSHOPTS:-''${ssh_opts[*]}}"

      case "$ref" in
        . | ./* | /*)
          echo "deploy: building local $ref in $node's store"
          gen="$(nix build "$ref#packages.$target.system" \
            --eval-store auto --store "ssh-ng://nikita@$node" \
            --no-link --print-out-paths)"
          ;;
        *)
          echo "deploy: $node fetches + builds $ref"
          # shellcheck disable=SC2029  # $ref/$target expand client-side, by design
          gen="$(ssh "''${ssh_opts[@]}" nikita@"$node" \
            "nix build '$ref#packages.$target.system' --no-link --print-out-paths")"
          ;;
      esac
      echo "deploy: generation $gen"

      # Detached (setsid): the switch may restart tailscaled, which serves our SSH,
      # so we must not let the dropped session SIGHUP the activation. We dispatch,
      # disconnect, then poll the status file it writes on completion.
      echo "deploy: dispatching detached 'activate switch' on $node"
      # one round-trip: clear the prior status, then launch detached.
      # shellcheck disable=SC2029  # $gen must expand here (client side), by design
      ssh "''${ssh_opts[@]}" nikita@"$node" \
        "sudo sh -c 'rm -f /run/activate.status; setsid \"$gen/activate\" switch </dev/null >/run/activate.log 2>&1 &'"

      echo "deploy: waiting for activation (tailscaled may bounce mid-switch)…"
      ok=""
      for _ in $(seq 1 90); do
        st="$(ssh "''${ssh_opts[@]}" nikita@"$node" 'cat /run/activate.status 2>/dev/null' 2>/dev/null || true)"
        case "$st" in
          "ok $gen"*)
            echo "deploy: $st"
            ok=1
            break
            ;;
          fail*)
            echo "deploy: activation FAILED: $st" >&2
            ssh "''${ssh_opts[@]}" nikita@"$node" 'sudo tail -n 40 /run/activate.log' 2>/dev/null || true
            exit 1
            ;;
        esac
        sleep 2
      done
      if [ -z "$ok" ]; then
        echo "deploy: timed out waiting for status; last activate.log:" >&2
        ssh "''${ssh_opts[@]}" nikita@"$node" 'sudo tail -n 40 /run/activate.log' 2>/dev/null || true
        exit 1
      fi
      echo "deploy: done — $node switched to $gen"
    '';
  };
}

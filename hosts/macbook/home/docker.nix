{ ... }:
{
  # Back the `docker` CLI (brew formula, client-only) with podman instead of
  # Docker Desktop: point it at the podman machine's docker-compatible API
  # socket. Path is stable per machine ($TMPDIR/podman/<machine>-api.sock);
  # requires `podman machine start`. shellInit (not interactive) so scripts
  # and child processes inherit it too.
  programs.fish.shellInit = ''
    set --global --export DOCKER_HOST "unix://$TMPDIR/podman/podman-machine-default-api.sock"
  '';
}

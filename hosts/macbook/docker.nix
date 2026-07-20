{ ... }:
let
  user = "nikita";
  # podman machine's docker-compatible API socket: a stable on-disk symlink that
  # resolves to $TMPDIR/podman/<machine>-api.sock while the machine is running.
  podmanSock = "/Users/${user}/.local/share/containers/podman/machine/podman.sock";
in
{
  # Declarative stand-in for `sudo podman-mac-helper install`: a root daemon that
  # keeps /var/run/docker.sock pointed at the rootless podman socket, so
  # docker-ecosystem tools that hardcode the default socket (testcontainers, some
  # compose setups) work without DOCKER_HOST. This is a single-user box, so a
  # direct symlink to our own podman socket is simpler and safer than podman's
  # root socket-forwarding proxy. DOCKER_HOST for the CLI lives in home/docker.nix.
  launchd.daemons.podman-docker-sock = {
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/var/log/podman-docker-sock.log";
      StandardErrorPath = "/var/log/podman-docker-sock.log";
    };
    # Only (re)link when docker.sock is already ours or absent — never clobber a
    # real socket (e.g. if Docker Desktop is ever installed).
    script = ''
      if [ -L /var/run/docker.sock ] || [ ! -e /var/run/docker.sock ]; then
        /bin/ln -sfh "${podmanSock}" /var/run/docker.sock
      fi
    '';
  };
}

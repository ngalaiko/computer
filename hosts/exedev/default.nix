{ pkgs, ... }:
{
  imports = [
    ./users/nikita.nix
    ./users/hermes.nix
  ];

  image = {
    name = "computer.exe";
    labels = {
      "org.opencontainers.image.title" = "computer.exe";
      "org.opencontainers.image.description" = "exe.dev image: s6-overlay, OpenSSH, and Hermes";
      "exe.dev/login-user" = "nikita";
    };
    packages = with pkgs; [
      bashInteractive
      coreutils-full
      findutils
      gnugrep
      gnused
      iproute2
      procps
      tzdata
      util-linux
      curl
    ];
  };
}

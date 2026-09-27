{ pkgs, lib, ... }:

# VacuumTube — Electron wrapper around YouTube Leanback (youtube.com/tv), with
# an adblocker and other enhancements.
#
# Not in nixpkgs, so this wraps the upstream AppImage. Version and both hashes
# are pinned, so the result is reproducible and needs no network after the
# first fetch. It also has to be a real package rather than a Flatpak: the
# Bigscreen launcher lists .desktop entries, which this installs.
let
  version = "1.8.2";

  src = pkgs.fetchurl {
    url = "https://github.com/shy1132/VacuumTube/releases/download/v${version}/VacuumTube-x86_64.AppImage";
    hash = "sha256-KWNe6Rq2fmEHP6hvpF67alzpUH/rc6kZfCbL5ZYh038=";
  };

  icon = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/shy1132/VacuumTube/v${version}/assets/icon.png";
    hash = "sha256-oxWhF15YNe7llokaZcV6zo0kupQORkhUx/DTgOVoAuc=";
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "vacuumtube";
    desktopName = "VacuumTube";
    genericName = "YouTube TV Client";
    comment = "YouTube Leanback (the TV interface) on the desktop";
    exec = "vacuumtube %U";
    icon = "vacuumtube";
    categories = [
      "AudioVideo"
      "Video"
      "Player"
    ];
  };

  vacuumtube = pkgs.appimageTools.wrapType2 {
    pname = "vacuumtube";
    inherit version src;

    # Electron expects these from the host; the AppImage doesn't bundle them.
    # If it fails to start, add candidates here (and see the README).
    extraPkgs = pkgs: with pkgs; [
      libglvnd
      alsa-lib
      nss
      nspr
    ];

    # appimageTools names the resulting executable after `pname`, i.e.
    # $out/bin/vacuumtube, which is what the desktop entry points at.
    extraInstallCommands = ''
      install -Dm644 ${icon} $out/share/icons/hicolor/512x512/apps/vacuumtube.png
      install -Dm644 ${desktopItem}/share/applications/vacuumtube.desktop \
        $out/share/applications/vacuumtube.desktop
    '';

    meta = {
      description = "YouTube Leanback (TV interface) on the desktop, with an adblocker";
      homepage = "https://github.com/shy1132/VacuumTube";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "vacuumtube";
    };
  };
in
{
  environment.systemPackages = [ vacuumtube ];
}

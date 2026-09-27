{ pkgs, ... }:

# Fladder — cross-platform Jellyfin client built on Flutter.
#
# nixpkgs builds this one from source (buildFlutterApplication) and already
# ships a scalable icon plus an "AudioVideo;Video;Player" desktop entry, so the
# Bigscreen launcher picks it up with nothing else to do here.
#
# Playback goes through mpv/FFmpeg, so VA-API applies: H.264 is hardware
# decoded, HEVC is not (see modules/graphics/intel-vaapi.nix and the README).
{
  environment.systemPackages = [ pkgs.fladder ];
}

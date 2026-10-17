{ pkgs, ... }:

# Intel HD Graphics 4000 (Ivy Bridge GT2, PCI 8086:0166).
#
# Two constraints that shape all of this:
#   1. Quick Sync here decodes H.264 only — no HEVC, VP8, VP9 or AV1.
#   2. There is no usable Vulkan on Gen7.
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # Legacy i965 VA-API driver — the one this GPU actually needs.
      # intel-media-driver is Broadwell (5th gen) and newer only; inert here.
      intel-vaapi-driver
    ];
  };

  # Mesa splits Ivy Bridge off into a separate "intel_hasvk" Vulkan driver,
  # which upstream calls incomplete and many builds omit entirely. Without it,
  # Vulkan-capable apps fall silently back to llvmpipe (software rendering),
  # so leave Qt and KWin on their normal GL paths.
  #
  # I originally also forced KWIN_COMPOSE=O2ES and QSG_RHI_BACKEND=opengl here.
  # Both are gone again: this host runs KWin 6.7.4, where OpenGL is still the
  # default compositing path, so O2ES was opting *out* of the well-tested code
  # for a GLES-only future that has not landed yet. It is the first thing worth
  # ruling out for the window-content flicker in Fladder.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "i965";
  };
}

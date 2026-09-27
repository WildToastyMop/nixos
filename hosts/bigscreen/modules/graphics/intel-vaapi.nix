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
  # Vulkan-capable apps fall silently back to llvmpipe (software rendering).
  # Keep Qt and KWin on the GL/GLES paths instead — which is also the direction
  # KWin is heading: Plasma 6.8 made its compositor OpenGL ES only.
  environment.sessionVariables = {
    KWIN_COMPOSE = "O2ES";
    QSG_RHI_BACKEND = "opengl";
    LIBVA_DRIVER_NAME = "i965";
  };
}

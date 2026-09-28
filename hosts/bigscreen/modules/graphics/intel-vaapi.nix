{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "i965";
  };
}

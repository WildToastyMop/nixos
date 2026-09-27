{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver
    ];
  };

  environment.sessionVariables = {
    KWIN_COMPOSE = "O2ES";
    QSG_RHI_BACKEND = "opengl";
    LIBVA_DRIVER_NAME = "i965";
  };
}

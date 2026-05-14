--  Some default env vars.
hl.env("XCURSOR_SIZE", "24")
--  change to qt6ct if you have that
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")

-- Firefox may crash with this

hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- VA-API hardware video acceleration
hl.env("NVD_BACKEND", "direct")
--  NVIDIA ENV VARS
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
--   Hardwarde video accelration driver
hl.env("NVD_BACKEND", "direct")

--  Enabling native wayland support for most electron apps
hl.env("ELECTOR_OZONE_PLATFORM_HINT", "auto")

--  Dont really remeber what these do
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")

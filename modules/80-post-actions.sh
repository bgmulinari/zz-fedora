#!/usr/bin/env bash
set -Eeuo pipefail

module_80_defaults() {
  apply_desktop_defaults
}

module_80_post_actions() {
  log_progress "Installing post-install launcher and first-run tasks"
  install_zz_launcher
  # This step runs under the continue-policy: a die in any later seed fails
  # the step but the install carries on and reports success. First-run
  # registration and the managed-files report must already be in place by
  # then, so they run before the failable user-file seeds below.
  register_first_run_hook
  write_managed_files_report
  log_progress "Applying desktop defaults"
  configure_default_applications
  log_progress "Installing desktop assets and theme seeds"
  install_bundled_wallpapers
  install_starship_config
  install_ghostty_theme_seed_if_missing
  install_niri_display_seed_if_missing
  install_niri_noctalia_seed_if_missing
  install_qt_theme_config
  configure_flatpak_theme_access
  log_progress "Enabling user services"
  enable_user_services
}

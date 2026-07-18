#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  setup_fake_bin
  mkdir -p "$TARGET_HOME/.mozilla/firefox/dev.default"
  touch "$TARGET_HOME/.mozilla/firefox/dev.default/cert9.db"
}

write_fake_dotnet() {
  write_fake_command dotnet <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'dotnet %s\n' "$*" >>"$COMMAND_LOG"
fake_root="${TEST_ROOT:-${TMPDIR:-/tmp}}"
case "$*" in
  "tool list -g")
    printf 'Package Id      Version      Commands\n'
    printf '%s\n' '-------------------------------------'
    printf 'linux-dev-certs 1.0.0        linux-dev-certs\n'
    ;;
  "linux-dev-certs install")
    if [[ "${FAKE_DOTNET_FAIL_INSTALL_ONCE:-0}" -eq 1 && ! -f "$fake_root/linux-dev-certs-failed" ]]; then
      touch "$fake_root/linux-dev-certs-failed"
      printf "Unable to excute 'sudo dotnet dev-certs https --clean': There was an error trying to clean HTTPS development certificates on this machine.\n" >&2
      printf "There was an error removing the certificate with thumbprint '94B87DEF03A43EF82C05F0EE56786A2118929953'.\n" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$ZZ_DOTNET_DEVCERT_CA_CERT")"
    printf 'fake cert\n' >"$ZZ_DOTNET_DEVCERT_CA_CERT"
    ;;
  "dev-certs https --clean")
    stale_pfx="$ZZ_DOTNET_HOME/.dotnet/corefx/cryptography/x509stores/my/94B87DEF03A43EF82C05F0EE56786A2118929953.pfx"
    if [[ "${FAKE_DOTNET_FAIL_CLEAN_WHILE_STALE_EXISTS:-0}" -eq 1 && -f "$stale_pfx" ]]; then
      printf "There was an error trying to clean HTTPS development certificates on this machine.\n" >&2
      printf "There was an error removing the certificate with thumbprint '94B87DEF03A43EF82C05F0EE56786A2118929953'.\n" >&2
      exit 1
    fi
    touch "$fake_root/dotnet-dev-certs-cleaned"
    ;;
esac
EOF
}

write_fake_certutil() {
  write_fake_command certutil <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'certutil %s\n' "$*" >>"$COMMAND_LOG"
case "$1" in
  -L)
    exit 1
    ;;
  -A|-D)
    exit 0
    ;;
esac
EOF
}

write_fake_firefox() {
  write_fake_command firefox <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
}

@test "zz dotnet exposes devcert help" {
  run bash "$ROOT_DIR/bin/zz" dotnet --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "zz dotnet <command>"
  assert_contains "$output" "devcert"

  run bash "$ROOT_DIR/bin/zz" dotnet devcert --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "zz dotnet devcert <command>"
  assert_contains "$output" "status"
  assert_contains "$output" "create"
}

@test "zz dotnet devcert status reports missing dotnet without failing" {
  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" \
    bash "$ROOT_DIR/bin/zz" dotnet devcert status

  [ "$status" -eq 0 ]
  assert_contains "$output" "dotnet: not installed"
}

@test "zz dotnet devcert create installs and imports into browser profiles" {
  write_fake_dotnet
  write_fake_certutil

  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" \
    COMMAND_LOG="$COMMAND_LOG" ZZ_DOTNET_DEVCERT_CA_CERT="$TEST_ROOT/ca/aspnet-dev-test.pem" \
    bash "$ROOT_DIR/bin/zz" dotnet devcert create

  [ "$status" -eq 0 ]
  assert_contains "$output" "Generating dev certificate"
  assert_contains "$output" "Imported into: dev.default"
  assert_file_contains "$COMMAND_LOG" "dotnet tool list -g"
  assert_file_contains "$COMMAND_LOG" "dotnet linux-dev-certs install"
  assert_file_contains "$COMMAND_LOG" "certutil -A -d sql:$TARGET_HOME/.mozilla/firefox/dev.default -n ASP.NET Core Dev Cert -t CT,C,C -i $TEST_ROOT/ca/aspnet-dev-test.pem"
}

@test "zz dotnet devcert create finds XDG Firefox profile path" {
  rm -rf "$TARGET_HOME/.mozilla/firefox/dev.default"
  mkdir -p "$TARGET_HOME/.config/mozilla/firefox/xdg.default-release"
  touch "$TARGET_HOME/.config/mozilla/firefox/xdg.default-release/cert9.db"
  write_fake_dotnet
  write_fake_certutil

  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" \
    ZZ_DOTNET_CONFIG_HOME="$TARGET_HOME/.config" \
    COMMAND_LOG="$COMMAND_LOG" ZZ_DOTNET_DEVCERT_CA_CERT="$TEST_ROOT/ca/aspnet-dev-test.pem" \
    bash "$ROOT_DIR/bin/zz" dotnet devcert create

  [ "$status" -eq 0 ]
  assert_contains "$output" "Imported into: xdg.default-release"
  assert_file_contains "$COMMAND_LOG" "certutil -A -d sql:$TARGET_HOME/.config/mozilla/firefox/xdg.default-release -n ASP.NET Core Dev Cert -t CT,C,C -i $TEST_ROOT/ca/aspnet-dev-test.pem"
}

@test "zz dotnet devcert create retries when linux-dev-certs clean fails" {
  write_fake_dotnet
  write_fake_certutil

  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" TEST_ROOT="$TEST_ROOT" \
    COMMAND_LOG="$COMMAND_LOG" ZZ_DOTNET_DEVCERT_CA_CERT="$TEST_ROOT/ca/aspnet-dev-test.pem" \
    FAKE_DOTNET_FAIL_INSTALL_ONCE=1 \
    bash "$ROOT_DIR/bin/zz" dotnet devcert create

  [ "$status" -eq 0 ]
  assert_contains "$output" "Retrying cleanup as the current user"
  [[ -f "$TEST_ROOT/dotnet-dev-certs-cleaned" ]]
  assert_file_contains "$COMMAND_LOG" "dotnet dev-certs https --clean"
  assert_equal "2" "$(grep -Fc "dotnet linux-dev-certs install" "$COMMAND_LOG")"
}

@test "zz dotnet devcert create quarantines stale pfx when dotnet cleanup cannot remove it" {
  write_fake_dotnet
  write_fake_certutil
  stale_dir="$TARGET_HOME/.dotnet/corefx/cryptography/x509stores/my"
  mkdir -p "$stale_dir"
  printf 'stale pfx\n' >"$stale_dir/94B87DEF03A43EF82C05F0EE56786A2118929953.pfx"

  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" TEST_ROOT="$TEST_ROOT" \
    COMMAND_LOG="$COMMAND_LOG" ZZ_DOTNET_DEVCERT_CA_CERT="$TEST_ROOT/ca/aspnet-dev-test.pem" \
    FAKE_DOTNET_FAIL_INSTALL_ONCE=1 FAKE_DOTNET_FAIL_CLEAN_WHILE_STALE_EXISTS=1 \
    bash "$ROOT_DIR/bin/zz" dotnet devcert create

  [ "$status" -eq 0 ]
  assert_contains "$output" "Moving the stale .NET user-store PFX aside"
  [[ ! -f "$stale_dir/94B87DEF03A43EF82C05F0EE56786A2118929953.pfx" ]]
  compgen -G "$stale_dir/94B87DEF03A43EF82C05F0EE56786A2118929953.pfx.zz-quarantine-*" >/dev/null
  assert_file_contains "$COMMAND_LOG" "dotnet dev-certs https --clean"
  assert_equal "2" "$(grep -Fc "dotnet dev-certs https --clean" "$COMMAND_LOG")"
  assert_equal "2" "$(grep -Fc "dotnet linux-dev-certs install" "$COMMAND_LOG")"
}

@test "zz dotnet devcert create explains installed browser without profile database" {
  rm -rf "$TARGET_HOME/.mozilla/firefox/dev.default"
  write_fake_dotnet
  write_fake_firefox

  run env PATH="$FAKE_BIN:/usr/bin:/bin" ZZ_DOTNET_HOME="$TARGET_HOME" \
    COMMAND_LOG="$COMMAND_LOG" ZZ_DOTNET_DEVCERT_CA_CERT="$TEST_ROOT/ca/aspnet-dev-test.pem" \
    bash "$ROOT_DIR/bin/zz" dotnet devcert create

  [ "$status" -eq 0 ]
  assert_contains "$output" "Firefox-style browser is installed, but no profile certificate database was found."
  assert_contains "$output" 'Launch the browser once to create a profile'
  assert_contains "$output" "Skipping NSS import."
}

#!/usr/bin/env bats

load "helpers/common"

HELPER="$ROOT_DIR/dotfiles/greetd/greeter-wait-for-gpu"
DROP_IN="$ROOT_DIR/dotfiles/greetd/50-zz-gpu-ready.conf"

setup() {
  setup_test_env
  # shellcheck source=../dotfiles/greetd/greeter-wait-for-gpu
  source "$HELPER"
  PCI="$TEST_ROOT/sys/bus/pci/devices"
  GPU_WAIT_PCI_DEVICES_ROOT="$PCI"
  GPU_WAIT_DEV_ROOT="$TEST_ROOT/dev/dri"
  GPU_WAIT_TIMEOUT=5
  mkdir -p "$PCI"
  CALLS="$TEST_ROOT/calls"
  : >"$CALLS"

  # Records each wait without --timeout (so assertions do not depend on clock
  # ticks), keeps the last timeout, and runs the per-call udev_effect hook.
  UDEV_CALL=0
  udevadm() {
    local arg
    local -a recorded=()
    for arg in "$@"; do
      if [[ "$arg" == --timeout=* ]]; then
        printf '%s\n' "${arg#--timeout=}" >"$TEST_ROOT/udev-timeout"
      else
        recorded+=("$arg")
      fi
    done
    printf 'udevadm %s\n' "${recorded[*]}" >>"$CALLS"
    UDEV_CALL=$((UDEV_CALL + 1))
    udev_effect "$UDEV_CALL"
  }
  udev_effect() { :; }
}

make_pci() {
  mkdir -p "$PCI/$1"
  printf '%s\n' "$2" >"$PCI/$1/class"
}

add_drm_nodes() {
  local address="$1" node
  shift
  for node in "$@"; do
    mkdir -p "$PCI/$address/drm/$node"
  done
}

@test "hosts without a display controller start the greeter immediately" {
  make_pci 0000:00:1f.3 0x040300

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_equal "" "$(cat "$CALLS")"
}

@test "the greeter waits for every display controller, then for the nodes their drivers registered" {
  make_pci 0000:00:02.0 0x030000
  make_pci 0000:01:00.0 0x030000
  make_pci 0000:01:00.1 0x040300
  make_pci 0000:02:00.0 0x030200
  add_drm_nodes 0000:00:02.0 card0 renderD128
  # nvidia_drm registers the NVIDIA nodes while udev processes the
  # controller's event, i.e. during the first wait.
  udev_effect() {
    [[ "$1" -eq 1 ]] || return 0
    add_drm_nodes 0000:01:00.0 card1 renderD129
  }

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_equal \
    "udevadm wait --initialized=yes $PCI/0000:00:02.0 $PCI/0000:01:00.0 $PCI/0000:02:00.0"$'\n'"udevadm wait --initialized=yes $GPU_WAIT_DEV_ROOT/card0 $GPU_WAIT_DEV_ROOT/renderD128 $GPU_WAIT_DEV_ROOT/card1 $GPU_WAIT_DEV_ROOT/renderD129" \
    "$(cat "$CALLS")"
  assert_equal "" "$output"
}

@test "a display controller without a driver has no nodes to wait for" {
  make_pci 0000:01:00.0 0x030000

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_equal "udevadm wait --initialized=yes $PCI/0000:01:00.0" "$(cat "$CALLS")"
  assert_equal "" "$output"
}

@test "a controller udev never finishes with still lets the greeter start" {
  make_pci 0000:01:00.0 0x030000
  add_drm_nodes 0000:01:00.0 card1 renderD128
  udev_effect() { return 1; }

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_equal "udevadm wait --initialized=yes $PCI/0000:01:00.0" "$(cat "$CALLS")"
  assert_contains "$output" "udev did not finish with 0000:01:00.0 within 5s"
}

@test "the node wait gets only the time left in the shared deadline" {
  make_pci 0000:01:00.0 0x030000
  add_drm_nodes 0000:01:00.0 card1 renderD128
  udev_effect() {
    [[ "$1" -eq 1 ]] || return 0
    SECONDS=$((SECONDS + 3))
  }

  run gpu_wait_main

  [ "$status" -eq 0 ]
  local timeout
  timeout="$(cat "$TEST_ROOT/udev-timeout")"
  [ "$timeout" -ge 1 ]
  [ "$timeout" -le 2 ]
}

@test "an exhausted deadline skips the node wait and starts the greeter" {
  make_pci 0000:01:00.0 0x030000
  add_drm_nodes 0000:01:00.0 card1 renderD128
  udev_effect() { SECONDS=$((SECONDS + 10)); }

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_equal "udevadm wait --initialized=yes $PCI/0000:01:00.0" "$(cat "$CALLS")"
  assert_contains "$output" "did not initialize"
}

@test "a node udev never initializes still lets the greeter start" {
  make_pci 0000:01:00.0 0x030000
  add_drm_nodes 0000:01:00.0 card1 renderD128
  udev_effect() { [[ "$1" -eq 1 ]]; }

  run gpu_wait_main

  [ "$status" -eq 0 ]
  assert_contains "$output" "udev did not initialize $GPU_WAIT_DEV_ROOT/card1 $GPU_WAIT_DEV_ROOT/renderD128"
}

@test "the greetd drop-in runs the installed helper without making its failure fatal" {
  local helper_path
  helper_path="$(awk -F'\t' '$5 == "dotfiles/greetd/greeter-wait-for-gpu" { print $2 }' "$ROOT_DIR/config/managed-config.tsv")"

  assert_equal "/usr/lib/zz/greeter-wait-for-gpu" "$helper_path"
  assert_file_contains "$DROP_IN" "ExecStartPre=-/usr/bin/bash $helper_path"
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'greeter-gpu-wait\t/usr/lib/systemd/system/greetd.service.d/50-zz-gpu-ready.conf\tsystem-file\tregenerate\tdotfiles/greetd/50-zz-gpu-ready.conf'
}

@test "the helper's shared deadline stays well inside greetd's start timeout" {
  # greetd keeps systemd's 90s default; the drop-in must not shorten it.
  run grep -q 'TimeoutStartSec' "$DROP_IN"
  [ "$status" -ne 0 ]
  source "$HELPER"
  [ "$GPU_WAIT_TIMEOUT" -le 30 ]
}

@test "the base plan installs the greeter GPU wait on every install" {
  source_core
  build_test_plan

  assert_plan_has "$PLAN_DIR/files/managed-files.list" "/usr/lib/zz/greeter-wait-for-gpu"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "/usr/lib/systemd/system/greetd.service.d/50-zz-gpu-ready.conf"
}

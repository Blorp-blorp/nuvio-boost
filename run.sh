#!/usr/bin/env bash
# Nuvio Boost: makes sideloaded Nuvio run like the Play Store version
# on Android TV, Google TV, Nvidia Shield and Fire TV.
# https://github.com/Blorp-blorp/nuvio-boost
#
# Everything is wrapped in main() so nothing runs unless the whole
# script downloaded successfully.

main() {
  APP_DIR="$HOME/.nuvio-boost"
  SAVED_FILE="$APP_DIR/devices.txt"
  DEFAULT_PORT=5555

  if [ -t 1 ]; then
    G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'
  else
    G=""; Y=""; R=""; B=""; N=""
  fi

  ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
  warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
  fail() { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
  info() { printf '  %s\n' "$*"; }
  # Read from the keyboard even when the script itself is piped in via curl | bash
  ask()  { local reply; printf '%s' "$1" > /dev/tty; IFS= read -r reply < /dev/tty || reply=""; printf '%s' "$reply"; }

  printf '\n%sNuvio Boost%s\n\n' "$B" "$N"

  if ! { : < /dev/tty; } 2>/dev/null; then
    fail "This script needs to be run from an interactive terminal."
    return 1
  fi

  case "$(uname -s)" in
    Darwin) PLATFORM=darwin ;;
    Linux)  PLATFORM=linux ;;
    *) fail "Unsupported system. On Windows, use run.ps1 (see the README)."; return 1 ;;
  esac

  # ---- Get adb -----------------------------------------------------------
  if command -v adb >/dev/null 2>&1; then
    ADB="$(command -v adb)"
    ok "Using adb already installed at $ADB"
  elif [ -x "$APP_DIR/platform-tools/adb" ]; then
    ADB="$APP_DIR/platform-tools/adb"
    ok "Using adb from a previous run"
  else
    info "Downloading Android platform-tools (adb) from Google..."
    if ! command -v unzip >/dev/null 2>&1; then
      fail "'unzip' is required. Install it (e.g. sudo apt install unzip) and run again."
      return 1
    fi
    mkdir -p "$APP_DIR"
    if ! curl -fsSL -o "$APP_DIR/platform-tools.zip" \
        "https://dl.google.com/android/repository/platform-tools-latest-$PLATFORM.zip"; then
      fail "Download failed. Check your internet connection and try again."
      return 1
    fi
    rm -rf "$APP_DIR/platform-tools"
    unzip -q -o "$APP_DIR/platform-tools.zip" -d "$APP_DIR" && rm -f "$APP_DIR/platform-tools.zip"
    ADB="$APP_DIR/platform-tools/adb"
    if [ ! -x "$ADB" ]; then fail "Could not unpack adb."; return 1; fi
    ok "adb ready"
  fi

  # Fresh adb server avoids stale connections and permission problems
  "$ADB" kill-server >/dev/null 2>&1
  "$ADB" start-server >/dev/null 2>&1

  # ---- Newer Google TV: Wireless debugging + one-time pairing -----------
  connect_wireless() {
    local main pair_addr code out
    info "On the TV: Developer options > Wireless debugging (turn it on)."
    main="$(ask "  IP address & port shown on the Wireless debugging screen (e.g. 192.168.1.50:37123): ")"
    [ -n "$main" ] || return 1
    out="$("$ADB" connect "$main" 2>&1)"
    sleep 2
    if [[ "$out" == *"connected to"* ]] && [ "$("$ADB" -s "$main" get-state 2>/dev/null)" = "device" ]; then
      ok "Connected"; FINAL_TARGET="$main"; return 0
    fi
    "$ADB" disconnect "$main" >/dev/null 2>&1
    info "This computer needs to be paired with the TV once."
    info "On the TV: Wireless debugging > Pair device with pairing code."
    pair_addr="$(ask "  IP address & port shown in the pairing popup: ")"
    code="$(ask "  Pairing code: ")"
    out="$("$ADB" pair "$pair_addr" "$code" 2>&1)"
    case "$out" in
      *"Successfully paired"*) ok "Paired" ;;
      *) fail "Pairing failed: $out"; return 1 ;;
    esac
    out="$("$ADB" connect "$main" 2>&1)"
    case "$out" in
      *"connected to"*) ok "Connected"; FINAL_TARGET="$main" ;;
      *) fail "Couldn't connect: $out"; return 1 ;;
    esac
  }

  # ---- Boost one TV ------------------------------------------------------
  boost() {
    local target="$1" out yn state i warned pkgs p res all_ok
    FINAL_TARGET="$target"

    out="$("$ADB" connect "$target" 2>&1)"
    case "$out" in
      *"connected to"*) ok "Connected" ;;
      *"Operation not permitted"*)
        fail "Your Mac is blocking local network access for this Terminal app."
        info "Fix: System Settings > Privacy & Security > Local Network > turn on your Terminal app."
        info "Then quit and reopen Terminal and run this again."
        return 1 ;;
      *)
        fail "Couldn't connect: $out"
        info "Check: the TV is on, the IP is right, and ADB / Network debugging is turned on."
        yn="$(ask "  Is this a newer Google TV using 'Wireless debugging'? [y/N]: ")"
        case "$yn" in
          y|Y|yes|Yes|YES) connect_wireless || return 1; target="$FINAL_TARGET" ;;
          *) return 1 ;;
        esac ;;
    esac

    # Wait for the "Allow debugging?" popup to be accepted
    state=""; i=0; warned=0
    while [ $i -lt 90 ]; do
      state="$("$ADB" -s "$target" get-state 2>/dev/null)"
      [ "$state" = "device" ] && break
      if [ $warned -eq 0 ]; then
        warn "Look at your TV: allow debugging and tick 'Always allow from this computer'."
        warned=1
      fi
      sleep 1; i=$((i + 1))
    done
    if [ "$state" != "device" ]; then
      fail "The TV didn't authorize this computer. Run again and accept the popup on the TV."
      return 1
    fi

    pkgs="$("$ADB" -s "$target" shell pm list packages 2>/dev/null | tr -d '\r' | grep -i nuvio | sed 's/^package://')"
    if [ -z "$pkgs" ]; then fail "Nuvio isn't installed on this TV."; return 1; fi

    all_ok=1
    for p in $pkgs; do
      info "Compiling $p (can take 1-2 minutes)..."
      res="$("$ADB" -s "$target" shell pm compile -m speed -f "$p" 2>&1 | tr -d '\r')"
      case "$res" in
        *Success*) ok "Boosted $p" ;;
        *) fail "Compile failed for $p: $res"; all_ok=0 ;;
      esac
    done
    "$ADB" disconnect "$target" >/dev/null 2>&1
    [ $all_ok -eq 1 ]
  }


  # ---- One-word shortcut for next time -----------------------------------
  install_shortcut() {
    local rc yn
    case "$(basename "${SHELL:-}")" in
      zsh)  rc="$HOME/.zshrc" ;;
      bash) if [ "$PLATFORM" = darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
      *)    return 1 ;;
    esac
    grep -q "alias nuvioboost=" "$rc" 2>/dev/null && return 0
    [ -f "$APP_DIR/no-shortcut" ] && return 1
    echo
    yn="$(ask "  Create a 'nuvioboost' shortcut so next time you just type nuvioboost? [Y/n]: ")"
    case "$yn" in
      n|N|no|No|NO) touch "$APP_DIR/no-shortcut"; return 1 ;;
    esac
    printf '\n# Nuvio Boost shortcut\nalias nuvioboost='"'"'curl -fsSL https://raw.githubusercontent.com/Blorp-blorp/nuvio-boost/main/run.sh | bash'"'"'\n' >> "$rc"
    ok "Shortcut added."
    return 0
  }

  # ---- Which TVs? ----------------------------------------------------------
  SAVED=""
  [ -f "$SAVED_FILE" ] && SAVED="$(tr '\n' ' ' < "$SAVED_FILE" | sed 's/ *$//')"
  echo
  if [ -n "$SAVED" ]; then
    info "Saved TVs: $SAVED"
    INPUT="$(ask "  Press Enter to use these, or type new IP addresses (space-separated): ")"
    [ -z "$INPUT" ] && INPUT="$SAVED"
  else
    info "Find your TV's IP address in its Settings > Network (e.g. 192.168.1.50)."
    INPUT="$(ask "  Enter TV IP address(es), separated by spaces: ")"
  fi
  if [ -z "$INPUT" ]; then fail "No IP address entered."; return 1; fi

  USED=""; TOTAL=0; DONE=0
  for T in $INPUT; do
    case "$T" in *:*) ;; *) T="$T:$DEFAULT_PORT" ;; esac
    TOTAL=$((TOTAL + 1))
    printf '\n%s%s%s\n' "$B" "$T" "$N"
    if boost "$T"; then DONE=$((DONE + 1)); fi
    USED="$USED $FINAL_TARGET"
  done

  mkdir -p "$APP_DIR"
  # shellcheck disable=SC2086
  printf '%s\n' $USED > "$SAVED_FILE"
  "$ADB" kill-server >/dev/null 2>&1

  HAS_SHORTCUT=0
  if [ "$DONE" -gt 0 ] && install_shortcut; then HAS_SHORTCUT=1; fi

  echo
  if [ "$DONE" -eq "$TOTAL" ]; then
    ok "Done: $DONE of $TOTAL TV(s) boosted."
  else
    warn "Done: $DONE of $TOTAL TV(s) boosted. Fix the issues above and run again."
  fi
  if [ "$HAS_SHORTCUT" -eq 1 ]; then
    printf '\n  %sAfter the next Nuvio update, open a new Terminal window and type: nuvioboost%s\n' "$B" "$N"
  else
    info "Run this again after each Nuvio update."
  fi
  echo
}

main "$@"

#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly BINARY_PATH="${SCRIPT_DIR}/SwiftTemp"
readonly PLIST_DIR="${HOME}/Library/LaunchAgents"
readonly PLIST_PATH="${PLIST_DIR}/com.kastner.swifttemp.plist"
readonly LAUNCH_TARGET="gui/$(id -u)"

usage() {
    cat <<EOF
Usage: ./startup.sh <add|update|remove>

Commands:
  add     Install SwiftTemp as a login item for the current user
  update  Rewrite the launch agent and reload it
  remove  Unload the launch agent and delete it
EOF
}

write_plist() {
    mkdir -p "${PLIST_DIR}"

    cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kastner.swifttemp</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
}

ensure_binary() {
    if [[ ! -x "${BINARY_PATH}" ]]; then
        echo "Expected executable at ${BINARY_PATH}" >&2
        echo "Build it first with:" >&2
        echo "  swiftc -parse-as-library -framework SwiftUI -framework AppKit -o SwiftTemp SwiftTemp.swift" >&2
        exit 1
    fi
}

load_agent() {
    launchctl bootstrap "${LAUNCH_TARGET}" "${PLIST_PATH}"
}

unload_agent_if_present() {
    launchctl bootout "${LAUNCH_TARGET}" "${PLIST_PATH}" 2>/dev/null || true
}

add_agent() {
    ensure_binary

    if [[ -f "${PLIST_PATH}" ]]; then
        echo "Launch agent already exists at ${PLIST_PATH}" >&2
        echo "Use './startup.sh update' to reload it." >&2
        exit 1
    fi

    write_plist
    load_agent
    echo "Installed SwiftTemp to launch at login."
}

update_agent() {
    ensure_binary
    write_plist
    unload_agent_if_present
    load_agent
    echo "Updated SwiftTemp launch agent."
}

remove_agent() {
    unload_agent_if_present
    rm -f "${PLIST_PATH}"
    echo "Removed SwiftTemp launch agent."
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi

    case "$1" in
        add)
            add_agent
            ;;
        update)
            update_agent
            ;;
        remove)
            remove_agent
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

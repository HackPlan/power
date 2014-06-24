#!/bin/sh
#
#     This is the installation script for Power.
#     See the full annotated source: http://power.hackplan.com
#
#     Install Power by running this command:
#     curl power.hackplan.com/install.sh | sh
#
#     Uninstall Power: :'(
#     curl power.hackplan.com/uninstall.sh | sh

# Set up the environment. Respect $VERSION if it's set.

      set -e
      POWER_ROOT="$HOME/Library/Application Support/Power"
      NODE_BIN="$POWER_ROOT/Current/bin/node"
      POWER_BIN="$POWER_ROOT/Current/bin/power"
      [[ -z "$VERSION" ]] && VERSION=0.0.1


# Fail fast if we're not on OS X >= 10.6.0.

      if [ "$(uname -s)" != "Darwin" ]; then
        echo "Sorry, Power requires Mac OS X to run." >&2
        exit 1
      elif [ "$(expr "$(sw_vers -productVersion | cut -f 2 -d .)" \>= 6)" = 0 ]; then
        echo "Power requires Mac OS X 10.6 or later." >&2
        exit 1
      fi

      echo "*** Installing Power $VERSION..."


# Create the Power directory structure if it doesn't already exist.

      mkdir -p "$POWER_ROOT/Hosts" "$POWER_ROOT/Versions"


# If the requested version of Power is already installed, remove it first.

      cd "$POWER_ROOT/Versions"
      rm -rf "$POWER_ROOT/Versions/$VERSION"


# Download the requested version of Power and unpack it.

      curl -s http://power.hackplan.com/versions/$VERSION.tar.gz | tar xzf -


# Update the Current symlink to point to the new version.

      cd "$POWER_ROOT"
      rm -f Current
      ln -s Versions/$VERSION Current


# Create the ~/.power symlink if it doesn't exist.

      cd "$HOME"
      [[ -a .power ]] || ln -s "$POWER_ROOT/Hosts" .power


# Install local configuration files.

      echo "*** Installing local configuration files..."
      "$NODE_BIN" "$POWER_BIN" --install-local


# Check to see whether we need root privileges.

      "$NODE_BIN" "$POWER_BIN" --install-system --dry-run >/dev/null && NEEDS_ROOT=0 || NEEDS_ROOT=1


# Install system configuration files, if necessary. (Avoid sudo otherwise.)

      if [ $NEEDS_ROOT -eq 1 ]; then
        echo "*** Installing system configuration files as root..."
        sudo "$NODE_BIN" "$POWER_BIN" --install-system
        sudo launchctl load -Fw /Library/LaunchDaemons/com.hackplan.power.firewall.plist 2>/dev/null
      fi


# Start (or restart) Power.

      echo "*** Starting the Power server..."
      launchctl unload "$HOME/Library/LaunchAgents/com.hackplan.power.powerd.plist" 2>/dev/null || true
      launchctl load -Fw "$HOME/Library/LaunchAgents/com.hackplan.power.powerd.plist" 2>/dev/null


# Show a message about where to go for help.

      function print_troubleshooting_instructions() {
        echo
        echo "For troubleshooting instructions, please see the Power wiki:"
        echo "https://github.com/hackplan/power/wiki/Troubleshooting"
        echo
        echo "To uninstall Power, \`curl power.hackplan.com/uninstall.sh | sh\`"
      }


# Check to see if the server is running properly.

      # If this version of Power supports the --print-config option,
      # source the configuration and use it to run a self-test.
      CONFIG=$("$NODE_BIN" "$POWER_BIN" --print-config 2>/dev/null || true)

      if [[ -n "$CONFIG" ]]; then
        eval "$CONFIG"
        echo "*** Performing self-test..."

        # Check to see if the server is running at all.
        function check_status() {
          sleep 1
          curl -sH host:power "localhost:$POWER_HTTP_PORT/status.json" | grep -c "$VERSION" >/dev/null
        }

        # Attempt to connect to Power via each configured domain. If a
        # domain is inaccessible, try to force a reload of OS X's
        # network configuration.
        function check_domains() {
          for domain in ${POWER_DOMAINS//,/$IFS}; do
            echo | nc "${domain}." "$POWER_DST_PORT" 2>/dev/null || return 1
          done
        }

        # Use networksetup(8) to create a temporary network location,
        # switch to it, switch back to the original location, then
        # delete the temporary location. This forces reloading of the
        # system network configuration.
        function reload_network_configuration() {
          echo "*** Reloading system network configuration..."
          local location=$(networksetup -getcurrentlocation)
          networksetup -createlocation "power$$" >/dev/null 2>&1
          networksetup -switchtolocation "power$$" >/dev/null 2>&1
          networksetup -switchtolocation "$location" >/dev/null 2>&1
          networksetup -deletelocation "power$$" >/dev/null 2>&1
        }

        # Try twice to connect to Power. Bail if it doesn't work.
        check_status || check_status || {
          echo "!!! Couldn't find a running Power server on port $POWER_HTTP_PORT"
          print_troubleshooting_instructions
          exit 1
        }

        # Try resolving and connecting to each configured domain. If
        # it doesn't work, reload the network configuration and try
        # again. Bail if it fails the second time.
        check_domains || {
          { reload_network_configuration && check_domains; } || {
            echo "!!! Couldn't resolve configured domains ($POWER_DOMAINS)"
            print_troubleshooting_instructions
            exit 1
          }
        }
      fi


# All done!

      echo "*** Installed"
      print_troubleshooting_instructions

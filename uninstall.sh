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


# Set up the environment.

      set -e
      POWER_ROOT="$HOME/Library/Application Support/Power"
      POWER_CURRENT_PATH="$POWER_ROOT/Current"
      POWER_VERSIONS_PATH="$POWER_ROOT/Versions"
      POWERD_PLIST_PATH="$HOME/Library/LaunchAgents/com.hackplan.power.powerd.plist"
      FIREWALL_PLIST_PATH="/Library/LaunchDaemons/com.hackplan.power.firewall.plist"
      POWER_CONFIG_PATH="$HOME/.powerconfig"

# Fail fast if Power isn't present.

      if [[ ! -d "$POWER_CURRENT_PATH" ]] && [[ ! -a "$POWERD_PLIST_PATH" ]] && [[ ! -a "$FIREWALL_PLIST_PATH" ]]; then
        echo "error: can't find Power" >&2
        exit 1
      fi


# Find the tty so we can prompt for confirmation even if we're being piped from curl.

      TTY="/dev/$( ps -p$$ -o tty | tail -1 | awk '{print$1}' )"


# Make sure we really want to uninstall.

      read -p "Sorry to see you go. Uninstall Power [y/n]? " ANSWER < $TTY
      [[ $ANSWER == "y" ]] || exit 1
      echo "*** Uninstalling Power..."


# Remove the Versions directory and the Current symlink.

      rm -fr "$POWER_VERSIONS_PATH"
      rm -f "$POWER_CURRENT_PATH"


# Unload com.hackplan.power.powerd from launchctl and remove the plist.

      launchctl unload "$POWERD_PLIST_PATH" 2>/dev/null || true
      rm -f "$POWERD_PLIST_PATH"


# Read the firewall plist, if possible, to figure out what ports are in use.

      if [[ -a "$FIREWALL_PLIST_PATH" ]]; then
        ports=($(ruby -e'puts $<.read.scan(/fwd .*?,([\d]+).*?dst-port ([\d]+)/)' "$FIREWALL_PLIST_PATH"))

        HTTP_PORT=${ports[0]}
        DST_PORT=${ports[1]}
      fi


# Assume reasonable defaults otherwise.

      [[ -z "$HTTP_PORT" ]] && HTTP_PORT=20559
      [[ -z "$DST_PORT" ]] && DST_PORT=80


# Try to find the ipfw rule and delete it.

      RULE=$(sudo ipfw show | (grep ",$HTTP_PORT .* dst-port $DST_PORT in" || true) | cut -f 1 -d " ")
      [[ -n "$RULE" ]] && sudo ipfw del "$RULE"


# Unload the firewall plist and remove it.

      sudo launchctl unload "$FIREWALL_PLIST_PATH" 2>/dev/null || true
      sudo rm -f "$FIREWALL_PLIST_PATH"


# Remove /etc/resolver files that belong to us
      grep -Rl 'generated by Power' /etc/resolver/ | sudo xargs rm

      echo "*** Uninstalled"

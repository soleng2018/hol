#!/bin/bash

# Make script executable
chmod +x "$0"

install_required_packages() {
  if ! command -v brew &> /dev/null; then
    echo "$(date): Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "$(date): Homebrew already installed."
  fi

  if ! command -v sudo &> /dev/null; then
    echo "$(date): sudo not found, installing via brew..."
    brew install sudo
  else
    echo "$(date): sudo already installed."
  fi
}

get_usb_ethernet_interface() {
  networksetup -listallhardwareports | awk '
  $0 ~ /Hardware Port: USB 10\/100\/1000 LAN/ {getline; print $2; exit}
  '
}

assign_static_ip() {
  local iface=$1
  local ip=$2
  echo "$(date): Assigning IP $ip to interface $iface"
  sudo networksetup -setmanual "$iface" "$ip" 255.255.255.0 10.10.10.1
  sudo networksetup -setdnsservers "$iface" 8.8.8.8 4.2.2.2
}

main() {
  install_required_packages

  INTERFACE=$(get_usb_ethernet_interface)
  if [ -z "$INTERFACE" ]; then
    echo "$(date): ERROR - No USB Ethernet interface found."
    exit 1
  fi
  echo "$(date): Detected USB Ethernet interface: $INTERFACE"

  current_ip="10.10.10.150"
  assign_static_ip "$INTERFACE" "$current_ip"

  while true; do
    sleep_minutes=1
    echo "$(date): Sleeping $sleep_minutes minute(s) before toggling interface."
    sleep $((sleep_minutes * 60))

    echo "$(date): Bringing down interface $INTERFACE"
    sudo ifconfig "$INTERFACE" down

    while true; do
      new_octet=$((RANDOM % 11 + 150))
      new_ip="10.10.10.$new_octet"
      if [ "$new_ip" != "$current_ip" ]; then
        current_ip=$new_ip
        break
      fi
    done

    assign_static_ip "$INTERFACE" "$current_ip"

    echo "$(date): Bringing up interface $INTERFACE"
    sudo ifconfig "$INTERFACE" up
  done
}

main

#!/bin/bash

# If debug mode is on it will skip various steps like installing etc.
debugmode=on

echo "Checking status of your computer"

# Check if running as root  
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run with sudo or as root. Please run without sudo."
  exit 1
fi

# Find the logged-in user
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

# Check for Homebrew (https://brew.sh/)
if ! command -v brew &> /dev/null; then
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    # Update Homebrew
    brew upgrade
    wait
fi
echo "Homebrew command ran"

# Check CPU and adjust brew path if needed (Apple Silicon)
if [[ $(uname -p) == 'arm' ]]; then
  echo "Detected arm processor, updating brew path for Homebrew"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$loggedInUser/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "Brew installed - ready to install applications."

#-----------------------
# Download the iTerm2 plist file from GitHub to the logged-in user's Desktop
#-----------------------
PLIST_URL="https://raw.githubusercontent.com/jamieal/iTerm-Config/refs/heads/main/com.googlecode.iterm2.plist"
DESTINATION="/Users/$loggedInUser/Desktop/com.googlecode.iterm2.plist"
echo "Downloading iTerm2 configuration plist file to $DESTINATION..."
curl -L "$PLIST_URL" -o "$DESTINATION"

if [[ -f "$DESTINATION" ]]; then
    echo "Download successful: $DESTINATION"
else
    echo "Download failed!"
fi

#-----------------------
# Application Installation
#-----------------------

# Declare an array of applications
declare -a applications=(visual-studio-code Spotify Discord Rectangle iTerm2 Karabiner-Elements)
echo "Array list: ${applications[*]}"

if [[ $debugmode == "off" ]]; then
  echo "Debug mode is: $debugmode"
  echo "Installing applications now..."
  for i in "${applications[@]}"
  do  
      brew install --cask "$i"
      wait
  done
else
  echo "Debug mode on; not installing apps. Applications declared to be installed: ${applications[*]}"
fi

#-----------------------
# System Settings
#-----------------------

# Enable single-app mode and set Dock orientation
defaults write com.apple.dock single-app -bool TRUE
defaults write com.apple.dock orientation right

# Enable dark mode and set desktop background using AppleScript
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
osascript -e 'tell application "System Events" to set picture of every desktop to "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
killall Dock

#-----------------------
# Touch ID Check for sudo
#-----------------------
if grep -q "auth\s*sufficient\s*pam_tid.so" /etc/pam.d/sudo_local; then
    echo "Touch ID for sudo is enabled."
else
    echo "Touch ID for sudo is not enabled."
fi

exit 0

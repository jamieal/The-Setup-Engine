#!/bin/bash

# macOS Setup Script
# Written by Jamie Cras
# Version: 1.2

#-----------------------
# Declaring variables
#-----------------------

# If debug mode is on it will skip various steps like installing applications etc.
debugmode=on
# Get logged in user
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
USER_HOME=$(dscl . -read /Users/"$loggedInUser" NFSHomeDirectory | awk '{print $2}')
# Use AppleScript dialog instead of echo/read
debugModePrompt=$(osascript -e 'display dialog "Are you running in debug mode?" buttons {"No", "Yes"} default button "Yes"' -e 'button returned of result' 2>/dev/null)
SCREENSHOTS_DIR="$USER_HOME/Desktop/Screenshots"

# Check if dialog was actually cancelled (Escape key or Command+.)
if [ $? -ne 0 ]; then
    echo "Dialog cancelled. Exiting."
    exit 1
fi

if [[ "$debugModePrompt" == "Yes" ]]; then
  debugmode=on
  echo "Debug Mode is $debugmode"
elif [[ "$debugModePrompt" == "No" ]]; then
  debugmode=off
  echo "Debug Mode is $debugmode"
else
  echo "An error occurred with the dialog"
  exit 1
fi

# Check if running as root  
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run with sudo or as root. Please run without sudo."
  exit 1
fi

#-----------------------
# Screenshot Directory Setup
#-----------------------

echo "Setting up screenshot directory for user: $loggedInUser"

# Create the Screenshots directory if it doesn't exist
if [ ! -d "$SCREENSHOTS_DIR" ]; then
    if [[ $debugmode == "off" ]]; then
        mkdir -p "$SCREENSHOTS_DIR"
        echo "✓ Created Screenshots directory: $SCREENSHOTS_DIR"
    else
        echo "Debug mode: Would create Screenshots directory: $SCREENSHOTS_DIR"
    fi
else
    echo "✓ Screenshots directory already exists: $SCREENSHOTS_DIR"
fi

# Set proper ownership of the directory and configure screenshot location
if [[ $debugmode == "off" ]]; then
    chown "$loggedInUser:staff" "$SCREENSHOTS_DIR"
    echo "✓ Set ownership of Screenshots directory"
    
    # Configure macOS to save screenshots to the new directory
    defaults write com.apple.screencapture location "$SCREENSHOTS_DIR"
    killall SystemUIServer 2>/dev/null || true
    echo "✓ Configured screenshot save location to: $SCREENSHOTS_DIR"
else
    echo "Debug mode: Would set ownership and configure screenshot location"
fi

# Check for Homebrew (https://brew.sh/)
if ! command -v brew >/dev/null 2>&1; then
    if [[ $debugmode == "off" ]]; then
        # Install Homebrew
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo "Debug mode: Would install Homebrew"
    fi
else
    if [[ $debugmode == "off" ]]; then
        # Update Homebrew
        brew upgrade
    else
        echo "Debug mode: Would update Homebrew"
    fi
fi
echo "Homebrew command ran"

# Check CPU and adjust brew path if needed (Apple Silicon)
if [[ $(uname -p) == 'arm' ]]; then
  echo "Detected arm processor, updating brew path for Homebrew"
  if [[ $debugmode == "off" ]]; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$loggedInUser/.zprofile
      eval "$(/opt/homebrew/bin/brew shellenv)"
  else
      echo "Debug mode: Would update brew path"
  fi
  
  # Check if Rosetta is installed
  if /usr/bin/pgrep oahd >/dev/null 2>&1; then
      echo "Rosetta is installed"
  else
      echo "Rosetta is not installed"
      if [[ $debugmode == "off" ]]; then
          /usr/sbin/softwareupdate --install-rosetta --agree-to-license
      else
          echo "Debug mode: Would install Rosetta"
      fi
  fi
fi

echo "Brew installed - ready to install applications."

#-----------------------
# Application Installation
#-----------------------

# Declare an array of applications
declare -a applications=(visual-studio-code spotify discord rectangle iterm2 karabiner-elements displaylink)
echo "Array list: ${applications[*]}"

if [[ $debugmode == "off" ]]; then
  echo "Debug mode is: $debugmode"
  echo "Installing applications now..."
  for i in "${applications[@]}"
  do  
      brew install --cask "$i"
  done
else
  echo "Debug mode on; not installing apps. Applications declared to be installed: ${applications[*]}"
fi

#-----------------------
# Download the iTerm2 plist file from GitHub
#-----------------------

PLIST_URL="https://raw.githubusercontent.com/jamieal/iTerm-Config/refs/heads/main/com.googlecode.iterm2.plist"
DESTINATION="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

if [[ $debugmode == "off" ]]; then
    # Download iTerm2 config
    echo "Downloading iTerm2 configuration plist file to $DESTINATION..."
    curl -L "$PLIST_URL" -o "$DESTINATION"
    if [[ -f "$DESTINATION" ]]; then
        echo "Download successful: $DESTINATION"
        echo "iTerm2 configuration will be applied on next launch"
    else
        echo "Download failed!"
    fi
else
    echo "Debug mode: Would download iTerm2 config from $PLIST_URL"
fi

#-----------------------
# System Settings
#-----------------------

if [[ $debugmode == "off" ]]; then
    # Enable single-app mode and set Dock orientation
    defaults write com.apple.dock single-app -bool TRUE
    defaults write com.apple.dock orientation right

    # Enable dark mode
    osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
else
    echo "Debug mode: Would configure dock and enable dark mode"
fi

#-----------------------
# Configure Menu Bar
#-----------------------

#configures sound to go into the menu bar. 
defaults -currentHost write com.apple.controlcenter Sound -int 18
#configures bluetooth to go into the menu bar.
defaults -currentHost write com.apple.controlcenter Bluetooth -int 18




#-----------------------
# Download and set desktop wallpaper
#-----------------------

MY_BUCKET="wallpaper-collection"
IMAGES_FOLDER="$HOME/Documents/MyBackgroundImages"

#-----------------------
# Install AWS CLI
#-----------------------

echo "Installing AWS CLI..."
if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI not found"
    if [[ $debugmode == "off" ]]; then
        brew install awscli
        
        # Wait for installation to complete
        while ! command -v aws >/dev/null 2>&1; do
            echo "Waiting for AWS CLI installation..."
            sleep 2
        done
        echo "AWS CLI installed successfully."
    else
        echo "Debug mode: Would install AWS CLI"
    fi
else
    echo "AWS CLI is already installed."
fi

# Check AWS configuration (only if not in debug mode)
if [[ $debugmode == "off" ]]; then
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "AWS not configured. Please run 'aws configure' first."
        exit 1
    fi
    echo "AWS configuration verified"
else
    echo "Debug mode: Would check AWS configuration"
fi

#-----------------------
# Download Images
#-----------------------

echo "Creating folder and downloading images..."
mkdir -p "$IMAGES_FOLDER"

if [[ $debugmode == "off" ]]; then
    aws s3 sync "s3://$MY_BUCKET" "$IMAGES_FOLDER"
    if [ $? -eq 0 ]; then
        echo "Images downloaded successfully"
        ls -la "$IMAGES_FOLDER"
    else
        echo "Error downloading images"
        exit 1
    fi
else
    echo "Debug mode: Would download images from s3://$MY_BUCKET to $IMAGES_FOLDER"
fi

#-----------------------
# Set Desktop Background
#-----------------------

echo "Setting desktop background..."

if [[ $debugmode == "off" ]]; then
    IMAGES=($(find "$IMAGES_FOLDER" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | head -10))

    if [ ${#IMAGES[@]} -eq 0 ]; then
        echo "No images found in $IMAGES_FOLDER"
    else
        # Set different wallpaper for each desktop/display
        osascript <<EOF
tell application "System Events"
    set imageList to {"${IMAGES[0]}", "${IMAGES[1]}", "${IMAGES[2]}", "${IMAGES[3]}"}
    set desktopCount to count of desktops
    
    repeat with i from 1 to desktopCount
        set imageIndex to ((i - 1) mod (count of imageList)) + 1
        if imageIndex ≤ (count of imageList) then
            set picture of desktop i to (imageList's item imageIndex)
            log "Set desktop " & i & " to image " & imageIndex
        end if
    end repeat
end tell
EOF
        echo "Set different wallpapers for each display!"
    fi
else
    echo "Debug mode: Would set desktop wallpapers from downloaded images"
fi

if [[ $debugmode == "off" ]]; then
    killall Dock

    # Change date/time format to be 24hr
    defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
    # Change the date to D/M/Y
    defaults write NSGlobalDomain AppleICUDateFormatStrings -dict-add 1 "dd/MM/yyyy"
    # Apply the configurations
    killall SystemUIServer
    
    # Install Oh My Zsh
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "Debug mode: Would configure date/time format and install Oh My Zsh"
fi

#-----------------------
# Touch ID Check for sudo
#-----------------------
if grep -q "auth\s*sufficient\s*pam_tid.so" /etc/pam.d/sudo_local 2>/dev/null; then
    echo "Touch ID for sudo is enabled."
else
    echo "Touch ID for sudo is not enabled."
fi

echo "Setup complete!"
echo "Screenshots will now be saved to: $SCREENSHOTS_DIR"
echo "You can test this by taking a screenshot (Cmd+Shift+3 or Cmd+Shift+4)"
exit 0
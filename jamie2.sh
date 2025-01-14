#!/bin/bash


#if debug mode is on it will skip various steps like installing etc. 
debugmode=on

echo "Checking status of your computer"

#check for running as root  
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run with sudo or as root. Please run without sudo".
  exit 1
fi

#find user account
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

#check homebrew homebrew https://brew.sh/
which -s brew
if [[ $? != 0 ]] ; then
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    #update homebrew  
    brew upgrade
    wait
fi
echo "homebrew command ran"
#check CPU 
cpu="checking to see if Silicone"
if [[ $(uname -p) == 'arm' ]]; then
  cpu=$(uname -p)
  echo "Detected $cpu processor, making change to path for brew"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$loggedInUser/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "Brew installed - ready to install applications."





#declare array
declare -a applications=(visual-studio-code Spotify Discord Rectangle Iterm2 Karabiner-Elements)
echo "Array list: ${applications[*])}"


if [[ $debugmode == "off" ]]; then
  echo "debug mode is: $debugmode"
  echo "Installing applications now"
  for i in "${applications[@]}"
    do  
      brew install cask "$i"
      wait
  done
else
  echo "Debug mode on, not installing apps. Applications declared to be installed $applications[@]"
fi

#writing 
# turning on single-app mode
defaults write com.apple.dock single-app -bool TRUE
defaults write com.apple.dock orentation right
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
osascript -e 'tell application "System Events" to set picture of every desktop to "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
killall Dock

#check if touch id is setup
if [[ grep -q "auth\s*sufficient\s*pam_tid.so" /etc/pam.d/sudo_local ]]; then
    echo "Touch ID for sudo is enabled."
else
    echo "Touch ID for sudo is not enabled."
fi


exit 0
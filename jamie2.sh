#!/bin/bash

echo "Welcome to the installer"
#check homebrew homebrew https://brew.sh/
which -s brew
if [[ $? != 0 ]] ; then
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    #update homebrew  
    brew update
fi

wait 
echo "homebrew command ran"
#check chip architecture
cpuArc="checking to see if Silicone"
if [[ $(uname -p) == 'arm' ]]; then
  cpuArc=$(uname -p)
  echo "Detected $cpuArc processor, making change to path for brew"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/jcras/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "Brew installed - ready to install applications"
#installing applications
#check to see if these are installed 
#change dock and put on right/hide
#array the apps

#declare array
declare -a applications=(visual-studio-code Spotify Discord Rectamble Iterm2)

for i in "${applications[@]}"
  do  
    brew install cask "$i"
    wait
done


defaults write com.apple.dock single-app -bool TRUE
defaults write com.apple.dock orentation right
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
killall Dock

exit 0
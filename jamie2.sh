#!/bin/bash

echo "Running install script"
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
#if m1....
m1="checking to see if m1"
if [[ $(uname -p) == 'arm' ]]; then
  m1=$(uname -p)
  echo "Detected $m1 processor, making change to path for brew"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/jcras/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "Brew installed - ready to install applications"
#installing applications
#check to see if these are installed 
#change dock and put on right/hide
#array the apps
#osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/Downloads/cat.jpg"'


#check for app
#if [ -d "/Applications/zoom.us.app" ] ; then
#	zoomapp="Installed"
#	if [ -f "/Applications/zoom.us.app/Contents/Info.plist" ] ; then
#		zoomversion=$(defaults read "/Applications/zoom.us.app/Contents/Info.plist" CFBundleVersion)
#		#zoomversion=$(defaults read "/Applications/zoom.us.app/Contents/Info.plist" CFBundleShortVersionString)
#	else
#		zoomversion="Not Installed"
#	fi  
#else
#	ZOOM_INSTALL_VALIDATION_ERRORS+=("zoomapp: application not found")
#	zoomapp="Not Installed"
#fi


#declare array
#declare -a applications=(Spotify Discord Franz Rectangle visual-studio-code VLC microsoft-excel)
declare -a applications=(visual-studio-code)

for i in "${applications[@]}"
  do  
    brew install cask "$i"
    wait
done

#dock stuff

defaults write com.apple.dock single-app -bool TRUE
defaults write com.apple.dock orentation right
killall Dock



exit 0
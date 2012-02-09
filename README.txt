Information on using the Google Data APIs Objective-C Client Library 
is available at

http://code.google.com/p/gdata-objectivec-client/

INSTALATION

in your project directory run:
git submodule add git@github.com:appunite/gdata-objectivec-client.git Frameworks/GData

drag Frameworks/GData/Source/GData.xcodeproj to your project

add GDataTouchStaticLib (GData) to "Target Dependencies"
add libGDataTouchStaticLib.a
  add libGTMHTTPFetcher.a
  to "Link Binary With Libraries"
add "$(SOURCE_ROOT)/Frameworks/GData/Source/Build"
  add "$(SOURCE_ROOT)/Frameworks/GData/Source/Frameworks/GTMOAuth2/Source/Build"
  and "$(SOURCE_ROOT)/Frameworks/GData/Source/Frameworks/GTMOAuth2/Source/Frameworks/GTMHTTPFetcher/Source/Build"
  add "/usr/include/libxml2"
  to "Header Search Paths"


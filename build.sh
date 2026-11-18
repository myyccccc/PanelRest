#!/bin/zsh
# 用法：
#   ./build.sh            编译直装版并安装到 /Applications（自用）
#   ./build.sh appstore   编译 App Store 版（沙盒）用于本地测试
#   ./build.sh archive    归档 App Store 版，之后在 Xcode Organizer 里上传
set -e
cd "$(dirname "$0")"
# 源码在 T7（exFAT），编译产物放内置盘，避免 ._ 文件破坏签名
DD="$HOME/Library/Developer/Xcode/DerivedData/PanelRest-T7"
find . -name "._*" -delete 2>/dev/null || true
xcodegen generate --quiet
case "${1:-direct}" in
  direct)
    xcodebuild -project PanelRest.xcodeproj -scheme PanelRestDirect -configuration Release \
      -derivedDataPath "$DD" build -quiet
    APP="$DD/Build/Products/Release/PanelRest.app"
    pkill -x PanelRest 2>/dev/null || true; sleep 0.5
    rm -rf /Applications/PanelRest.app && cp -R "$APP" /Applications/
    open /Applications/PanelRest.app
    echo "已安装直装版 → /Applications/PanelRest.app" ;;
  appstore)
    xcodebuild -project PanelRest.xcodeproj -scheme PanelRest -configuration Debug \
      -derivedDataPath "$DD" build -quiet
    echo "App Store 版（沙盒）→ $DD/Build/Products/Debug/PanelRest.app" ;;
  archive)
    xcodebuild -project PanelRest.xcodeproj -scheme PanelRest -configuration Release \
      -derivedDataPath "$DD" -archivePath "$HOME/Library/Developer/Xcode/Archives/PanelRest-$(date +%Y%m%d-%H%M).xcarchive" \
      -allowProvisioningUpdates archive
    echo "归档完成：打开 Xcode › Window › Organizer 上传到 App Store Connect" ;;
esac

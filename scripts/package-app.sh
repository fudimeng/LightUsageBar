#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_path="${project_dir}/LightUsageBar.app"

cd "$project_dir"
swift build -c release

mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${project_dir}/AppResources/Info.plist" "${app_path}/Contents/Info.plist"
cp "${project_dir}/.build/release/LightUsageBar" "${app_path}/Contents/MacOS/LightUsageBar"
chmod 755 "${app_path}/Contents/MacOS/LightUsageBar"

# A local ad-hoc signature lets macOS validate the bundle without requiring an Apple Developer account.
xattr -cr "$app_path"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Built ${app_path}"

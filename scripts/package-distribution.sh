#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
dist_dir="${project_dir}/dist"
app_path="${dist_dir}/LightUsageBar.app"
build_dir=$(mktemp -d)
cd "$project_dir"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"

# Build without debug information and remap source paths before producing either slice.
for arch in arm64 x86_64; do
    xcrun swiftc -parse-as-library -O -gnone \
        -target "${arch}-apple-macosx14.0" \
        -file-prefix-map "${project_dir}=." \
        -debug-prefix-map "${project_dir}=." \
        Sources/LightUsageBar/*.swift -o "${build_dir}/LightUsageBar-${arch}"
    xcrun strip -S "${build_dir}/LightUsageBar-${arch}"
done
xcrun lipo -create "${build_dir}/LightUsageBar-arm64" "${build_dir}/LightUsageBar-x86_64" \
    -output "${app_path}/Contents/MacOS/LightUsageBar"
cp AppResources/Info.plist "${app_path}/Contents/Info.plist"
cp LICENSE "${app_path}/Contents/Resources/LICENSE"
xattr -cr "$app_path"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
plutil -lint "${app_path}/Contents/Info.plist"
if /usr/bin/strings "${app_path}/Contents/MacOS/LightUsageBar" | rg '/Users/|/private/var/folders/'; then
    echo "Distribution aborted: a personal build path remains." >&2
    exit 1
fi
archive="${dist_dir}/LightUsageBar-0.1.0-macos-universal.zip"
ditto -c -k --keepParent --norsrc "$app_path" "$archive"
(cd "$dist_dir" && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
echo "Distribution archive: ${archive}"

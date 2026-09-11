#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

build_arguments=(-c release)
if [[ -n "${SWIFT_SDK_PATH:-}" ]]; then
  mkdir -p .build/ModuleCache
  export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/ModuleCache"
  export SDKROOT="$SWIFT_SDK_PATH"
  build_arguments+=(--disable-sandbox --sdk "$SWIFT_SDK_PATH")
fi

swift build "${build_arguments[@]}"

app_dir="$project_dir/dist/PDF Quote Collector.app"
contents_dir="$app_dir/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
ditto "$project_dir/.build/release/PDFQuoteCollector" "$contents_dir/MacOS/PDFQuoteCollector"
ditto "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"


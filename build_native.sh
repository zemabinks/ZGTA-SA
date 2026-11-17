#!/bin/zsh
# Gameplay builds are optimized; --debug retains Xcode's unoptimized mode.
set -euo pipefail
project_dir="${0:A:h}"
configuration=Release
target=simulator
derived_data="$project_dir/local-only/native-build"
usage() {
  print 'Usage: zsh build_native.sh [simulator|device|all] [--debug|--release] [--derived-data PATH]'
}
while (( $# )); do
  case "$1" in
    simulator|device|all) target="$1"; shift ;;
    --debug) configuration=Debug; shift ;;
    --release) configuration=Release; shift ;;
    --derived-data)
      (( $# >= 2 )) || { usage; exit 2; }
      derived_data="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
# OWNER_MENU_SPEC_BEGIN
project_spec=project.yml
if test -f "$project_dir/local-only/menu-bundle/OwnerMenu/manifest.json"; then
  project_spec=project-owner-menu.yml
fi
# OWNER_MENU_SPEC_END
command -v xcodegen >/dev/null || { print -u2 'XcodeGen is required to regenerate the native project.'; exit 1; }
if { [[ "$target" != device ]] && ! python3 "$project_dir/native-physics/source_stamp.py" check "$project_dir/local-only/native-physics/ios-simulator"; } ||
   { [[ "$target" != simulator ]] && ! python3 "$project_dir/native-physics/source_stamp.py" check "$project_dir/local-only/native-physics/ios-device"; }; then
  zsh "$project_dir/native-physics/build.sh" all
fi
if ! python3 "$project_dir/build_samp_transport.py" --check --platform device --platform simulator; then
  command -v go >/dev/null || { print -u2 'Go 1.26.4 or newer is required for native SA-MP networking.'; exit 1; }
  python3 "$project_dir/build_samp_transport.py" --platform device --platform simulator
fi
if [[ "$target" != device ]] && ! python3 "$project_dir/build_installer_bridge.py" --check --platform simulator; then
  python3 "$project_dir/build_installer_bridge.py" --platform simulator
fi
if [[ "$target" != simulator ]] && ! python3 "$project_dir/build_installer_bridge.py" --check --platform device; then
  python3 "$project_dir/build_installer_bridge.py" --platform device
fi
if [[ "$target" != device ]] && ! python3 "$project_dir/build_native_audio.py" --check --platform simulator; then
  python3 "$project_dir/build_native_audio.py" --platform simulator
fi
if [[ "$target" != simulator ]] && ! python3 "$project_dir/build_native_audio.py" --check --platform device; then
  python3 "$project_dir/build_native_audio.py" --platform device
fi
(cd "$project_dir/ios" && xcodegen generate --spec "$project_spec")
build_platform() {
  local platform="$1" suffix="$2"
  xcodebuild -project "$project_dir/ios/ZGTASA.xcodeproj" -scheme ZGTASA -configuration "$configuration" \
    -destination "generic/platform=$platform" -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build
  print "Native $configuration bundle: $derived_data/Build/Products/$configuration-$suffix/ZGTASA.app"
}
if [[ "$target" != device ]]; then build_platform 'iOS Simulator' iphonesimulator; fi
if [[ "$target" != simulator ]]; then build_platform iOS iphoneos; fi

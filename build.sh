#!/bin/sh -e
# `./build.sh` generates dist/$VERSION.tar.gz
# `./build.sh --install` installs into ~/Library/Application Support/Power/Current

VERSION=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("package.json","utf8")).version); ""')
ROOT="/tmp/power-build.$$"
DIST="$(pwd)/dist"

cake build

mkdir -p "$ROOT/$VERSION/node_modules"
cp -R package.json bin lib "$ROOT/$VERSION"
cp Cakefile "$ROOT/$VERSION"
cd "$ROOT/$VERSION"
BUNDLE_ONLY=1 npm install --production &>/dev/null
cp `which node` bin

if [ "$1" == "--install" ]; then
  POWER_ROOT="$HOME/Library/Application Support/Power"
  rm -fr "$POWER_ROOT/Versions/9999.0.0"
  mkdir -p "$POWER_ROOT/Versions"
  cp -R "$ROOT/$VERSION" "$POWER_ROOT/Versions/9999.0.0"
  rm -f "$POWER_ROOT/Current"
  cd "$POWER_ROOT"
  ln -s Versions/9999.0.0 Current
  echo "$POWER_ROOT/Versions/9999.0.0"
else
  cd "$ROOT"
  tar czf "$VERSION.tar.gz" "$VERSION"
  mkdir -p "$DIST"
  cd "$DIST"
  mv "$ROOT/$VERSION.tar.gz" "$DIST/power_$VERSION.tar.gz"
  echo "$DIST/power_$VERSION.tar.gz"
fi

rm -fr "$ROOT"

#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
gcp_dir=$(dirname -- "$script_dir")
repo_dir=$(dirname -- "$gcp_dir")
source_dir="$repo_dir/frontend/out"
staging_dir="$gcp_dir/.firebase-hosting"

if [ ! -f "$source_dir/index.html" ]; then
  echo "frontend/out is missing. Build the production static export before deploying." >&2
  exit 1
fi

rm -rf -- "$staging_dir"
mkdir -p -- "$staging_dir"
cp -R -- "$source_dir"/. "$staging_dir"/

echo "Staged frontend/out for Firebase Hosting."

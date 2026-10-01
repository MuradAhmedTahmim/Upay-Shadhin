#!/usr/bin/env bash
# Publish the API to a Hugging Face Space.
#
# The Space needs the Dockerfile and its own README (with the HF front matter) at the
# repository ROOT, while in this project they live under deploy/space/. So rather than
# reshaping the project to suit the host, this script assembles the Space's tree in a
# temporary directory and pushes that — the same approach used for the gh-pages build.
#
# Only source is sent. The dataset and models are built inside the image.
#
# Usage:
#   HF_USER=<your-username> HF_TOKEN=<hf_...> ./deploy/space/push.sh [space-name]
#
# The token needs **write** access and is read from the environment only — it is never
# written to a file, and never committed.

set -euo pipefail

SPACE_NAME="${1:-upay-shadhin-api}"
: "${HF_USER:?set HF_USER to your Hugging Face username}"
: "${HF_TOKEN:?set HF_TOKEN to a Hugging Face token with write access}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "assembling Space tree in $TMP"
cp "$ROOT/deploy/space/Dockerfile" "$TMP/Dockerfile"
cp "$ROOT/deploy/space/README.md"  "$TMP/README.md"
cp "$ROOT/requirements.txt"        "$TMP/requirements.txt"

for pkg in data ml rules nlg api; do
  mkdir -p "$TMP/$pkg"
  # Source only. Generated CSVs, model artifacts and caches are rebuilt in the image.
  find "$ROOT/$pkg" -maxdepth 1 -type f \( -name '*.py' -o -name '*.md' \) \
    -exec cp {} "$TMP/$pkg/" \;
done

echo "files to publish:"
(cd "$TMP" && find . -type f | sort | sed 's/^/  /')

cd "$TMP"
git init -q -b main
git add -A
git -c user.name="$HF_USER" -c user.email="$HF_USER@users.noreply.huggingface.co" \
    commit -q -m "Deploy upay Shadhin API

Synthetic data only. The dataset and models are generated during the image
build from a fixed seed, so the running service matches this commit."

REMOTE="https://${HF_USER}:${HF_TOKEN}@huggingface.co/spaces/${HF_USER}/${SPACE_NAME}"
echo "pushing to https://huggingface.co/spaces/${HF_USER}/${SPACE_NAME}"
git push -q --force "$REMOTE" main

cat <<EOF

Pushed. The Space will build (about 4-6 minutes: install, generate data, train, evaluate).

  Space : https://huggingface.co/spaces/${HF_USER}/${SPACE_NAME}
  API   : https://${HF_USER}-${SPACE_NAME}.hf.space
  Docs  : https://${HF_USER}-${SPACE_NAME}.hf.space/docs

Then rebuild the web app so it calls the hosted API instead of localhost:

  cd app
  flutter build web --release --base-href /Upay-Shadhin/ \\
    --dart-define=SHADHIN_API_BASE_URL=https://${HF_USER}-${SPACE_NAME}.hf.space

and publish build/web to the gh-pages branch.
EOF

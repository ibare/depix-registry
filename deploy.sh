#!/bin/bash
# depix-registry deploy script
# Usage: ./deploy.sh [tag]
# Example: ./deploy.sh v0.4.0
#
# What it does:
# 1. Validates JSON files
# 2. Updates registry.json URLs to the new tag
# 3. Commits + tags + pushes
# 4. Purges jsDelivr CDN cache

set -euo pipefail
cd "$(dirname "$0")"

# --- Tag ---
if [ -z "${1:-}" ]; then
  # Auto-increment: find latest vX.Y.Z tag, bump patch
  LATEST=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
  if [ -z "$LATEST" ]; then
    TAG="v0.1.0"
  else
    IFS='.' read -r MAJOR MINOR PATCH <<< "${LATEST#v}"
    TAG="v${MAJOR}.${MINOR}.$((PATCH + 1))"
  fi
else
  TAG="$1"
fi

echo "==> Deploying as $TAG"

# --- Validate JSON ---
echo "==> Validating JSON..."
for f in packs/*.json registry.json; do
  python3 -c "import json; json.load(open('$f'))" || { echo "INVALID: $f"; exit 1; }
done

PACK_COUNT=$(python3 -c "
import json, glob
total = sum(len(json.load(open(f))) for f in glob.glob('packs/*.json'))
print(total)
")
echo "    $PACK_COUNT shapes across $(ls packs/*.json | wc -l | tr -d ' ') packs"

# --- Update registry.json URLs ---
echo "==> Updating registry.json URLs to $TAG..."
python3 -c "
import json, re
with open('registry.json') as f:
    data = json.load(f)
for pack in data['packs']:
    pack['url'] = re.sub(r'@v[\d.]+/', '@${TAG}/', pack['url'])
with open('registry.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

# --- Git commit + tag + push ---
echo "==> Committing and pushing..."
git add -A
git commit -m "release: ${TAG}" --allow-empty
git tag "$TAG"
git push
git push origin "$TAG"

# --- Purge jsDelivr cache ---
echo "==> Purging jsDelivr cache..."
BASE="https://purge.jsdelivr.net/gh/ibare/depix-registry@${TAG}"

curl -s "${BASE}/registry.json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  registry.json: {d.get(\"status\",\"?\")}')" 2>/dev/null || echo "  registry.json: purge sent"

for f in packs/*.json; do
  NAME=$(basename "$f")
  curl -s "${BASE}/packs/${NAME}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  packs/${NAME}: {d.get(\"status\",\"?\")}')" 2>/dev/null || echo "  packs/${NAME}: purge sent"
done

echo ""
echo "==> Done! Deployed $TAG ($PACK_COUNT shapes)"
echo "    Registry: https://cdn.jsdelivr.net/gh/ibare/depix-registry@${TAG}/registry.json"
echo ""
echo "    To use in depix, update DEFAULT_REGISTRY_URL to @${TAG}"

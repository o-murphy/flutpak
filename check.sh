#!/usr/bin/env bash
# check-actions.sh — знаходить застарілі GitHub Actions БЕЗ використання закешованого пошуку коду

set -euo pipefail

OWNER="${1:-$(gh api user --jq '.login')}"

# Асоціативний масив для перевірки застарілих версій
declare -A UPGRADES=(
  ["actions/checkout@v2"]="→ @v6"
  ["actions/checkout@v3"]="→ @v6"
  ["actions/checkout@v4"]="→ @v6"
  ["actions/checkout@v5"]="→ @v6"
  ["actions/cache@v2"]="→ @v5"
  ["actions/cache@v3"]="→ @v5"
  ["actions/cache@v4"]="→ @v5"
  ["actions/upload-artifact@v2"]="→ @v7"
  ["actions/upload-artifact@v3"]="→ @v7"
  ["actions/upload-artifact@v4"]="→ @v7"
  ["actions/upload-artifact@v5"]="→ @v7"
  ["actions/upload-artifact@v6"]="→ @v7"
  ["actions/download-artifact@v2"]="→ @v8"
  ["actions/download-artifact@v3"]="→ @v8"
  ["actions/download-artifact@v4"]="→ @v8"
  ["actions/download-artifact@v5"]="→ @v8"
  ["actions/download-artifact@v6"]="→ @v8"
  ["actions/download-artifact@v7"]="→ @v8"
  ["actions/github-script@v5"]="→ @v8"
  ["actions/github-script@v6"]="→ @v8"
  ["actions/github-script@v7"]="→ @v8"
  ["actions/setup-node@v1"]="→ @v4"
  ["actions/setup-node@v2"]="→ @v4"
  ["actions/setup-node@v3"]="→ @v4"
  ["actions/setup-python@v1"]="→ @v5"
  ["actions/setup-python@v2"]="→ @v5"
  ["actions/setup-python@v3"]="→ @v5"
  ["actions/setup-python@v4"]="→ @v6"
  ["actions/setup-python@v5"]="→ @v6"
  ["actions/setup-java@v3"]="→ @v5"
  ["softprops/action-gh-release@v1"]="→ @v3"
  ["softprops/action-gh-release@v2"]="→ @v3"
  ["dorny/paths-filter@v3"]="→ @v4"
  ["astral-sh/setup-uv@v6"]="→ @08807647e7069bb48b6ef5acd8ec9567f424441b"
  ["actions/setup-go@v5"]="→ @v6"
  ["upload-release-asset"]="→ ARCHIVED!"
)

echo "🔍 Отримуємо актуальний список репозиторіїв для: $OWNER..."

# Використовуємо --source (не форки) та --no-archived (виключаємо архівні)
repos=$(gh repo list "$OWNER" --limit 300 --source --no-archived --json nameWithOwner --jq '.[].nameWithOwner')

if [[ -z "$repos" ]]; then
  echo "Репозиторіїв не знайдено."
  exit 0
fi

echo "🚀 Скануємо workflows в реальному часі (без кешу)..."
echo ""

found_any=0

# Тимчасовий файл для завантаження workflow
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

for repo in $repos; do
  # Отримуємо список файлів у .github/workflows напряму з API
  workflows=$(gh api "repos/$repo/contents/.github/workflows" --jq '.[].path' 2>/dev/null || true)

  if [[ -z "$workflows" ]]; then
    continue
  fi

  # Перевіряємо кожен знайдений файл конфігурації
  for wf_path in $workflows; do
    # Перевіряємо тільки файли .yml або .yaml
    if [[ "$wf_path" != *.yml && "$wf_path" != *.yaml ]]; then
      continue
    fi

    # Завантажуємо «сирий» вміст файлу (завжди найсвіжіший з main/master)
    if gh api "repos/$repo/contents/$wf_path" --jq '.content' | base64 -d > "$tmp_file" 2>/dev/null; then

      # Перевіряємо файл на наявність наших застарілих патернів
      for pattern in "${!UPGRADES[@]}"; do
        # Шукаємо точний збіг рядка (наприклад, "uses: actions/checkout@v3")
        if grep -q -F "$pattern" "$tmp_file"; then
          upgrade="${UPGRADES[$pattern]}"
          echo "⚠  Знайдено застарілий action: $pattern $upgrade"
          echo "   $repo  →  $wf_path"
          echo ""
          found_any=1
        fi
      done
    fi
  done
done

echo "---------------------------------------"
if [[ $found_any -eq 0 ]]; then
  echo "✅ Все актуально! Реальних застарілих actions не знайдено."
fi
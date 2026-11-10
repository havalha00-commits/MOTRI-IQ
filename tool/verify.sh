#!/usr/bin/env bash
# Work around Flutter tooling failures with non-ASCII paths and parentheses.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
validation_dir="$(mktemp -d /tmp/motriiq-check.XXXXXX)"
echo "Validation copy: $validation_dir"
for item in lib test integration_test tool assets pubspec.yaml pubspec.lock analysis_options.yaml; do
  rsync -a "$project_root/$item" "$validation_dir/" \
    --exclude '*.backup*' --exclude 'main_backup*.dart' \
    --exclude main_fixed.dart --exclude 'tmp_img_*.dart'
done
cd "$validation_dir"
flutter pub get
flutter analyze
flutter test

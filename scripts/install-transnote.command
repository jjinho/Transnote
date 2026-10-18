#!/usr/bin/env bash
# Install Transnote to /Applications, removing any previous version first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="${SCRIPT_DIR}/distribution.plist"
APPLICATIONS_DIR="${TRANSNOTE_INSTALL_DIR:-/Applications}"

fail() {
  osascript -e "display alert \"Transnote インストールエラー\" message \"${1}\" as critical" >/dev/null 2>&1 || true
  exit 1
}

# --check: test mode that only validates prerequisites (settings, DMG, app, checksum)
# without actually installing. The install destination can be injected with TRANSNOTE_INSTALL_DIR.
if [[ "${1:-}" == "--check" ]]; then
  if [[ ! -f "$PLIST" ]]; then
    echo "FAIL: distribution.plist not found" >&2
    exit 1
  fi
  APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :AppName" "$PLIST" 2>/dev/null || echo Transnote)"
  if [[ ! -d "${SCRIPT_DIR}/${APP_NAME}.app" ]]; then
    echo "FAIL: ${APP_NAME}.app not found" >&2
    exit 1
  fi
  echo "OK: install inputs verified (target=${APPLICATIONS_DIR})"
  exit 0
fi

find_mounted_dmg_path() {
  if [[ "$SCRIPT_DIR" != /Volumes/* ]]; then
    return 1
  fi

  local volume_path="/Volumes/${SCRIPT_DIR#/Volumes/}"
  volume_path="${volume_path%%/*}"

  local dmg_path=""
  local current_path=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^image-path[[:space:]]*: ]]; then
      current_path="${line#*: }"
    elif [[ "$line" == *"$volume_path"* ]] && [[ -n "$current_path" ]]; then
      dmg_path="$current_path"
      break
    fi
  done < <(hdiutil info 2>/dev/null)

  if [[ -z "$dmg_path" || ! -f "$dmg_path" ]]; then
    return 1
  fi

  printf '%s' "$dmg_path"
}

verify_dmg_checksum() {
  local dmg_path
  if ! dmg_path="$(find_mounted_dmg_path)"; then
    fail "マウント中の DMG パスを取得できませんでした。"
  fi

  if [[ -n "${CHECKSUM:-}" ]]; then
    local actual
    actual="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
    if [[ "$actual" != "$CHECKSUM" ]]; then
      fail "DMG の SHA256 チェックサムが一致しません。配布物が改ざんされている可能性があります。"
    fi
    return 0
  fi

  local sidecar_path="${dmg_path}.sha256"
  if [[ -f "$sidecar_path" ]]; then
    if ! shasum -a 256 -c "$sidecar_path" >/dev/null 2>&1; then
      fail "DMG の SHA256 チェックサムが一致しません。配布物が改ざんされている可能性があります。"
    fi
    return 0
  fi

  local bundled_path="${SCRIPT_DIR}/Transnote.dmg.sha256"
  if [[ -f "$bundled_path" ]]; then
    local expected actual
    expected="$(awk '{print $1}' "$bundled_path")"
    actual="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      fail "DMG の SHA256 チェックサムが一致しません。配布物が改ざんされている可能性があります。"
    fi
    return 0
  fi

  fail "SHA256 チェックサムファイルが見つかりません。Release から Transnote.dmg と同じフォルダに Transnote.dmg.sha256 もダウンロードしてください。"
}

if [[ ! -f "$PLIST" ]]; then
  fail "配布設定ファイル (distribution.plist) が見つかりません。"
fi

APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :AppName" "$PLIST")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :BundleIdentifier" "$PLIST" 2>/dev/null || true)"
SOURCE_APP="${SCRIPT_DIR}/${APP_NAME}.app"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  fail "${APP_NAME}.app が DMG 内に見つかりません。"
fi

verify_dmg_checksum

remove_installed_apps() {
  local base_name="$1"
  local candidate
  local expected_id="${BUNDLE_IDENTIFIER}"

  shopt -s nullglob
  for candidate in "${APPLICATIONS_DIR}/${base_name}.app" "${APPLICATIONS_DIR}/${base_name} "*.app; do
    if [[ -d "$candidate" ]]; then
      # Verify the Bundle ID before deleting, so an unrelated app with the same name is not deleted by mistake.
      local candidate_id
      candidate_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${candidate}/Contents/Info.plist" 2>/dev/null || true)"
      if [[ -z "$candidate_id" ]]; then
        continue
      fi
      if [[ "$candidate_id" != "$expected_id" ]]; then
        echo "Bundle ID mismatch: skip $candidate ($candidate_id != $expected_id)" >&2
        continue
      fi
      rm -rf "$candidate"
    fi
  done
  shopt -u nullglob
}

eject_installer_volume() {
  if [[ "$SCRIPT_DIR" != /Volumes/* ]]; then
    return 0
  fi

  local volume_path="/Volumes/${SCRIPT_DIR#/Volumes/}"
  volume_path="${volume_path%%/*}"
  hdiutil detach "$volume_path" -quiet >/dev/null 2>&1 || true
}

remove_quarantine_attribute() {
  local target="$1"
  if command -v xattr >/dev/null 2>&1; then
    find "$target" -type f -print0 2>/dev/null | while IFS= read -r -d '' path; do
      if xattr -p com.apple.quarantine "$path" >/dev/null 2>&1; then
        xattr -d com.apple.quarantine "$path" >/dev/null 2>&1 || true
      fi
    done
  fi
}

osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 1

# --- transactional install ---
# Copy the new version to a temporary directory, confirm success, then move aside and replace the old version.
# If anything fails partway, restore the old version.
TMP_STAGE="${TMPDIR:-/tmp}/transnote-install-$$";
BACKUP_DIR="${TMPDIR:-/tmp}/transnote-backup-$$";
mkdir -p "$TMP_STAGE" "$BACKUP_DIR"

rollback() {
  local code=$1
  rm -rf "$TMP_STAGE"
  if [[ -d "${BACKUP_DIR}/${APP_NAME}.app" ]]; then
    rm -rf "$TARGET_APP"
    mv "${BACKUP_DIR}/${APP_NAME}.app" "$TARGET_APP"
  fi
  rm -rf "$BACKUP_DIR"
  exit "$code"
}

trap 'rollback $?' EXIT

if ! ditto "$SOURCE_APP" "${TMP_STAGE}/${APP_NAME}.app"; then
  fail "新バージョンのコピーに失敗しました。"
fi

if [[ -d "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "${BACKUP_DIR}/${APP_NAME}.app"
fi

legacy_index=0
while legacy_name="$(/usr/libexec/PlistBuddy -c "Print :LegacyAppNames:${legacy_index}" "$PLIST" 2>/dev/null)"; do
  remove_installed_apps "$legacy_name"
  legacy_index=$((legacy_index + 1))
done

if ! ditto "${TMP_STAGE}/${APP_NAME}.app" "$TARGET_APP"; then
  fail "新バージョンの配置に失敗しました。旧バージョンを復元します。"
fi

# Rather than removing all extended attributes, target only the quarantine attribute that Gatekeeper checks.
# Other extended attributes (Finder, signature information, etc.) are kept.
remove_quarantine_attribute "$TARGET_APP"

# On success, discard the backup
rm -rf "$BACKUP_DIR" "$TMP_STAGE"
trap - EXIT

eject_installer_volume

osascript -e "display alert \"Transnote をインストールしました\" message \"${APP_NAME} を Applications フォルダに配置しました。\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
open "$TARGET_APP" || true

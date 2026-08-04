#!/usr/bin/env bash
# Release to TestFlight: bump build number, build the signed IPA, upload.
#
# Credentials — either of:
#   ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH   App Store Connect API key (.p8)
#   keychain item AC_PASSWORD                    app-specific password for
#                                                dev@basecode.al, stored via:
#     security add-generic-password -a dev@basecode.al -s AC_PASSWORD -w <pw>
set -euo pipefail
cd "$(dirname "$0")"

# Fail early if no upload credential is configured.
have_key() { [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; }
have_pw() { security find-generic-password -s AC_PASSWORD >/dev/null 2>&1; }
if ! have_key && ! have_pw; then
  echo "no upload credential: set ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH," >&2
  echo "or store an app-specific password in the keychain as AC_PASSWORD." >&2
  exit 1
fi

# Bump the +N build number in pubspec.yaml.
ver=$(grep '^version:' pubspec.yaml | awk '{print $2}')
base=${ver%+*}; build=${ver#*+}; next=$((build + 1))
sed -i '' "s/^version: .*/version: ${base}+${next}/" pubspec.yaml
echo "building ${base}+${next}"

flutter build ipa --release --export-method app-store

ipa=(build/ios/ipa/*.ipa)
if have_key; then
  mkdir -p ~/.appstoreconnect/private_keys
  cp -n "${ASC_KEY_PATH}" ~/.appstoreconnect/private_keys/"AuthKey_${ASC_KEY_ID}.p8" 2>/dev/null || true
  xcrun altool --upload-app --type ios -f "${ipa[0]}" \
    --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}"
else
  xcrun altool --upload-app --type ios -f "${ipa[0]}" \
    -u dev@basecode.al -p "@keychain:AC_PASSWORD"
fi

git add pubspec.yaml && git commit -m "release: build ${base}+${next}"
echo "uploaded ✓ — App Store Connect → TestFlight (processing takes ~10 min)"

#!/usr/bin/env bash
# Ajustes de Android que Ergos necesita. Ejecutar dentro de app/ después de:
#   flutter create . --platforms=android,windows
set -euo pipefail
M=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.CAMERA' "$M"; then
  python3 - "$M" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
perms='''    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <uses-permission android:name="android.permission.INTERNET"/>
'''
s=s.replace('<application',perms+'    <application',1)
open(p,'w').write(s)
PY
fi
# minSdk 24 (SQLCipher / biometría)
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i -E 's/minSdk(Version)? *=? *flutter\.minSdkVersion/minSdk = 24/' "$f" || true
done
# local_auth necesita FlutterFragmentActivity
K=$(find android/app/src/main -name MainActivity.kt | head -1)
sed -i 's/FlutterActivity/FlutterFragmentActivity/g' "$K"
echo "Android listo."

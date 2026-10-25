#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

RID="${1:-osx-$(uname -m | sed 's/x86_64/x64/')}"
FILEE="vendor/Filee"
OUT="build/engine-$RID"

case "$RID" in
    osx-arm64|osx-x64) ;;
    *) echo "Desteklenmeyen hedef: $RID (osx-arm64 ya da osx-x64)"; exit 1 ;;
esac

[ -f "$FILEE/src/Filee.Cli/Filee.Cli.csproj" ] || {
    echo "Filee submodule eksik. Önce: git submodule update --init"
    exit 1
}
command -v dotnet >/dev/null 2>&1 || { echo "dotnet bulunamadı (.NET 10 SDK gerekli)"; exit 1; }
command -v pwsh >/dev/null 2>&1 || { echo "pwsh bulunamadı (PowerShell gerekli)"; exit 1; }

echo "▸ Filee CLI derleniyor ($RID)"
rm -rf "$OUT"
mkdir -p "$OUT/cli" "$OUT/licenses"
dotnet publish "$FILEE/src/Filee.Cli/Filee.Cli.csproj" \
    -c Release -r "$RID" --self-contained true \
    -p:PublishReadyToRun=false \
    -o "$OUT/cli"

echo "▸ Yerleşik motorlar indiriliyor (rhwp, 7-Zip)"
pwsh -NoProfile "$FILEE/build/fetch-portable-engines.ps1" -Runtime "$RID" -Destination "$OUT/cli/engines"

chmod +x "$OUT/cli/filee-cli"
cp "$FILEE/LICENSE" "$OUT/licenses/Filee-LICENSE.txt"
cp "$FILEE/THIRD-PARTY-NOTICES.md" "$OUT/licenses/Filee-THIRD-PARTY-NOTICES.md"

HOST="osx-$(uname -m | sed 's/x86_64/x64/')"
if [ "$RID" = "$HOST" ]; then
    "$OUT/cli/filee-cli" version
fi
echo "✓ $OUT/cli"

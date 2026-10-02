#!/usr/bin/env bash
# Integration of real wrappers with harmless delegates; Linux only.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture="$root/data/test-u1/shell-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$fixture/source space 中文/tools" "$fixture/source space 中文/host" "$fixture/source space 中文/sdk/roomkit/shared" "$fixture/source space 中文/examples/framework"
f="$fixture/source space 中文"
cp "$root/RoomKit.sh" "$f/"
cp "$root/tools/roomkit.ps1" "$root/tools/roomkit_entry.ps1" "$root/tools/runtime_paths.sh" "$root/tools/roomkit_status.ps1" "$f/tools/"
for file in project.godot host/operator.gd host/managed_host.gd sdk/roomkit/shared/json_wire.gd examples/framework/services.json tools/build_framework.ps1 tools/prepare_environment.sh; do : > "$f/$file"; done
cat > "$f/tools/roomkit_linux.sh" <<'STUB'
#!/usr/bin/env bash
printf 'DELEGATE'; printf ' <%s>' "$@"; printf '\n'
exit 17
STUB
passed=0
expect() {
  local code="$1" pattern="$2";shift 2
  set +e
  output=$("$@" 2>&1); rc=$?
  set -e
  if [ "$rc" -ne "$code" ] || ! grep -q -- "$pattern" <<< "$output"; then printf 'FAIL exit=%s expected=%s output=%s\n' "$rc" "$code" "$output"; exit 1; fi
  passed=$((passed+1));printf 'PASS expected_exit=%s %s\n' "$code" "$pattern"
}
cd "$fixture"
expect 17 'DELEGATE <start> <--instance> <test-u1> <--panel-port> <29191>' bash "$f/RoomKit.sh" start --instance test-u1 --panel-port 29191
expect 17 'DELEGATE <stop>' bash "$f/RoomKit.sh" stop
expect 17 'DELEGATE <status>' bash "$f/RoomKit.sh" status
expect 2 'Duplicate option' bash "$f/RoomKit.sh" start --instance x --instance y
expect 2 'pwsh missing' env ROOMKIT_PWSH=/nonexistent/pwsh bash "$f/RoomKit.sh" help
mkdir "$fixture/fakebin"
printf '#!/usr/bin/env bash\necho Darwin\n' > "$fixture/fakebin/uname"
chmod 700 "$fixture/fakebin/uname"
expect 2 'supported platforms' env PATH="$fixture/fakebin:$PATH" bash "$f/RoomKit.sh" help
ln -s "$f" "$fixture/linked"
expect 2 'linked installation' bash "$fixture/linked/RoomKit.sh" status
# Read-only Windows status with CIM substitutes. Real adapter script, no engine.
mkdir "$fixture/status"
cat > "$fixture/probe.ps1" <<'PS'
param([string]$Adapter,[string]$Data,[string]$State)
function Get-CimInstance {if($State -eq 'live'){[pscustomobject]@{ProcessId=123}}elseif($State -eq 'denied'){throw 'access denied'}}
& $Adapter -DataRoot $Data
exit $LASTEXITCODE
PS
expect 0 'ROOMKIT_NOT_RUNNING' "$ROOMKIT_PWSH" -NoProfile -File "$fixture/probe.ps1" "$f/tools/roomkit_status.ps1" "$fixture/status" absent
printf '{"pid":123,"port":29191}' > "$fixture/status/operator.json"
before=$(sha256sum "$fixture/status/operator.json")
expect 3 'ROOMKIT_STALE' "$ROOMKIT_PWSH" -NoProfile -File "$fixture/probe.ps1" "$f/tools/roomkit_status.ps1" "$fixture/status" absent
expect 3 'ROOMKIT_UNKNOWN reason=legacy_identity_incomplete' "$ROOMKIT_PWSH" -NoProfile -File "$fixture/probe.ps1" "$f/tools/roomkit_status.ps1" "$fixture/status" live
expect 3 'ROOMKIT_UNKNOWN reason=identity_unavailable' "$ROOMKIT_PWSH" -NoProfile -File "$fixture/probe.ps1" "$f/tools/roomkit_status.ps1" "$fixture/status" denied
[ "$before" = "$(sha256sum "$fixture/status/operator.json")" ]
[ "$(find "$fixture/status" -type f | wc -l)" -eq 1 ]
passed=$((passed+1))
printf 'PASS status retained descriptor and wrote no signal\n'
printf 'UNIFIED_SHELL_TESTS passed=%s failed=0 Windows=mock-CIM-only\n' "$passed"

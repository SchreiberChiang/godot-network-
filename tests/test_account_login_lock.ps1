param([string]$Source = (Split-Path $PSScriptRoot -Parent))
# Deterministic, real SQLite tests of login's credential snapshot boundary.
# No Godot or service is started. A copied account helper pauses AFTER the real
# PBKDF2 verification and BEFORE CheckPassword returns. On old code that point
# holds the write transaction; on new code it must not. The parent's single
# connection waits only 300 ms for a write lock, not the production 10 seconds.
# All users and databases are fake, under a fresh private project data directory.
# Requests (including passwords) use stdin only. Never save raw helper output:
# successful responses contain bearer tokens. Evidence contains fixed labels,
# counts, codes and timings only.
$ErrorActionPreference = 'Stop'
$Source = [IO.Path]::GetFullPath($Source).TrimEnd('/', '\')
if (-not [IO.File]::Exists((Join-Path $Source 'project.godot'))) { throw 'Source must be the RoomKit project root.' }
. (Join-Path $Source 'tests/support/portable.ps1')
$utf8 = New-Object Text.UTF8Encoding($false)
$script:passed = 0; $script:failed = 0; $script:records = @()
$connection = $null; $active = $null; $gateRelease = ''
$root = Join-Path (Join-Path $Source 'data') ('test-account-login-lock-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $root) { throw 'Fresh evidence directory required.' }
Rk-ProtectData $Source $root
foreach ($folder in 'tools', 'gates', 'logs') { [void][IO.Directory]::CreateDirectory((Join-Path $root $folder)) }
$database = Join-Path $root 'accounts.sqlite'
$sourceAccount = Join-Path $Source 'tools/account_store.ps1'
$sourceSqlite = Join-Path $Source 'tools/sqlite_store.ps1'
$beforeAccount = (Get-FileHash -LiteralPath $sourceAccount -Algorithm SHA256).Hash
$beforeSqlite = (Get-FileHash -LiteralPath $sourceSqlite -Algorithm SHA256).Hash
$accountText = [IO.File]::ReadAllText($sourceAccount)
$sqliteText = [IO.File]::ReadAllText($sourceSqlite)
$copiedAccount = Join-Path $root 'tools/account_store.ps1'
[IO.File]::WriteAllText((Join-Path $root 'tools/sqlite_store.ps1'), $sqliteText, $utf8)
$binding = [regex]::Match($sqliteText, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
$passwordType = [regex]::Matches($accountText, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@") | Where-Object { $_.Groups[1].Value.Contains('RoomKitPasswords') } | Select-Object -First 1
if (-not $binding.Success -or $null -eq $passwordType) { throw 'Production binding/type could not be identified.' }
Add-Type -TypeDefinition $binding.Groups[1].Value
Add-Type -TypeDefinition $passwordType.Groups[1].Value
$verificationLine = 'return [RoomKitPasswords]::Verify($Password,$Row[''salt''],[int]$Row[''iterations''],$Row[''password_hash''])'
if ([regex]::Matches($accountText, [regex]::Escape($verificationLine)).Count -ne 1) { throw 'Exactly one production verification return was expected.' }
function Check([bool]$Condition, [string]$Label) {
    if ($Condition) { $script:passed++; Write-Output ('PASS ' + $Label) }
    else { $script:failed++; Write-Output ('FAIL ' + $Label) }
}
function Q([string]$Sql, [string[]]$Values = @()) { return ,($connection.Query($Sql, $Values)) }
function Scalar([string]$Sql, [string[]]$Values = @()) {
    $rows = Q $Sql $Values
    if (-not $rows.Count) { return -1 }
    return [long]$rows[0]['n']
}
function StartAccount($Request) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Rk-PowerShell
    $arguments = @('-NoProfile', '-NonInteractive')
    if (-not $script:RkPosix) { $arguments += @('-ExecutionPolicy', 'Bypass') }
    $arguments += @('-File', $copiedAccount, '-Database', $database)
    if ($script:RkPosix) { foreach ($argument in $arguments) { $info.ArgumentList.Add([string]$argument) } }
    else {
        $quoted = foreach ($argument in $arguments) { '"' + ([string]$argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
        $info.Arguments = $quoted -join ' '
        try { [Console]::InputEncoding = $utf8 } catch { }
    }
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    if (-not $script:RkPosix) { $null = $process.Handle }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $json = ConvertTo-Json -InputObject $Request -Depth 8 -Compress
    $process.StandardInput.WriteLine([Convert]::ToBase64String($utf8.GetBytes($json)))
    $process.StandardInput.Close()
    return [pscustomobject]@{process = $process; stdout = $stdout; stderr = $stderr}
}
function CompleteAccount($Child) {
    if (-not $Child.process.WaitForExit(45000)) {
        $Child.process.Kill(); [void]$Child.process.WaitForExit(5000)
        return [pscustomobject]@{ok = $false; code = 'DRIVER_TIMEOUT'; clean = $false}
    }
    $text = $Child.stdout.Result.Trim()
    $clean = $Child.process.ExitCode -eq 0 -and [string]::IsNullOrEmpty($Child.stderr.Result)
    if ($text.Length -eq 0 -or -not $text.StartsWith('{')) { return [pscustomobject]@{ok = $false; code = 'DRIVER_NO_JSON'; clean = $false} }
    try {
        $reply = ConvertFrom-Json -InputObject $text
        $reply | Add-Member -NotePropertyName clean -NotePropertyValue $clean
        return $reply
    } catch { return [pscustomobject]@{ok = $false; code = 'DRIVER_BAD_JSON'; clean = $false} }
}
function InstallGate([string]$Label) {
    $script:gateReady = Join-Path $root ('gates/' + $Label + '.ready')
    $script:gateRelease = Join-Path $root ('gates/' + $Label + '.release')
    # Keep the injected source ASCII. PowerShell 5.1 can misread a UTF-8 script
    # without BOM when the absolute project path contains Chinese characters.
    $ready64 = [Convert]::ToBase64String($utf8.GetBytes($script:gateReady))
    $release64 = [Convert]::ToBase64String($utf8.GetBytes($script:gateRelease))
    $lines = @(
        '$verified = [RoomKitPasswords]::Verify($Password,$Row[''salt''],[int]$Row[''iterations''],$Row[''password_hash''])',
        ('$gateReadyPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''' + $ready64 + '''))'),
        ('$gateReleasePath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''' + $release64 + '''))'),
        '[IO.File]::WriteAllText($gateReadyPath,''ready'')',
        '$gateClock = [Diagnostics.Stopwatch]::StartNew()',
        'while (-not [IO.File]::Exists($gateReleasePath)) {',
        '    if ($gateClock.ElapsedMilliseconds -ge 30000) { throw ''TEST_GATE_TIMEOUT'' }',
        '    Start-Sleep -Milliseconds 10',
        '}',
        'return $verified'
    )
    # String.Replace preserves literal $ characters. Do not use regex replacement.
    [IO.File]::WriteAllText($copiedAccount, $accountText.Replace($verificationLine, ($lines -join "`n")), $utf8)
}
function InsertAccount([string]$Id, [string]$Name, [string]$Display) {
    [void](Q 'INSERT INTO accounts (user_id,username,display_name,role,algorithm,iterations,salt,password_hash,created_at) VALUES (?,?,?,''player'',''pbkdf2-sha256'',600000,?,?,?)' @($Id, $Name, $Display, $oldSalt, $oldHash, [string]$now))
}
Write-Output ('ACCOUNT_LOGIN_LOCK_EVIDENCE=' + $root)
try {
    # Initialization uses the unmodified helper. No password is needed for init.
    [IO.File]::WriteAllText($copiedAccount, $accountText, $utf8)
    $active = StartAccount @{op = 'init'}
    $init = CompleteAccount $active
    Check ($init.ok -and $init.clean) 'production helper initializes the fake database'
    $active.process.Dispose(); $active = $null
    if (-not $init.ok -or -not $init.clean) { throw 'Initialization failed.' }
    $connection = New-Object RoomKitSqlite($database)
    # This affects only the fixture parent's connection, not production requests.
    [void](Q 'PRAGMA busy_timeout=300')
    $oldPassword = 'Fixture!' + [Guid]::NewGuid().ToString('N')
    $newPassword = 'Changed!' + [Guid]::NewGuid().ToString('N')
    $oldSalt = [RoomKitPasswords]::Salt(); $newSalt = [RoomKitPasswords]::Salt()
    $oldHash = [RoomKitPasswords]::Derive($oldPassword, $oldSalt, 600000)
    $newHash = [RoomKitPasswords]::Derive($newPassword, $newSalt, 600000)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cases = @(
        @{label = 'fresh_identity'; expected = ''; mutate = 'rename'},
        @{label = 'password_changed'; expected = 'AUTH_FAILED'; mutate = 'password'},
        @{label = 'ban_during_verify'; expected = 'ACCOUNT_BANNED'; mutate = 'ban'},
        @{label = 'username_rate_recheck'; expected = 'RATE_LIMITED'; mutate = 'user_rate'},
        @{label = 'ip_rate_recheck'; expected = 'RATE_LIMITED'; mutate = 'ip_rate'},
        @{label = 'deleted_during_verify'; expected = 'AUTH_FAILED'; mutate = 'delete'},
        @{label = 'same_username_new_identity'; expected = 'AUTH_FAILED'; mutate = 'replace'},
        @{label = 'credential_format_changed'; expected = 'AUTH_FAILED'; mutate = 'format'}
    )
    for ($index = 0; $index -lt $cases.Count; $index++) {
        $case = $cases[$index]
        $id = 'fixture_' + [Guid]::NewGuid().ToString('N')
        $replacementId = 'replacement_' + [Guid]::NewGuid().ToString('N')
        $username = 'lockcase_' + $index
        $ip = '192.0.2.' + (20 + $index)
        $userKey = 'user:' + [RoomKitPasswords]::Digest($username)
        $ipKey = 'ip:' + [RoomKitPasswords]::Digest($ip)
        [void](Q 'DELETE FROM rate_limits')
        InsertAccount $id $username 'Before verification'
        InstallGate $case.label
        $active = StartAccount @{op = 'account.login'; username = $username; password = $oldPassword; client_ip = $ip}
        $readyClock = [Diagnostics.Stopwatch]::StartNew()
        while (-not [IO.File]::Exists($script:gateReady) -and -not $active.process.HasExited -and $readyClock.ElapsedMilliseconds -lt 60000) { Start-Sleep -Milliseconds 20 }
        $ready = [IO.File]::Exists($script:gateReady)
        Check $ready ($case.label + ': real password verification reaches the finite barrier')
        $mutated = $false; $inTransaction = $false; $mutationCode = ''; $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
            if (-not $ready) { throw 'BARRIER_NOT_REACHED' }
            [void](Q 'BEGIN IMMEDIATE'); $inTransaction = $true
            switch ($case.mutate) {
                'rename' { [void](Q 'UPDATE accounts SET display_name=? WHERE user_id=?' @('After verification', $id)) }
                'password' { [void](Q 'UPDATE accounts SET salt=?,password_hash=? WHERE user_id=?' @($newSalt, $newHash, $id)) }
                'ban' { [void](Q 'UPDATE accounts SET ban_until=-1,ban_reason=''fixture ban'' WHERE user_id=?' @($id)) }
                'user_rate' { [void](Q 'INSERT INTO rate_limits(rate_key,failures,window_start) VALUES (?,5,?)' @($userKey, [string]$now)) }
                'ip_rate' { [void](Q 'INSERT INTO rate_limits(rate_key,failures,window_start) VALUES (?,20,?)' @($ipKey, [string]$now)) }
                'delete' { [void](Q 'DELETE FROM accounts WHERE user_id=?' @($id)) }
                'replace' { [void](Q 'DELETE FROM accounts WHERE user_id=?' @($id)); InsertAccount $replacementId $username 'Replacement identity' }
                'format' { [void](Q 'UPDATE accounts SET algorithm=''fixture-unsupported'',iterations=599999 WHERE user_id=?' @($id)) }
                default { throw 'UNKNOWN_FIXTURE' }
            }
            [void](Q 'COMMIT'); $inTransaction = $false; $mutated = $true
        } catch {
            if ($inTransaction) { try { [void](Q 'ROLLBACK') } catch { } }
            # Only a fixed SQLite status is recorded; never echo exception details.
            $mutationCode = if ($_.Exception.Message -match 'SQLITE_STEP_FAILED_5') { 'SQLITE_BUSY' } else { 'FIXTURE_FAILED' }
        } finally {
            $clock.Stop()
            [IO.File]::WriteAllText($script:gateRelease, 'release', $utf8)
        }
        Check ($mutated -and $clock.ElapsedMilliseconds -lt 2000) ($case.label + ': independent write commits while login is paused (300 ms busy limit)')
        $reply = CompleteAccount $active
        Check $reply.clean ($case.label + ': helper exits normally without error output')
        $actualCode = if ($reply.ok) { 'OK' } else { [string]$reply.code }
        if ($case.expected -eq '') {
            Check ($mutated -and $reply.ok -and $reply.identity.display_name -ceq 'After verification') ($case.label + ': successful login reads the latest identity')
            Check ((Scalar 'SELECT count(*) AS n FROM sessions WHERE user_id=?' @($id)) -eq 1) ($case.label + ': exactly one player session exists')
            Check ((Scalar 'SELECT count(*) AS n FROM account_audit WHERE action=''account.login'' AND target_id=? AND result=''OK''' @($id)) -eq 1) ($case.label + ': exactly one successful login is audited')
        } else {
            Check ($mutated -and -not $reply.ok -and $reply.code -ceq $case.expected) ($case.label + ': rejected with the existing expected code')
            Check ((Scalar 'SELECT count(*) AS n FROM sessions WHERE user_id=? OR user_id=?' @($id, $replacementId)) -eq 0) ($case.label + ': no old or replacement session is created')
            if ($case.mutate -in @('password', 'ban', 'delete', 'replace', 'format')) {
                Check ((Scalar 'SELECT failures AS n FROM rate_limits WHERE rate_key=?' @($userKey)) -eq 1) ($case.label + ': the failure is counted once')
            } elseif ($case.mutate -eq 'user_rate') {
                Check ((Scalar 'SELECT failures AS n FROM rate_limits WHERE rate_key=?' @($userKey)) -eq 5) ($case.label + ': limit refusal does not add another failure')
            } elseif ($case.mutate -eq 'ip_rate') {
                Check ((Scalar 'SELECT failures AS n FROM rate_limits WHERE rate_key=?' @($ipKey)) -eq 20) ($case.label + ': IP limit refusal does not add another failure')
            }
            if ($case.mutate -in @('delete', 'replace')) {
                Check ((Scalar 'SELECT count(*) AS n FROM account_audit WHERE actor_id=? OR target_id=? OR instr(reason,?)>0 OR instr(before_body,?)>0 OR instr(after_body,?)>0' @($id, $id, $id, $id, $id)) -eq 0) ($case.label + ': stale identity is not reintroduced into audit')
            }
        }
        # Check output in memory only; the JSON token is deliberately not saved.
        Check (-not $active.stdout.Result.Contains($oldPassword) -and -not $active.stdout.Result.Contains($newPassword) -and -not $active.stderr.Result.Contains($oldPassword) -and -not $active.stderr.Result.Contains($newPassword)) ($case.label + ': no password appears in helper output')
        $script:records += [pscustomobject]@{case = $case.label; barrier = $ready; mutation_committed = $mutated; mutation_ms = [int]$clock.ElapsedMilliseconds; mutation_code = $mutationCode; reply_code = $actualCode; clean = [bool]$reply.clean}
        $active.process.Dispose(); $active = $null
        [void](Q 'DELETE FROM sessions WHERE user_id=? OR user_id=?' @($id, $replacementId))
    }
    Check ((Q 'PRAGMA integrity_check')[0]['integrity_check'] -ceq 'ok') 'fake SQLite database passes integrity check'
    Check ($beforeAccount -ceq (Get-FileHash -LiteralPath $sourceAccount -Algorithm SHA256).Hash -and $beforeSqlite -ceq (Get-FileHash -LiteralPath $sourceSqlite -Algorithm SHA256).Hash) 'production helper files remain byte-for-byte unchanged'
} catch {
    $script:failed++
    # Raw exceptions could include driver arguments or contents; omit them.
    Write-Output 'FAIL login lock driver aborted; inspect redacted result and local fixture'
} finally {
    if ($null -ne $active) {
        if ($gateRelease) { try { [IO.File]::WriteAllText($gateRelease, 'release', $utf8) } catch { } }
        if (-not $active.process.HasExited) {
            if (-not $active.process.WaitForExit(5000)) { $active.process.Kill(); [void]$active.process.WaitForExit(5000) }
        }
        $active.process.Dispose()
    }
    if ($null -ne $connection) { $connection.Dispose() }
    $summary = @{passed = $script:passed; failed = $script:failed; cases = $script:records; fixture_busy_ms = 300; barrier_deadline_ms = 30000; source_account_sha256 = $beforeAccount; source_sqlite_sha256 = $beforeSqlite}
    [IO.File]::WriteAllText((Join-Path $root 'logs/result.json'), (ConvertTo-Json -InputObject $summary -Depth 8), $utf8)
    # On POSIX the private parent directory is 700; explicitly close file modes
    # as well so copied fixtures/databases never depend on a caller's umask.
    if ($script:RkPosix) {
        Get-ChildItem -LiteralPath $root -Force -Recurse | ForEach-Object {
            $mode = if ($_.PSIsContainer) { 'UserRead,UserWrite,UserExecute' } else { 'UserRead,UserWrite' }
            [IO.File]::SetUnixFileMode($_.FullName, [IO.UnixFileMode]$mode)
        }
    }
}
Write-Output ('ACCOUNT_LOGIN_LOCK_RESULT passed=' + $script:passed + ' failed=' + $script:failed + ' evidence=' + $root)
if ($script:failed -gt 0) { exit 1 }
exit 0

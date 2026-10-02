param([string]$DriverPath=(Join-Path $PSScriptRoot 'test_linux_concurrent_login.ps1'))
$ErrorActionPreference='Stop'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($DriverPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Driver parse errors' }
$functionTexts=@{}
foreach($name in 'IsFinalChildIdentity','Rk-StartHidden','RequireOwned') {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if ($null -eq $node) { throw ('Missing driver function '+$name) }
    $functionTexts[$name]=$node.Extent.Text
    Invoke-Expression $functionTexts[$name]
}
$checks=New-Object Collections.ArrayList
function Assert([bool]$Condition,[string]$Name) {
    [void]$script:checks.Add(@{name=$Name;ok=$Condition})
    if (-not $Condition) { throw $Name }
}
$engine='/home/mock/roomkit/engine/godot'
$arguments=@('--headless','--path','/home/mock/roomkit/source','--script','res://tests/run_framework_clients.gd','--','--test-config=/home/mock/roomkit/source/data/client/bootstrap.json')
$wrapper=@{start='12345';state='R';args=@('/bin/bash','-c','out=$1; err=$2; shift 2; exec "$@" > "$out" 2> "$err" < /dev/null','rk-start','/mock/stdout','/mock/stderr',$engine)+$arguments+@('')}
$final=@{start='12345';state='R';args=@($engine)+$arguments+@('')}
# No process is started. Use actual driver polling/capture/ownership functions
# with only the process launcher and /proc identity provider replaced.
$script:baseStart={param($FilePath,$Arguments,$Stdout,$Stderr) return @{Id=1234;HasExited=$false}}
function ProcessIdentity([int]$ProcessId) {
    $offset=[Math]::Min($script:reads,$script:sequence.Count-1)
    $script:reads++
    return $script:sequence[$offset]
}
function ExerciseSequence {
    $script:identities=@{}
    $script:reads=0
    $script:sequence=@($script:wrapper,$script:final,$script:final)
    $process=Rk-StartHidden $script:engine $script:arguments '/mock/stdout' '/mock/stderr'
    $captureReads=$script:reads
    $saved=$script:identities[$process.Id]
    $ownsFinal=$true
    try { RequireOwned $process } catch { $ownsFinal=$false }
    return @{capture_reads=$captureReads;captured_argv0=$saved.args[0];owns_final=$ownsFinal}
}
$legacyAccepted=$null -ne $wrapper -and $engine -cin $wrapper.args -and @($arguments | Where-Object { [string]$_ -cnotin $wrapper.args }).Count -eq 0
Assert $legacyAccepted 'counterexample really satisfies the old membership predicate'
Assert (-not (IsFinalChildIdentity $wrapper $engine $arguments)) 'actual final predicate rejects pre-exec bash argv'
Assert (IsFinalChildIdentity $final $engine $arguments) 'actual final predicate accepts post-exec engine argv'
Assert (-not (IsFinalChildIdentity $null $engine $arguments)) 'actual predicate rejects missing proc identity'
Assert (-not (IsFinalChildIdentity @{start='12345';args=@($engine,'--headless')} $engine $arguments)) 'actual predicate rejects incomplete engine args'
Assert (-not (IsFinalChildIdentity @{start='12345';args=@('/other/engine')+$arguments} $engine $arguments)) 'actual predicate rejects another argv0'
$current=ExerciseSequence
Assert ($current.capture_reads -eq 2 -and $current.captured_argv0 -ceq $engine -and $current.owns_final) 'actual startup polls through wrapper to exec and ownership stays stable'

# Mutation check restores the exact old membership decisions in-memory only.
# The SAME behavioral assertion must fail, proving this mock catches the bug
# rather than simply checking a helper's desired final result.
$legacyText=$functionTexts['Rk-StartHidden'].Replace('if (IsFinalChildIdentity $identity $FilePath $Arguments) { break }','if ($null -ne $identity -and $FilePath -cin $identity.args -and @($Arguments | Where-Object { [string]$_ -cnotin $identity.args }).Count -eq 0) { break }').Replace('if (-not (IsFinalChildIdentity $identity $FilePath $Arguments))','if ($null -eq $identity -or $FilePath -cnotin $identity.args -or @($Arguments | Where-Object { [string]$_ -cnotin $identity.args }).Count -gt 0)')
Assert ($legacyText -cne $functionTexts['Rk-StartHidden']) 'legacy mutation was actually applied to startup decisions'
Invoke-Expression $legacyText
$legacy=ExerciseSequence
$legacyPasses=$legacy.capture_reads -eq 2 -and $legacy.captured_argv0 -ceq $engine -and $legacy.owns_final
Assert (-not $legacyPasses -and $legacy.capture_reads -eq 1 -and $legacy.captured_argv0 -ceq '/bin/bash' -and -not $legacy.owns_final) 'same startup sequence catches the old wrapper capture and subsequent identity mismatch'
Invoke-Expression $functionTexts['Rk-StartHidden']
$restored=ExerciseSequence
Assert ($restored.capture_reads -eq 2 -and $restored.owns_final) 'restored candidate passes the wrapper-to-engine transition again'
foreach($check in $checks) { Write-Output ('PASS '+$check.name) }
Write-Output ('WRAPPER_ARGV_MOCK_RESULT passed='+$checks.Count+' failed=0 process_starts=0 source_mutations=0')
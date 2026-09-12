# Stop hook: validate Bicep before the agent finishes, if Bicep files changed.
#
# If the working tree has no uncommitted changes under infra/**/*.bicep or
# infra/**/*.bicepparam, this hook does nothing. Otherwise it runs
# lint/build/build-params and, on failure, blocks the agent from stopping so
# it can fix the errors. Never runs `what-if` or any deployment command.

$ErrorActionPreference = 'Stop'

function Write-Result {
    param($Result)
    $Result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$rawInput = [Console]::In.ReadToEnd()

try {
    $payload = $rawInput | ConvertFrom-Json
}
catch {
    # Malformed input: fail open rather than blocking the agent on a hook bug.
    Write-Result @{ continue = $true }
}

# Avoid re-blocking indefinitely if a previous Stop hook already forced a continuation.
if ($payload.stop_hook_active -eq $true) {
    Write-Result @{ continue = $true }
}

function Get-ChangedBicepFiles {
    try {
        $modified = git diff --name-only HEAD 2>$null
        $untracked = git ls-files --others --exclude-standard 2>$null
    }
    catch {
        return @()
    }
    $all = @($modified) + @($untracked) | Where-Object { $_ } | Select-Object -Unique
    return $all | Where-Object { $_ -match '^infra/.*\.(bicep|bicepparam)$' }
}

$changed = Get-ChangedBicepFiles

if (-not $changed -or $changed.Count -eq 0) {
    Write-Result @{ continue = $true }
}

# Fixed validation set — never includes what-if or any deployment command.
$checks = @(
    @{ Name = 'az bicep lint';         Args = @('bicep', 'lint', '--file', 'infra/main.bicep') },
    @{ Name = 'az bicep build';        Args = @('bicep', 'build', '--file', 'infra/main.bicep') },
    @{ Name = 'az bicep build-params'; Args = @('bicep', 'build-params', '--file', 'infra/environments/lab/main.bicepparam') }
)

$output = New-Object System.Collections.Generic.List[string]
$failed = $false

foreach ($check in $checks) {
    $output.Add("> $($check.Name)")
    $result = & az @($check.Args) 2>&1
    foreach ($line in $result) { $output.Add($line.ToString()) }
    if ($LASTEXITCODE -ne 0) {
        $failed = $true
        $output.Add("(exit code $LASTEXITCODE)")
    }
}

$summary = ($output -join "`n")

if ($failed) {
    Write-Result @{
        hookSpecificOutput = @{
            hookEventName = 'Stop'
            decision      = 'block'
            reason        = "Changed Bicep file(s) [$($changed -join ', ')] failed validation. Fix the errors before finishing:`n`n$summary"
        }
    }
}

Write-Result @{
    continue      = $true
    systemMessage = "Bicep validation passed for changed infra file(s): $($changed -join ', ')."
}

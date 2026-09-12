# PreToolUse hook: require explicit confirmation for Azure mutations.
#
# Reads the hook JSON payload from stdin, and if the invoked tool is a
# terminal-command tool whose command matches a known Azure CLI mutation
# (deployment create, resource/group delete, role assignment/definition
# create or delete), forces permissionDecision "ask" so the agent cannot
# auto-approve it. Read-only commands (what-if, show, list, bicep
# lint/build/build-params) are intentionally left alone.

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
    # Malformed input: fail open rather than breaking the agent session on a hook bug.
    Write-Result @{ continue = $true }
}

$toolName = [string]$payload.tool_name

# Only inspect terminal-command tools; match loosely since the exact tool
# name can vary across agent harnesses (e.g. runInTerminal, run_in_terminal).
if ([string]::IsNullOrEmpty($toolName) -or $toolName -notmatch 'Terminal') {
    Write-Result @{ continue = $true }
}

$command = [string]$payload.tool_input.command
if ([string]::IsNullOrEmpty($command)) {
    Write-Result @{ continue = $true }
}

# Azure CLI operations that create, modify, or destroy real Azure resources.
# Anything not matched here (what-if, show, list, bicep lint/build/build-params)
# is intentionally left unrestricted.
$mutatingPatterns = @(
    'az\s+deployment\s+sub\s+create',
    'az\s+deployment\s+group\s+create',
    'az\s+group\s+delete',
    'az\s+resource\s+delete',
    'az\s+role\s+assignment\s+create',
    'az\s+role\s+assignment\s+delete',
    'az\s+role\s+definition\s+create',
    'az\s+role\s+definition\s+delete'
)

foreach ($pattern in $mutatingPatterns) {
    if ($command -match $pattern) {
        Write-Result @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'ask'
                permissionDecisionReason = "Azure mutating command detected ('$($Matches[0])'). This repository requires explicit confirmation before any Azure deployment or destructive operation (see AGENTS.md / docs/DEVELOPMENT.md)."
            }
        }
    }
}

Write-Result @{ continue = $true }

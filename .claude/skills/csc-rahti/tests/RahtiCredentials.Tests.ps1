$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$initializeScript = Join-Path $skillRoot 'scripts\Initialize-RahtiCredential.ps1'
$connectScript = Join-Path $skillRoot 'scripts\Connect-Rahti.ps1'

Assert-True (Test-Path -LiteralPath $initializeScript) 'Initialize-RahtiCredential.ps1 exists'
Assert-True (Test-Path -LiteralPath $connectScript) 'Connect-Rahti.ps1 exists'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rahti-credentials-test-" + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $testRoot

try {
    $fakeOc = Join-Path $testRoot 'fake-oc.ps1'
    $fakeLog = Join-Path $testRoot 'oc.log'
    $secretFile = Join-Path $testRoot 'rahti-sa.env'
    $kubeconfig = Join-Path $testRoot 'config'
    $env:FAKE_OC_LOG = $fakeLog

    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $CommandArgs)
$ErrorActionPreference = 'Stop'
$line = $CommandArgs -join ' '
Add-Content -LiteralPath $env:FAKE_OC_LOG -Value $line

if ($line -eq 'whoami') { 'testuser'; exit 0 }
if ($line -like 'auth can-i *') { 'yes'; exit 0 }
if ($line -like 'get serviceaccount *') { exit 0 }
if ($line -like 'create serviceaccount *') { 'serviceaccount/deployer-bot created'; exit 0 }
if ($line -like 'adm policy add-role-to-user *') { 'role added'; exit 0 }
if ($line -like 'create token *') { 'test-token-value'; exit 0 }
if ($line -like 'login *') {
    $configArg = $CommandArgs | Where-Object { $_ -like '--kubeconfig=*' } | Select-Object -First 1
    $configPath = $configArg.Substring('--kubeconfig='.Length)
    [System.IO.File]::WriteAllText($configPath, 'apiVersion: v1')
    'Login successful.'
    exit 0
}
if ($line -like '--kubeconfig=* auth can-i *') { 'yes'; exit 0 }
if ($line -like 'config set-context *') { 'Context updated.'; exit 0 }
if ($line -like 'config current-context *') { 'my-project/api/system:serviceaccount:my-project:deployer-bot'; exit 0 }
if ($line -like 'config delete-context *') { exit 0 }
if ($line -like 'config rename-context *') { 'Context renamed.'; exit 0 }
if ($line -like 'config use-context *') { 'Switched.'; exit 0 }
if ($line -like '--kubeconfig=* whoami') { 'system:serviceaccount:my-project:deployer-bot'; exit 0 }

throw "Unexpected fake oc call: $line"
'@ | Set-Content -LiteralPath $fakeOc -Encoding utf8

    $initializeOutput = & $initializeScript `
        -Namespace 'my-project' `
        -AccessNamespaces @('my-project', 'other-project') `
        -ServiceAccount 'deployer-bot' `
        -Role 'admin' `
        -Duration '8760h' `
        -SecretFile $secretFile `
        -KubeconfigPath $kubeconfig `
        -OcCommand $fakeOc `
        -SkipConnect `
        -Force 2>&1 | Out-String

    Assert-True (Test-Path -LiteralPath $secretFile) 'bootstrap creates the synced secret file'
    $secretContent = Get-Content -Raw -LiteralPath $secretFile
    Assert-True ($secretContent -match '(?m)^RAHTI_API_SERVER=https://api\.2\.rahti\.csc\.fi:6443\r?$') 'secret contains the Rahti API server'
    Assert-True ($secretContent -match '(?m)^RAHTI_NAMESPACE=my-project\r?$') 'secret contains the namespace'
    Assert-True ($secretContent -match '(?m)^RAHTI_SERVICE_ACCOUNT=deployer-bot\r?$') 'secret contains the service account'
    Assert-True ($secretContent -match '(?m)^RAHTI_ACCESS_NAMESPACES=my-project,other-project\r?$') 'secret contains every granted namespace'
    Assert-True ($secretContent -match '(?m)^RAHTI_ROLE=admin\r?$') 'secret records the granted role'
    Assert-True ($secretContent -match '(?m)^RAHTI_TOKEN=test-token-value\r?$') 'secret contains the generated token'
    Assert-True ($initializeOutput -notmatch 'test-token-value') 'bootstrap never prints the token'

    $connectOutput = & $connectScript `
        -SecretFile $secretFile `
        -KubeconfigPath $kubeconfig `
        -OcCommand $fakeOc 2>&1 | Out-String

    Assert-True (Test-Path -LiteralPath $kubeconfig) 'connect creates a local kubeconfig'
    Assert-True ($connectOutput -notmatch 'test-token-value') 'connect never prints the token'
    Assert-True ($connectOutput -match 'system:serviceaccount:my-project:deployer-bot') 'connect verifies the expected service-account identity'
    Assert-True ($connectOutput -match 'Access verified: my-project, other-project') 'connect verifies every granted namespace'

    $missingSecretFailed = $false
    try {
        & $connectScript `
            -SecretFile (Join-Path $testRoot 'missing.env') `
            -KubeconfigPath $kubeconfig `
            -OcCommand $fakeOc 2>$null
    }
    catch {
        $missingSecretFailed = $_.Exception.Message -match 'Secret file not found'
    }
    Assert-True $missingSecretFailed 'connect rejects a missing secret file with a clear error'

    $calls = Get-Content -Raw -LiteralPath $fakeLog
    Assert-True ($calls -match 'create serviceaccount deployer-bot -n my-project') 'bootstrap creates a dedicated service account'
    Assert-True ($calls -match 'adm policy add-role-to-user admin system:serviceaccount:my-project:deployer-bot -n my-project') 'bootstrap grants the requested role in the primary namespace'
    Assert-True ($calls -match 'adm policy add-role-to-user admin system:serviceaccount:my-project:deployer-bot -n other-project') 'bootstrap grants the requested role in the additional namespace'
    Assert-True ($calls -match 'create token deployer-bot -n my-project --duration=8760h') 'bootstrap requests the configured token lifetime'

    Write-Output 'PASS: Rahti credential scripts'
}
finally {
    Remove-Item Env:\FAKE_OC_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

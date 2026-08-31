[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string] $Namespace,

    [string[]] $AccessNamespaces,

    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string] $ServiceAccount = 'deployer-bot',

    [ValidateSet('view', 'edit', 'admin')]
    [string] $Role = 'edit',

    [ValidatePattern('^[1-9][0-9]*(m|h)$')]
    [string] $Duration = '8760h',

    [string] $SecretFile,

    [string] $KubeconfigPath,

    [string] $OcCommand = 'oc',

    [switch] $SkipConnect,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'RahtiCredential.Common.ps1')

if (-not $SecretFile) {
    $SecretFile = Get-RahtiDefaultSecretFile -Namespace $Namespace
}
if (-not $KubeconfigPath) {
    $KubeconfigPath = Get-RahtiDefaultKubeconfig
}

if (-not $AccessNamespaces) {
    $AccessNamespaces = @($Namespace)
}
$AccessNamespaces = @($Namespace) + @($AccessNamespaces)
$AccessNamespaces = @($AccessNamespaces | Select-Object -Unique)
foreach ($accessNamespace in $AccessNamespaces) {
    if ($accessNamespace -notmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$') {
        throw "Invalid namespace name: $accessNamespace"
    }
}

if ((Test-Path -LiteralPath $SecretFile) -and -not $Force) {
    throw "Secret file already exists: $SecretFile. Use -Force only when intentionally rotating the credential."
}

$currentIdentity = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @('whoami') -Capture | Select-Object -Last 1).Trim()
if ($currentIdentity.StartsWith('system:serviceaccount:')) {
    throw 'Bootstrap requires an active personal oc login, not another service account.'
}

$allowed = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    'auth', 'can-i', 'create', 'serviceaccounts', '-n', $Namespace
) -Capture | Select-Object -Last 1).Trim()
if ($allowed -ne 'yes') {
    throw "Current user '$currentIdentity' cannot create serviceaccounts in namespace '$Namespace'."
}
foreach ($accessNamespace in $AccessNamespaces) {
    $allowed = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
        'auth', 'can-i', 'create', 'rolebindings', '-n', $accessNamespace
    ) -Capture | Select-Object -Last 1).Trim()
    if ($allowed -ne 'yes') {
        throw "Current user '$currentIdentity' cannot create rolebindings in namespace '$accessNamespace'."
    }
}

if (-not $PSCmdlet.ShouldProcess(
        "namespaces $($AccessNamespaces -join ', ')",
        "create or update service account $Namespace/$ServiceAccount with role $Role and issue a $Duration token"
    )) {
    return
}

$existing = Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    'get', 'serviceaccount', $ServiceAccount, '-n', $Namespace,
    '--ignore-not-found', '-o', 'name'
) -Capture

if (-not ($existing | Select-Object -First 1)) {
    $null = Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
        'create', 'serviceaccount', $ServiceAccount, '-n', $Namespace
    ) -Capture
}

foreach ($accessNamespace in $AccessNamespaces) {
    $null = Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
        'adm', 'policy', 'add-role-to-user', $Role,
        "system:serviceaccount:${Namespace}:${ServiceAccount}",
        '-n', $accessNamespace
    ) -Capture
}

$token = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    'create', 'token', $ServiceAccount, '-n', $Namespace,
    "--duration=$Duration"
) -Capture | Select-Object -Last 1).Trim()

if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Rahti returned an empty service-account token.'
}

$secretDirectory = Split-Path -Parent $SecretFile
if ($secretDirectory -and -not (Test-Path -LiteralPath $secretDirectory)) {
    $null = New-Item -ItemType Directory -Path $secretDirectory -Force
}

$createdAt = [DateTimeOffset]::UtcNow.ToString('o')
$content = @(
    '# Managed by csc-rahti/scripts/Initialize-RahtiCredential.ps1'
    '# Secret: do not commit, paste into chat, or copy outside the private env store.'
    'RAHTI_API_SERVER=https://api.2.rahti.csc.fi:6443'
    "RAHTI_NAMESPACE=$Namespace"
    "RAHTI_SERVICE_ACCOUNT=$ServiceAccount"
    "RAHTI_ACCESS_NAMESPACES=$($AccessNamespaces -join ',')"
    "RAHTI_ROLE=$Role"
    "RAHTI_TOKEN=$token"
    "RAHTI_TOKEN_DURATION=$Duration"
    "RAHTI_TOKEN_CREATED_AT=$createdAt"
) -join [Environment]::NewLine

[System.IO.File]::WriteAllText(
    $SecretFile,
    $content + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)
$token = $null
$content = $null

Write-Output "Rahti credential stored outside the repository: $SecretFile"
Write-Output "Identity: system:serviceaccount:${Namespace}:${ServiceAccount}"
Write-Output "Role: $Role in namespaces $($AccessNamespaces -join ', '); requested lifetime: $Duration"

if (-not $SkipConnect) {
    & (Join-Path $PSScriptRoot 'Connect-Rahti.ps1') `
        -Namespace $Namespace `
        -SecretFile $SecretFile `
        -KubeconfigPath $KubeconfigPath `
        -OcCommand $OcCommand
}

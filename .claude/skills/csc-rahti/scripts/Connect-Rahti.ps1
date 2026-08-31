[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string] $Namespace,

    [string] $SecretFile,

    [string] $KubeconfigPath,

    [string] $OcCommand = 'oc'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'RahtiCredential.Common.ps1')

if (-not $SecretFile) {
    if (-not $Namespace) {
        throw 'Specify -Namespace (to use the default secret location) or -SecretFile.'
    }
    $SecretFile = Get-RahtiDefaultSecretFile -Namespace $Namespace
}
if (-not $KubeconfigPath) {
    $KubeconfigPath = Get-RahtiDefaultKubeconfig
}

$credential = Read-RahtiEnvFile -Path $SecretFile
$storedNamespace = $credential.RAHTI_NAMESPACE
$serviceAccount = $credential.RAHTI_SERVICE_ACCOUNT
$expectedIdentity = "system:serviceaccount:${storedNamespace}:${serviceAccount}"
$accessNamespaces = if ($credential.ContainsKey('RAHTI_ACCESS_NAMESPACES')) {
    @($credential.RAHTI_ACCESS_NAMESPACES.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
else {
    @($storedNamespace)
}

if ($PSBoundParameters.ContainsKey('Namespace') -and $Namespace -ne $storedNamespace) {
    throw "Requested namespace '$Namespace' does not match secret namespace '$storedNamespace'."
}

$kubeDirectory = Split-Path -Parent $KubeconfigPath
if ($kubeDirectory -and -not (Test-Path -LiteralPath $kubeDirectory)) {
    $null = New-Item -ItemType Directory -Path $kubeDirectory -Force
}

# The token is deliberately passed only to oc and is never written to output.
$null = Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    'login',
    $credential.RAHTI_API_SERVER,
    "--token=$($credential.RAHTI_TOKEN)",
    "--kubeconfig=$KubeconfigPath"
) -Capture

$null = Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    'config', 'set-context', '--current',
    "--namespace=$storedNamespace",
    "--kubeconfig=$KubeconfigPath"
) -Capture

$identity = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
    "--kubeconfig=$KubeconfigPath", 'whoami'
) -Capture | Select-Object -Last 1).Trim()

if ($identity -ne $expectedIdentity) {
    throw "Rahti identity verification failed. Expected '$expectedIdentity', got '$identity'."
}

foreach ($accessNamespace in $accessNamespaces) {
    $allowed = (Invoke-RahtiOc -OcCommand $OcCommand -Arguments @(
        "--kubeconfig=$KubeconfigPath", 'auth', 'can-i', 'get', 'pods', '-n', $accessNamespace
    ) -Capture | Select-Object -Last 1).Trim()
    if ($allowed -ne 'yes') {
        throw "Rahti access verification failed for namespace '$accessNamespace'."
    }
}

Write-Output "Rahti CLI ready: $identity (namespace $storedNamespace)"
Write-Output "Access verified: $($accessNamespaces -join ', ')"
Write-Output "Kubeconfig: $KubeconfigPath"

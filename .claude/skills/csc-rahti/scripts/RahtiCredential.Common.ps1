Set-StrictMode -Version Latest

function Get-RahtiDefaultSecretFile {
    param([Parameter(Mandatory)] [string] $Namespace)

    # Private env store, outside any repository. Override with RAHTI_ENV_HOME.
    $envHome = if ($env:RAHTI_ENV_HOME) {
        $env:RAHTI_ENV_HOME
    }
    elseif ($env:AGENTS_HOME) {
        Join-Path $env:AGENTS_HOME 'env'
    }
    else {
        Join-Path $HOME '.agents\env'
    }

    Join-Path $envHome "rahti\$Namespace\rahti-sa.env"
}

function Get-RahtiDefaultKubeconfig {
    Join-Path $HOME '.kube\config'
}

function Read-RahtiEnvFile {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret file not found: $Path. Run Initialize-RahtiCredential.ps1 while a personal oc login is active."
    }

    $values = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            throw "Invalid env line in ${Path}: expected KEY=VALUE."
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }

    foreach ($required in 'RAHTI_API_SERVER', 'RAHTI_NAMESPACE', 'RAHTI_SERVICE_ACCOUNT', 'RAHTI_TOKEN') {
        if (-not $values.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($values[$required])) {
            throw "Missing $required in secret file: $Path"
        }
    }

    if ($values.RAHTI_API_SERVER -ne 'https://api.2.rahti.csc.fi:6443') {
        throw "Unexpected Rahti API server in secret file: $($values.RAHTI_API_SERVER)"
    }

    $values
}

function Invoke-RahtiOc {
    param(
        [Parameter(Mandatory)] [string] $OcCommand,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $Capture
    )

    if ($Capture) {
        $result = & $OcCommand @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "oc command failed with exit code $LASTEXITCODE."
        }
        return $result
    }

    & $OcCommand @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "oc command failed with exit code $LASTEXITCODE."
    }
}

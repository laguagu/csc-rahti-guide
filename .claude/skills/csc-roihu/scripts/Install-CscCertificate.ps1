<#
.SYNOPSIS
Installs a MyCSC-signed SSH certificate next to the matching private key.

.DESCRIPTION
MyCSC signs each registered public key separately, so downloading certificates for
an account with several machines yields several `cert.pub` / `cert (1).pub` files
that look identical. Only the one whose fingerprint matches this machine's key
works; installing the wrong one fails as "Permission denied (publickey)" with no
hint that the certificate was the problem.

This script matches each downloaded certificate against the local public keys by
fingerprint and installs the one that belongs here as `<key>-cert.pub`, which is
where OpenSSH looks automatically.

Certificates are valid 24 h, so this runs daily after re-signing in MyCSC.

.PARAMETER Source
Directory to scan for downloaded certificates. Defaults to ~/Downloads.

.PARAMETER SshDir
SSH directory holding the keys. Defaults to ~/.ssh.

.PARAMETER TestHost
Host to verify against after installing. Defaults to roihu-gpu.csc.fi.
Pass an empty string to skip the connection test.

.EXAMPLE
./Install-CscCertificate.ps1
.EXAMPLE
./Install-CscCertificate.ps1 -Source D:\tmp -TestHost roihu-cpu.csc.fi
#>
[CmdletBinding()]
param(
    [string]$Source   = (Join-Path $HOME 'Downloads'),
    [string]$SshDir   = (Join-Path $HOME '.ssh'),
    [string]$TestHost = 'roihu-gpu.csc.fi'
)

$ErrorActionPreference = 'Stop'

function Get-Fingerprint([string]$Path) {
    # ssh-keygen -lf prints "<bits> SHA256:<hash> <comment> (<type>)" for keys and
    # certificates alike, so one parser covers both.
    $line = & ssh-keygen -lf $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $line) { return $null }
    if ("$line" -match '(SHA256:\S+)') { return $Matches[1] }
    return $null
}

# Local keys: every *.pub that is not itself a certificate.
$localKeys = Get-ChildItem $SshDir -Filter '*.pub' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*-cert.pub' } |
    ForEach-Object { [pscustomobject]@{ File = $_; Fingerprint = Get-Fingerprint $_.FullName } } |
    Where-Object { $_.Fingerprint }

if (-not $localKeys) { throw "No SSH public keys found in $SshDir. Generate one with: ssh-keygen -t ed25519" }

# Candidate certificates, newest first — a re-signed certificate should win.
$certs = Get-ChildItem $Source -Filter '*cert*.pub' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if (-not $certs) { throw "No certificate files matching '*cert*.pub' in $Source. Download one from https://my.csc.fi (Profile -> SSH public keys -> key menu -> Sign and download SSH certificate)." }

$installed = @()
foreach ($cert in $certs) {
    $fp = Get-Fingerprint $cert.FullName
    if (-not $fp) { Write-Verbose "Skipping $($cert.Name): not a valid key/certificate file"; continue }

    $match = $localKeys | Where-Object { $_.Fingerprint -eq $fp } | Select-Object -First 1
    if (-not $match) {
        Write-Host "skip    $($cert.Name) -> no local key with $fp (certificate for another machine)" -ForegroundColor DarkGray
        continue
    }

    $target = Join-Path $SshDir ($match.File.BaseName + '-cert.pub')
    if ($installed -contains $target) { continue }   # newest already won

    Copy-Item $cert.FullName $target -Force
    $installed += $target

    $valid = (& ssh-keygen -Lf $target 2>$null | Select-String 'Valid:').ToString().Trim()
    Write-Host "install $($cert.Name) -> $target" -ForegroundColor Green
    Write-Host "        $valid" -ForegroundColor DarkGray
}

if (-not $installed) { throw "None of the certificates in $Source match a key in $SshDir. Re-sign the key whose fingerprint is: $($localKeys[0].Fingerprint)" }

if ($TestHost) {
    Write-Host "`nTesting $TestHost ..." -ForegroundColor Cyan
    $user = $env:CSC_USERNAME
    $target = if ($user) { "$user@$TestHost" } else { $TestHost }
    & ssh -o BatchMode=yes -o ConnectTimeout=20 $target 'hostname'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Connection failed. If this says 'Permission denied (publickey)', the CSC username is probably missing — set `$env:CSC_USERNAME or use ssh <user>@$TestHost." -ForegroundColor Yellow
    }
}

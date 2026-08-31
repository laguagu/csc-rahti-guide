<#
.SYNOPSIS
    Kerää CSC Rahti 2 -namespacejen tilannekuvan JSONina. READ-ONLY.

.DESCRIPTION
    Ajaa pelkkiä lukevia `oc get` -komentoja ja HTTP-pyyntöjä routeille.
    Ei sisällä eikä saa koskaan sisältää kirjoittavia komentoja
    (delete, scale, apply, set, annotate, rollout).

    Tulostaa yhden JSON-objektin stdoutiin:
      { generatedAt, whoami, server, namespaces: { <ns>: { workloads, pods,
        routes, warnings, quota, errors } } }

.PARAMETER Namespace
    Auditoitavat namespacet. Oletuksena kaikki `oc projects -q` -listan.

.PARAMETER SkipRoutes
    Ohita routejen HTTP-tarkistus (nopeampi, pelkkä klusteritila).

.PARAMETER TimeoutSec
    HTTP-pyynnön aikakatkaisu sekunteina. Oletus 15.

.PARAMETER EventLimit
    Montako tuoreinta warning-eventtiä per namespace. Oletus 15.

.EXAMPLE
    .\Get-RahtiStatus.ps1 | ConvertFrom-Json

.EXAMPLE
    .\Get-RahtiStatus.ps1 -Namespace my-project -TimeoutSec 30
#>
[CmdletBinding()]
param(
    [string[]]$Namespace,
    [switch]$SkipRoutes,
    [int]$TimeoutSec = 15,
    [int]$EventLimit = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OcJson {
    <# Ajaa `oc get <args> -o json` ja palauttaa objektin, tai $null jos kutsu epäonnistuu. #>
    param([Parameter(Mandatory)][string[]]$OcArgs)
    try {
        $raw = & oc get @OcArgs -o json 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($raw -join "`n" | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-AgeDays {
    param($Timestamp)
    if (-not $Timestamp) { return $null }
    try { return [math]::Round(((Get-Date) - [datetime]$Timestamp).TotalDays, 1) } catch { return $null }
}

function Test-RouteHealth {
    <#
      Kaksi yritystä ennen kuin route merkitään alas — cold start ja
      skaalattu-nollaan antavat ensimmäisellä pyynnöllä väärän hälytyksen.
      HEAD ensin; jos sovellus vastaa 405, uusitaan GETillä.
    #>
    param([Parameter(Mandatory)][string]$Url, [int]$TimeoutSec = 15)

    $lastError = $null
    foreach ($attempt in 1..2) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $resp = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec $TimeoutSec `
                -SkipHttpErrorCheck -MaximumRedirection 5 -ErrorAction Stop
            if ([int]$resp.StatusCode -eq 405) {
                $sw.Restart()
                $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $TimeoutSec `
                    -SkipHttpErrorCheck -MaximumRedirection 5 -ErrorAction Stop
            }
            $sw.Stop()
            return [ordered]@{
                status   = [int]$resp.StatusCode
                ms       = [int]$sw.Elapsed.TotalMilliseconds
                attempts = $attempt
                error    = $null
            }
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt 2) { Start-Sleep -Seconds 2 }
        }
    }
    return [ordered]@{ status = $null; ms = $null; attempts = 2; error = $lastError }
}

# --- Esitarkistukset -------------------------------------------------------

if (-not (Get-Command oc -ErrorAction SilentlyContinue)) {
    throw "oc CLI ei ole PATHissa. Asenna se Rahti-konsolin Command Line Tools -sivulta."
}

$whoami = (& oc whoami 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Rahti-kirjautuminen puuttuu tai on vanhentunut. Kirjaudu `oc login` -komennolla tai aja csc-rahti-skillin Connect-Rahti.ps1 -Namespace <namespace>."
}

$server = (& oc whoami --show-server 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { $server = $null }

if (-not $Namespace -or $Namespace.Count -eq 0) {
    $projects = & oc projects -q 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Namespacejen listaus epäonnistui: $projects" }
    $Namespace = @($projects | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# --- Keruu -----------------------------------------------------------------

$result = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    whoami      = $whoami
    server      = $server
    namespaces  = [ordered]@{}
}

foreach ($ns in $Namespace) {
    $nsData = [ordered]@{
        workloads = @()
        pods      = @()
        routes    = @()
        warnings  = @()
        quota     = @()
        errors    = @()
    }

    # Deploymentit ja statefulsetit
    foreach ($kind in 'deployments', 'statefulsets') {
        $items = Get-OcJson @($kind, '-n', $ns)
        if ($null -eq $items) { $nsData.errors += "Haku epäonnistui: $kind"; continue }
        foreach ($w in $items.items) {
            $desired = if ($w.spec.PSObject.Properties['replicas']) { $w.spec.replicas } else { 1 }
            $ready = if ($w.status.PSObject.Properties['readyReplicas']) { $w.status.readyReplicas } else { 0 }
            $nsData.workloads += [ordered]@{
                kind     = $w.kind
                name     = $w.metadata.name
                desired  = $desired
                ready    = $ready
                healthy  = ($ready -eq $desired -and $desired -gt 0)
                ageDays  = Get-AgeDays $w.metadata.creationTimestamp
            }
        }
    }

    # Podit
    $pods = Get-OcJson @('pods', '-n', $ns)
    if ($null -eq $pods) {
        $nsData.errors += 'Haku epäonnistui: pods'
    } else {
        foreach ($p in $pods.items) {
            $cs = @()
            if ($p.status.PSObject.Properties['containerStatuses']) { $cs = @($p.status.containerStatuses) }

            $restarts = 0
            if ($cs.Count -gt 0) { $restarts = ($cs | Measure-Object -Property restartCount -Sum).Sum }

            $waitingReasons = @()
            $lastTermReasons = @()
            foreach ($c in $cs) {
                if ($c.state.PSObject.Properties['waiting'] -and $c.state.waiting) {
                    $waitingReasons += $c.state.waiting.reason
                }
                if ($c.PSObject.Properties['lastState'] -and $c.lastState.PSObject.Properties['terminated'] -and $c.lastState.terminated) {
                    $lastTermReasons += $c.lastState.terminated.reason
                }
            }

            $nsData.pods += [ordered]@{
                name           = $p.metadata.name
                phase          = $p.status.phase
                readyCount     = @($cs | Where-Object { $_.ready }).Count
                containerCount = $cs.Count
                restarts       = $restarts
                ageDays        = Get-AgeDays $p.metadata.creationTimestamp
                waiting        = @($waitingReasons | Where-Object { $_ } | Select-Object -Unique)
                lastTerminated = @($lastTermReasons | Where-Object { $_ } | Select-Object -Unique)
            }
        }
    }

    # Routet + HTTP-terveys
    $routes = Get-OcJson @('routes', '-n', $ns)
    if ($null -eq $routes) {
        $nsData.errors += 'Haku epäonnistui: routes'
    } else {
        foreach ($r in $routes.items) {
            $scheme = if ($r.spec.PSObject.Properties['tls'] -and $r.spec.tls) { 'https' } else { 'http' }
            $path = if ($r.spec.PSObject.Properties['path'] -and $r.spec.path) { $r.spec.path } else { '' }
            $url = "${scheme}://$($r.spec.host)$path"

            $entry = [ordered]@{
                name    = $r.metadata.name
                url     = $url
                service = $r.spec.to.name
                health  = $null
            }
            if (-not $SkipRoutes) {
                $entry.health = Test-RouteHealth -Url $url -TimeoutSec $TimeoutSec
            }
            $nsData.routes += $entry
        }
    }

    # Warning-eventit, tuoreimmat ensin
    $events = Get-OcJson @('events', '-n', $ns, '--field-selector', 'type=Warning')
    if ($null -eq $events) {
        $nsData.errors += 'Haku epäonnistui: events'
    } else {
        $nsData.warnings = @(
            $events.items |
                Sort-Object -Property { $_.lastTimestamp } -Descending |
                Select-Object -First $EventLimit |
                ForEach-Object {
                    [ordered]@{
                        object  = "$($_.involvedObject.kind)/$($_.involvedObject.name)"
                        reason  = $_.reason
                        count   = $_.count
                        last    = $_.lastTimestamp
                        message = $_.message
                    }
                }
        )
    }

    # Kiintiöt käyttöasteineen
    $quotas = Get-OcJson @('resourcequota', '-n', $ns)
    if ($null -eq $quotas) {
        $nsData.errors += 'Haku epäonnistui: resourcequota'
    } else {
        foreach ($q in $quotas.items) {
            if (-not $q.status.PSObject.Properties['hard']) { continue }
            $lines = @()
            foreach ($key in $q.status.hard.PSObject.Properties.Name) {
                $hard = $q.status.hard.$key
                $used = if ($q.status.PSObject.Properties['used']) { $q.status.used.$key } else { $null }
                $lines += [ordered]@{ resource = $key; used = $used; hard = $hard }
            }
            $nsData.quota += [ordered]@{ name = $q.metadata.name; items = $lines }
        }
    }

    $result.namespaces[$ns] = $nsData
}

$result | ConvertTo-Json -Depth 10

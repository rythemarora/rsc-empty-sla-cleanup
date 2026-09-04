<#
.SYNOPSIS
    Deletes Rubrik Security Cloud (RSC) SLA Domains whose name contains a
    given substring, but only when the SLA Domain has zero objects (workloads)
    currently assigned.

.DESCRIPTION
    Uses the official Rubrik Security Cloud PowerShell SDK (RubrikSecurityCloud,
    https://github.com/rubrikinc/rubrik-powershell-sdk) to:

      1. Connect to RSC (Connect-Rsc).
      2. Ask which substring the SLA Domain name should contain (e.g. "Rhy",
         "test", ...) - either via -NamePattern or an interactive prompt.
      3. Retrieve all SLA Domains whose name contains that pattern
         (Get-RscSla -Name <pattern>), requesting the live protected-object count.
      4. Filter down to only the SLA Domains with ProtectedObjectCount -eq 0 -
         these are the only ones listed and the only ones considered for deletion.
         Any SLA Domain with 1 or more assigned objects is listed separately as
         skipped, and never touched.
      5. Delete each listed (zero-object) SLA Domain via Remove-RscSla.

    Safe by default:
      - Supports -WhatIf / -Confirm (ShouldProcess) so you can preview first.
      - Prompts individually per SLA Domain unless -Force is supplied.
      - Never deletes an SLA Domain with ProtectedObjectCount -gt 0, full stop.

.PARAMETER NamePattern
    Substring to match in the SLA Domain name (case-insensitive), e.g. "Rhy" or
    "test". If not supplied, the script prompts for it interactively.

.PARAMETER ServiceAccountFile
    Optional path to a clear-text RSC service account JSON file (downloaded from
    the RSC UI). If supplied, it is registered once via Set-RscServiceAccountFile
    and the script connects using that encrypted file. This takes priority over
    -Server/-ClientId/-ClientSecret and over the interactive prompt.

.PARAMETER Server
    FQDN of the RSC instance, e.g. mycompany.my.rubrik.com. If not supplied (and
    -ServiceAccountFile is not used), the script prompts for it interactively.

.PARAMETER ClientId
    RSC Service Account Client ID. If not supplied (and -ServiceAccountFile is
    not used), the script prompts for it interactively.

.PARAMETER ClientSecret
    RSC Service Account Client Secret, as a SecureString. If not supplied (and
    -ServiceAccountFile is not used), the script prompts for it interactively
    with masked input.

.PARAMETER Force
    Skip the per-SLA-Domain confirmation prompt (still honors -WhatIf).

.EXAMPLE
    # Preview only - shows what WOULD be deleted, deletes nothing.
    # Prompts interactively for the name pattern and for Server / Client ID / Client Secret.
    ./Remove-EmptySlaDomains.ps1 -WhatIf

.EXAMPLE
    # Real run, supplying the name pattern and Client ID/Server up front - only prompts for the secret
    ./Remove-EmptySlaDomains.ps1 -NamePattern "test" -Server "mycompany.my.rubrik.com" -ClientId "client|xxxxxxxx"

.EXAMPLE
    # Real run using a previously-downloaded service account JSON file instead
    ./Remove-EmptySlaDomains.ps1 -NamePattern "Rhy" -ServiceAccountFile "C:\path\rsc-service-account.json"

.EXAMPLE
    # Real run, no per-item prompts
    ./Remove-EmptySlaDomains.ps1 -NamePattern "test" -Force

.NOTES
    Requires the RubrikSecurityCloud PowerShell module:
        Install-Module -Name RubrikSecurityCloud
    Docs: https://developer.rubrik.com/SDKs-and-Tools/PowerShell/

    Note: this SDK has no browser/SSO login flow - Connect-Rsc only supports
    Rubrik Service Account authentication (Client ID + Client Secret, either
    typed in directly or loaded from a service account file).
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false)]
    [string]$NamePattern,

    [Parameter(Mandatory = $false)]
    [string]$ServiceAccountFile,

    [Parameter(Mandatory = $false)]
    [string]$Server,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Section($text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 0. Ask what the SLA Domain name should contain, if not already supplied
# ---------------------------------------------------------------------------
while ([string]::IsNullOrWhiteSpace($NamePattern)) {
    $NamePattern = Read-Host "Enter the text the SLA Domain name should contain (e.g. Rhy, test)"
}

# ---------------------------------------------------------------------------
# 1. Make sure the RSC SDK module is available
# ---------------------------------------------------------------------------
Write-Section "Checking prerequisites"

if (-not (Get-Module -ListAvailable -Name RubrikSecurityCloud)) {
    Write-Host "RubrikSecurityCloud module not found. Installing from PowerShell Gallery..." -ForegroundColor Yellow
    Install-Module -Name RubrikSecurityCloud -Scope CurrentUser -Force -AllowClobber
}

Import-Module RubrikSecurityCloud -ErrorAction Stop
Write-Host "RubrikSecurityCloud module loaded." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Establish credentials: service account file takes priority; otherwise
#    use whatever Server/ClientId/ClientSecret were passed in, prompting
#    interactively (with masked secret input) for anything missing.
# ---------------------------------------------------------------------------
Write-Section "Connecting to Rubrik Security Cloud"

if ($ServiceAccountFile) {

    if (-not (Test-Path $ServiceAccountFile)) {
        throw "Service account file not found at path: $ServiceAccountFile"
    }
    Write-Host "Registering service account file..." -ForegroundColor Yellow
    Set-RscServiceAccountFile $ServiceAccountFile
    Write-Host "Service account file registered (encrypted copy stored by the SDK)." -ForegroundColor Green
    Write-Host "You can safely delete the clear-text file: $ServiceAccountFile" -ForegroundColor Yellow

    Connect-Rsc
}
else {
    # No file supplied - fall back to direct Client ID / Client Secret auth.
    # Prompt for anything not already supplied as a parameter.
    if (-not $Server) {
        $Server = Read-Host "RSC Server (e.g. mycompany.my.rubrik.com)"
    }
    if (-not $ClientId) {
        $ClientId = Read-Host "RSC Service Account Client ID"
    }
    if (-not $ClientSecret) {
        $ClientSecret = Read-Host "RSC Service Account Client Secret" -AsSecureString
    }

    if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($ClientId) -or -not $ClientSecret) {
        throw "Server, Client ID, and Client Secret are all required to connect."
    }

    Connect-Rsc -Server $Server -ClientId $ClientId -ClientSecret $ClientSecret
}

Write-Host "Connected to RSC." -ForegroundColor Green

try {
    # -----------------------------------------------------------------------
    # 4. Retrieve SLA Domains matching the name pattern (live data), then
    #    narrow down to only the ones with 0 protected objects.
    # -----------------------------------------------------------------------
    Write-Section "Retrieving SLA Domains matching '*$NamePattern*'"

    $matchingSlas = Get-RscSla -Name $NamePattern

    if (-not $matchingSlas -or $matchingSlas.Count -eq 0) {
        Write-Host "No SLA Domains found containing '$NamePattern'. Nothing to do." -ForegroundColor Yellow
        return
    }

    # Client-side safety net: keep only SLA Domains whose name really contains
    # the pattern (case-insensitive), in case the API's filter is ever looser
    # than expected (e.g. matches description instead of name).
    $matchingSlas = $matchingSlas | Where-Object { $_.Name -match [regex]::Escape($NamePattern) }

    # Split into deletion candidates (0 objects) and skipped ones (still in use).
    $zeroObjectSlas    = $matchingSlas | Where-Object { $_.ProtectedObjectCount -eq 0 }
    $skippedHasObjects = $matchingSlas | Where-Object { $_.ProtectedObjectCount -gt 0 }

    if ($skippedHasObjects.Count -gt 0) {
        Write-Host "SLA Domain(s) matching '$NamePattern' SKIPPED (objects still assigned):" -ForegroundColor Yellow
        $skippedHasObjects | ForEach-Object {
            Write-Host ("  - {0}  (Id: {1}, ProtectedObjectCount: {2})" -f $_.Name, $_.Id, $_.ProtectedObjectCount)
        }
    }

    if (-not $zeroObjectSlas -or $zeroObjectSlas.Count -eq 0) {
        Write-Host "No SLA Domains matching '$NamePattern' have 0 protected objects. Nothing to delete." -ForegroundColor Yellow
        return
    }

    Write-Host "SLA Domain(s) matching '$NamePattern' with 0 protected objects (candidates for deletion):" -ForegroundColor Green
    $zeroObjectSlas | ForEach-Object {
        Write-Host ("  - {0}  (Id: {1})" -f $_.Name, $_.Id)
    }

    # -----------------------------------------------------------------------
    # 5. Delete each zero-object SLA Domain
    # -----------------------------------------------------------------------
    Write-Section "Deleting SLA Domains"

    $deleted = @()
    $failed = @()

    foreach ($sla in $zeroObjectSlas) {

        # Defense in depth: re-check right before deleting in case anything
        # changed between the listing above and this point.
        if ($sla.ProtectedObjectCount -gt 0) {
            Write-Host "Skipping '$($sla.Name)' - no longer has 0 protected objects." -ForegroundColor Yellow
            continue
        }

        $target = "SLA Domain '$($sla.Name)' (Id: $($sla.Id))"

        if ($Force -or $PSCmdlet.ShouldProcess($target, "Delete (0 objects assigned)")) {
            try {
                # Use -SlaId (plain string) rather than piping the SLA object in -
                # Remove-RscSla's pipeline parameter set requires a strictly-typed
                # GlobalSlaReply object, and objects returned by Get-RscSla don't
                # always bind cleanly through the pipe.
                Remove-RscSla -SlaId $sla.Id -UserNote "Deleted by automated script: name contains '$NamePattern', 0 objects assigned." | Out-Null
                Write-Host "Deleted: $target" -ForegroundColor Green
                $deleted += $sla
            }
            catch {
                Write-Host "FAILED to delete $target : $($_.Exception.Message)" -ForegroundColor Red
                $failed += $sla
            }
        }
    }

    # -----------------------------------------------------------------------
    # 6. Summary
    # -----------------------------------------------------------------------
    Write-Section "Summary"
    Write-Host "Deleted: $($deleted.Count)" -ForegroundColor Green
    Write-Host "Skipped: $($skippedHasObjects.Count) (objects still assigned)" -ForegroundColor Yellow
    Write-Host "Failed:  $($failed.Count)" -ForegroundColor Red

    if ($skippedHasObjects.Count -gt 0) {
        Write-Host ""
        Write-Host "SLA Domains left in place because objects are still assigned:" -ForegroundColor Yellow
        $skippedHasObjects | ForEach-Object {
            Write-Host ("  - {0}  (Id: {1}, ProtectedObjectCount: {2})" -f $_.Name, $_.Id, $_.ProtectedObjectCount)
        }
    }
}
finally {
    # -------------------------------------------------------------------
    # 7. Always disconnect
    # -------------------------------------------------------------------
    Write-Section "Disconnecting"
    Disconnect-Rsc
    Write-Host "Disconnected from RSC." -ForegroundColor Green
}
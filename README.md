# Remove-EmptySlaDomains.ps1

A PowerShell script that safely deletes **Rubrik Security Cloud (RSC) SLA
Domains** whose name contains a given substring — but **only** when the SLA
Domain currently has **zero objects (workloads) assigned to it**. Anything
still in use is listed as skipped and is never touched.

Built on the official [Rubrik Security Cloud PowerShell SDK](https://github.com/rubrikinc/rubrik-powershell-sdk).

## What it does

1. Prompts for the text the SLA Domain name should contain (e.g. `Rhy`,
   `test`) — or accepts it via `-NamePattern`.
2. Connects to RSC (`Connect-Rsc`), using a Service Account.
3. Retrieves all SLA Domains whose name contains that text
   (`Get-RscSla -Name <pattern>`), including the live protected-object count.
4. Splits the matches into two groups:
   - **Skipped** — SLA Domains with 1+ objects still assigned. These are
     listed with their object count, but never modified.
   - **Candidates for deletion** — SLA Domains with `ProtectedObjectCount -eq 0`.
5. Deletes only the zero-object SLA Domains (`Remove-RscSla`), one at a time,
   with a confirmation prompt per item (unless `-Force` is used).
6. Prints a summary: how many were deleted, how many were skipped (with
   names), and how many failed.

## Safety

- Supports `-WhatIf` — preview exactly what would be deleted without deleting
  anything.
- Prompts for confirmation on every individual SLA Domain unless `-Force` is
  passed.
- Hard rule: an SLA Domain with any objects assigned is **never** deleted,
  no matter what. It's filtered out before the deletion step even runs, and
  re-checked again immediately before each delete call as a safety net.

## Prerequisites

- PowerShell 5.1+ (Windows) or PowerShell 7+ (Windows/macOS/Linux)
- The `RubrikSecurityCloud` module (installed automatically by the script if
  missing):
  ```powershell
  Install-Module -Name RubrikSecurityCloud -Scope CurrentUser
  ```
- An RSC Service Account with permissions to read and delete SLA Domains.
  Create one from the RSC UI under **Settings → Service Accounts**, and note
  the `client_id` / `client_secret` (or download the JSON file).

## Authentication

This script uses RSC **Service Account** authentication only — the
underlying SDK has no browser/SSO login flow. You can authenticate one of
two ways:

**1. Type in credentials directly (default, interactive)**

If you don't pass `-ServiceAccountFile`, the script prompts for:
- `Server` — the RSC instance FQDN, e.g. `mycompany.my.rubrik.com`
- `ClientId` — the Service Account Client ID
- `ClientSecret` — the Service Account Client Secret (masked input)

Any of these can also be passed as parameters to skip that particular prompt.

**2. Use a downloaded Service Account JSON file**

```powershell
./Remove-EmptySlaDomains.ps1 -ServiceAccountFile "C:\path\rsc-service-account.json"
```

The file is registered once via `Set-RscServiceAccountFile` (which stores an
encrypted copy) and used for the connection. The clear-text JSON can be
deleted afterward.

## Usage

```powershell
# Interactive: prompts for the name pattern, then Server/ClientId/ClientSecret
./Remove-EmptySlaDomains.ps1

# Preview only — shows what would be deleted, deletes nothing
./Remove-EmptySlaDomains.ps1 -NamePattern "Rhy" -WhatIf

# Real run, supplying everything up front except the secret
./Remove-EmptySlaDomains.ps1 -NamePattern "test" -Server "mycompany.my.rubrik.com" -ClientId "client|xxxxxxxx"

# Real run using a Service Account JSON file
./Remove-EmptySlaDomains.ps1 -NamePattern "Rhy" -ServiceAccountFile "C:\path\rsc-service-account.json"

# Real run, no per-item confirmation prompts
./Remove-EmptySlaDomains.ps1 -NamePattern "test" -Force
```

## Parameters

| Parameter            | Required | Description                                                                                   |
|-----------------------|----------|-----------------------------------------------------------------------------------------------|
| `-NamePattern`        | No       | Substring to match in the SLA Domain name (case-insensitive). Prompted for if omitted.        |
| `-ServiceAccountFile` | No       | Path to a clear-text Service Account JSON file downloaded from the RSC UI.                    |
| `-Server`             | No       | RSC instance FQDN, e.g. `mycompany.my.rubrik.com`. Prompted for if omitted (and no SA file).   |
| `-ClientId`           | No       | RSC Service Account Client ID. Prompted for if omitted (and no SA file).                       |
| `-ClientSecret`       | No       | RSC Service Account Client Secret (`SecureString`). Prompted for if omitted (and no SA file). |
| `-Force`              | No       | Skip the per-SLA-Domain confirmation prompt. `-WhatIf` still overrides this.                   |
| `-WhatIf`             | No       | Standard PowerShell switch — preview actions without making changes.                          |

## Example output

```
=== Retrieving SLA Domains matching '*Rhy*' ===
SLA Domain(s) matching 'Rhy' SKIPPED (objects still assigned):
  - Rhy-Azure-Devops-SLA  (Id: ...-...-..., ProtectedObjectCount: 3)
  - Rhy-SQL-AD-WIN-HyperV-SLA  (Id: ...-...-..., ProtectedObjectCount: 11)
SLA Domain(s) matching 'Rhy' with 0 protected objects (candidates for deletion):
  - Rhy-Cloud-only-SLA  (Id: ...-...-...)
  - Rhy_1_hour  (Id: ...-...-...)

=== Deleting SLA Domains ===
Deleted: SLA Domain 'Rhy-Cloud-only-SLA' (Id: ...-...-...)
Deleted: SLA Domain 'Rhy_1_hour' (Id: ...-...-...)

=== Summary ===
Deleted: 2
Skipped: 2 (objects still assigned)
Failed:  0
```

## Notes / troubleshooting

- **`Call to "api/client_token" failed with : Not Found`** — the Service
  Account's `access_token_uri` is stale or invalid (e.g. the account was
  deleted/regenerated in RSC, or the cached credential file is outdated).
  Re-download a fresh Service Account JSON from the RSC UI and reconnect.
- **`The input object cannot be bound to any parameters...`** on delete —
  this SDK version's `Remove-RscSla` pipeline binding can reject objects
  returned by `Get-RscSla`. This script avoids the pipe entirely and calls
  `Remove-RscSla -SlaId <id>` directly.
- This script performs live deletions against your RSC tenant. Always run
  with `-WhatIf` first in an unfamiliar environment.

## License

Add your preferred license here (e.g. MIT) before publishing.

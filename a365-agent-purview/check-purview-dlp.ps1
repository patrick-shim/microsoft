# check-purview-dlp.ps1
# Thoroughly dumps the Purview DLP policy + rule config for the Application (AI apps)
# enforcement plane, including each SIT's match THRESHOLDS (minCount / maxCount / confidence).
# Run in an INTERACTIVE PowerShell (a browser sign-in opens). Paste the whole output back.
#
#   Connect first if not already connected:
#     Import-Module ExchangeOnlineManagement
#     Connect-IPPSSession -UserPrincipalName admin@diax48836189.onmicrosoft.com
#
# Then:  .\check-purview-dlp.ps1

$ErrorActionPreference = "Stop"

Write-Host "`n=================  CONNECTION  =================" -ForegroundColor Cyan
try { (Get-ConnectionInformation | Select-Object -First 1) | Format-List UserPrincipalName, ConnectionUri, TokenStatus }
catch { Write-Host "Not connected. Run Connect-IPPSSession first." -ForegroundColor Red; return }

Write-Host "`n=================  ALL DLP POLICIES  =================" -ForegroundColor Cyan
Get-DlpCompliancePolicy | Format-Table Name, Mode, Enabled, Workload, @{n='Planes';e={$_.EnforcementPlanes -join ','}} -AutoSize

Write-Host "`n=================  APPLICATION-PLANE POLICIES (detail)  =================" -ForegroundColor Cyan
$appPolicies = Get-DlpCompliancePolicy | Where-Object { $_.EnforcementPlanes -contains "Application" -or $_.Workload -match "Applications" }
if (-not $appPolicies) { Write-Host "!! No Application-plane DLP policy found. This is why nothing blocks in the agent." -ForegroundColor Red }

foreach ($p in $appPolicies) {
  Write-Host "`n----- POLICY: $($p.Name) -----" -ForegroundColor Yellow
  $p | Format-List Name, Guid, Mode, Enabled, Workload, @{n='EnforcementPlanes';e={$_.EnforcementPlanes -join ', '}}, `
      @{n='AppLocations';e={ ($_.ExchangeLocation + $_.OneDriveLocation + $_.SharePointLocation + $_.EndpointDlpLocation + $_.AppLocation) | Out-String }}, CreatedBy, WhenChanged
  Write-Host "  (raw locations blob):" -ForegroundColor DarkGray
  $p | Select-Object -ExpandProperty Locations -ErrorAction SilentlyContinue

  Write-Host "`n  ----- RULES in '$($p.Name)' -----" -ForegroundColor Yellow
  $rules = Get-DlpComplianceRule -Policy $p.Name
  foreach ($r in $rules) {
    Write-Host "`n  RULE: $($r.Name)  (Disabled=$($r.Disabled))" -ForegroundColor Green
    $r | Format-List Name, Disabled, BlockAccess, BlockAccessScope, `
        @{n='RestrictAccess';e={ $_.RestrictAccess | Out-String }}, `
        NotifyUser, GenerateAlert, GenerateIncidentReport, ReportSeverityLevel

    Write-Host "  --- Sensitive info types + THRESHOLDS ---" -ForegroundColor Magenta
    # ContentContainsSensitiveInformation is a nested array of hashtables; expand the important keys.
    $ccsi = $r.ContentContainsSensitiveInformation
    if ($ccsi) {
      foreach ($group in $ccsi) {
        # each group may itself contain a 'groups' array (newer schema) or be a flat SIT
        $sits = if ($group.groups) { $group.groups.sensitivetypes } elseif ($group.sensitivetypes) { $group.sensitivetypes } else { @($group) }
        foreach ($s in $sits) {
          [pscustomobject]@{
            Name           = $s.name
            MinCount       = $s.mincount
            MaxCount       = $s.maxcount
            Confidence     = $s.confidencelevel
            MinConfidence  = $s.mincount
            ClassifierType = $s.classifiertype
          } | Format-Table -AutoSize
        }
      }
    } else { Write-Host "   (no ContentContainsSensitiveInformation on this rule)" -ForegroundColor DarkGray }
  }
}

Write-Host "`n=================  SENSITIVE INFO TYPES referenced (confirm they exist)  =================" -ForegroundColor Cyan
"Credit Card Number","South Korea Resident Registration Number","South Korea Passport Number","South Korea Driver's License Number" | ForEach-Object {
  $sit = Get-DlpSensitiveInformationType -Identity $_ -ErrorAction SilentlyContinue
  if ($sit) { "{0,-45}  OK (Publisher: {1})" -f $sit.Name, $sit.Publisher } else { "{0,-45}  !! NOT FOUND under this exact name" -f $_ }
}

Write-Host "`n=================  INSIDER RISK MANAGEMENT (best effort)  =================" -ForegroundColor Cyan
# IRM is mostly portal-configured; only a few read cmdlets exist and may be absent in some tenants.
if (Get-Command Get-InsiderRiskPolicy -ErrorAction SilentlyContinue) {
  try {
    Get-InsiderRiskPolicy | Format-Table Name, Enabled, @{n='Template';e={$_.InsiderRiskScenario}}, WhenChanged -AutoSize
    foreach ($irp in (Get-InsiderRiskPolicy)) {
      Write-Host "`n----- IRM POLICY: $($irp.Name) -----" -ForegroundColor Yellow
      $irp | Format-List Name, Enabled, InsiderRiskScenario, Workload, `
          @{n='ThresholdConfig';e={ $_.ThresholdConfig | Out-String }}, WhenChanged
    }
  } catch { Write-Host "  IRM read failed: $($_.Exception.Message)" -ForegroundColor DarkGray }
} else {
  Write-Host "  Get-InsiderRiskPolicy not available in this session — inspect IRM in the portal instead:" -ForegroundColor DarkGray
  Write-Host "  https://purview.microsoft.com/insiderriskmgmt/insiderriskpolicies" -ForegroundColor DarkGray
}

Write-Host "`n=================  DONE — paste everything above back  =================" -ForegroundColor Cyan

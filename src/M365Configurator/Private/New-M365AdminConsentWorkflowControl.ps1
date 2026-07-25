#requires -Version 7.6

function New-M365AdminConsentWorkflowControl {
    <#
    .SYNOPSIS
        Builds the CON-2 (admin consent request workflow) control handler — a
        Graph singleton on the ADR-0013 contract (MCA-27; SCuBA MS.AAD.5.3v1).

    .DESCRIPTION
        Completes the consent story alongside CON-1: when user consent is
        restricted, this is the escape hatch that lets a user request admin
        review of an app instead of being flatly blocked.

        Mechanism (verified against Microsoft Learn, graph-rest-1.0,
        2026-07-25): `GET /policies/adminConsentRequestPolicy` returns
        `{ isEnabled, notifyReviewers, remindersEnabled,
        requestDurationInDays, reviewers[] }`, each reviewer
        `{ query, queryType }` (`queryRoot` is documented only for relative
        queries like `./manager` and is omitted here for static reviewer
        lists, per Microsoft's own example). The update is **PUT, not
        PATCH** — a full replace — so unlike every other singleton in this
        module, `Set` cannot merge a partial change: all five properties must
        be present in Desired, and it throws loud (NFR-6) rather than
        silently omitting one and resetting it to a default.

        A second guard: enabling the workflow with zero reviewers would
        create requests nobody ever reviews — a silent blackhole, not a
        working consent workflow — so `Set` refuses that combination too.

        No custom Compare: the flat five-key vocabulary fits the engine's
        default map-diff. Available on every tenant; no DependsOn.
        RequiredCapabilities deliberately empty (MCA-21/S9 retrofits it).

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'CON-2' -Provider 'graph' -Shape 'singleton' `
        -Title 'Admin consent request workflow' `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            $policy = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/adminConsentRequestPolicy'
            $reviewers = @(Get-M365MapValue $policy 'reviewers')

            @{
                isEnabled             = [bool] (Get-M365MapValue $policy 'isEnabled')
                notifyReviewers       = [bool] (Get-M365MapValue $policy 'notifyReviewers')
                remindersEnabled      = [bool] (Get-M365MapValue $policy 'remindersEnabled')
                requestDurationInDays = [int]  (Get-M365MapValue $policy 'requestDurationInDays')
                reviewerQueries       = @($reviewers | ForEach-Object { Get-M365MapValue $_ 'query' } | Sort-Object)
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $requiredKeys = @('isEnabled', 'notifyReviewers', 'remindersEnabled', 'requestDurationInDays', 'reviewerQueries')
            $missing = @($requiredKeys | Where-Object { -not (Test-M365MapHasKey $Desired $_) })
            if ($missing.Count -gt 0) {
                throw 'CON-2 requires the full settings map (isEnabled, notifyReviewers, remindersEnabled, requestDurationInDays, reviewerQueries) because the Graph update is a full-replace PUT.'
            }

            $isEnabled = [bool] (Get-M365MapValue $Desired 'isEnabled')
            $reviewerQueries = @(Get-M365MapValue $Desired 'reviewerQueries' | Sort-Object)

            if ($isEnabled -and $reviewerQueries.Count -eq 0) {
                throw 'CON-2 refuses to enable the admin consent workflow with zero reviewers — that would silently blackhole every request.'
            }

            $body = @{
                isEnabled             = $isEnabled
                notifyReviewers       = [bool] (Get-M365MapValue $Desired 'notifyReviewers')
                remindersEnabled      = [bool] (Get-M365MapValue $Desired 'remindersEnabled')
                requestDurationInDays = [int]  (Get-M365MapValue $Desired 'requestDurationInDays')
                reviewers             = @(foreach ($query in $reviewerQueries) { @{ query = $query; queryType = 'MicrosoftGraph' } })
            }

            Invoke-M365GraphRequest -Method PUT -Uri 'v1.0/policies/adminConsentRequestPolicy' -Body $body
            @{ Id = 'CON-2'; Outcome = 'Applied' }
        }
}

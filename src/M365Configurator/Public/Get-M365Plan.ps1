#requires -Version 7.6

function Get-M365Plan {
    <#
    .SYNOPSIS
        Computes a dry-run plan — what a profile would change against the connected
        tenant — as a readable, dependency-ordered set of plan items with one
        overall pass / needs-attention signal (MCA-17; FR-8, NFR-6, NFR-9; ADR-0013).

    .DESCRIPTION
        The provider-agnostic core of the change engine. For each control in the
        profile it: resolves the handler from the registry; checks capability gates;
        reads current tenant state via the handler's Get seam; compares it to the
        profile's desired settings; and emits a plan item — WITHOUT mutating anything
        (FR-8). It never calls a handler's Set.

        Comparison defaults to the canonical form (ADR-0008): a field differs when its
        canonical JSON differs, so "did anything change?" is byte-stable (NFR-9). A
        handler may override with its own Compare for shapes the default can't express
        (e.g. the preset rule-state check); the engine validates the returned Action
        against the plan enum and fails loud on anything else (NFR-6).

        Ordering honours DependsOn: dependencies are planned before their dependents,
        via a deterministic, cycle-detecting sort (a cycle or a DependsOn on an
        unregistered control fails loud — NFR-6). Only DependsOn targets that are also
        in this profile constrain ordering.

        The registry is an injected seam (default: Get-M365ControlRegistry) so the
        engine is unit-testable with in-memory fake controls and no tenant.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Plan'): ProfileName, Signal
        ('Pass' | 'NeedsAttention'), Summary (per-Action counts), Items[].
        Each item: Id, Title, Provider, Action
        ('NoChange' | 'Create' | 'Update' | 'Blocked' | 'Unsupported'), Changes[], Gate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Profile')]
        [AllowNull()]
        $InputObject,

        # The connected session, passed to each handler's Get seam. May be $null in
        # tests that supply fake controls whose Get ignores it.
        $Session,

        # Injected control set; defaults to the real registry.
        [AllowNull()]
        $Registry
    )

    $validActions = @('NoChange', 'Create', 'Update', 'Blocked', 'Unsupported')

    if ($null -eq $Registry) { $Registry = Get-M365ControlRegistry }
    $handlers = @{}
    foreach ($handler in @($Registry)) { $handlers[$handler.Id] = $handler }

    # --- read profile controls into ordered (id, desired, handler) records --------
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($pc in @(Get-M365MapValue $InputObject 'controls')) {
        $id = [string] (Get-M365MapValue $pc 'id')
        $records.Add([pscustomobject]@{
                Id      = $id
                Desired = Get-M365MapValue $pc 'settings'
                Handler = if ($handlers.ContainsKey($id)) { $handlers[$id] } else { $null }
            })
    }

    # Duplicate control ids in a profile would silently collapse during ordering
    # (last-wins) and drop a control's intent — reject loudly instead (NFR-6).
    $dupeIds = @($records.ToArray() | Group-Object -Property Id | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupeIds.Count -gt 0) {
        throw "Profile declares duplicate control id(s): $($dupeIds -join ', ')."
    }

    # A handler's DependsOn must reference a real registered control (author-side
    # invariant — a typo is a packaging fault, not a silent no-op; NFR-6).
    foreach ($rec in $records) {
        if ($null -ne $rec.Handler) {
            foreach ($dep in @($rec.Handler.DependsOn)) {
                if (-not $handlers.ContainsKey($dep)) {
                    throw "Control '$($rec.Id)' declares DependsOn '$dep', which is not a registered control."
                }
            }
        }
    }

    # --- deterministic, cycle-detecting dependency order (Kahn) -------------------
    $inPlan   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $recById  = @{}
    $indegree = @{}
    foreach ($rec in $records) { [void] $inPlan.Add($rec.Id); $recById[$rec.Id] = $rec; $indegree[$rec.Id] = 0 }

    $dependents = @{}   # dependency id -> ids that depend on it (present in this plan)
    foreach ($rec in $records) {
        if ($null -ne $rec.Handler) {
            foreach ($dep in @($rec.Handler.DependsOn)) {
                if ($inPlan.Contains($dep)) {
                    $indegree[$rec.Id]++
                    if (-not $dependents.ContainsKey($dep)) { $dependents[$dep] = [System.Collections.Generic.List[string]]::new() }
                    $dependents[$dep].Add($rec.Id)
                }
            }
        }
    }

    $ready = [System.Collections.Generic.List[string]]::new()
    foreach ($rec in $records) { if ($indegree[$rec.Id] -eq 0) { $ready.Add($rec.Id) } }  # profile order

    $ordered = [System.Collections.Generic.List[object]]::new()
    while ($ready.Count -gt 0) {
        $id = $ready[0]; $ready.RemoveAt(0)
        $ordered.Add($recById[$id])
        if ($dependents.ContainsKey($id)) {
            foreach ($dependent in $dependents[$id]) {
                $indegree[$dependent]--
                if ($indegree[$dependent] -eq 0) { $ready.Add($dependent) }
            }
        }
    }
    if ($ordered.Count -ne $records.Count) {
        $cyclic = @($records.ToArray() | Where-Object { $indegree[$_.Id] -gt 0 } | ForEach-Object { $_.Id })
        throw "Control dependency cycle detected among: $($cyclic -join ', ')."
    }

    # --- build a plan item per record, in dependency order -----------------------
    $items   = [System.Collections.Generic.List[object]]::new()
    $summary = [ordered]@{ NoChange = 0; Create = 0; Update = 0; Blocked = 0; Unsupported = 0 }

    foreach ($rec in $ordered) {
        $action  = 'NoChange'
        $changes = @()
        $gate    = $null
        $title   = $rec.Id
        $provider = $null

        if ($null -eq $rec.Handler) {
            # No provider knows this control id — surface it, never silently skip.
            $action = 'Unsupported'
            $gate   = "no control handler is registered for id '$($rec.Id)'"
        }
        else {
            $title    = $rec.Handler.Title
            $provider = $rec.Handler.Provider

            # capability gate — surfaced in dry-run, never half-applied (MCA-21).
            $required = @($rec.Handler.RequiredCapabilities)
            $sessionCaps = @(if ($null -ne $Session) { Get-M365MapValue $Session 'Capabilities' })
            $missing = @($required | Where-Object { $_ -notin $sessionCaps })

            if ($missing.Count -gt 0) {
                $action = 'Blocked'
                $gate   = "requires capability: $($missing -join ', ')"
            }
            else {
                $current = & $rec.Handler.Get $Session

                if ($null -ne $rec.Handler.Compare) {
                    $result = & $rec.Handler.Compare $rec.Desired $current
                    $action  = [string] (Get-M365MapValue $result 'Action')
                    # A Compare that omits Changes must yield an empty list, not @($null):
                    # the renderer walks Changes and a $null entry crashes on .Path (NFR-6/NFR-9).
                    $changes = @(Get-M365MapValue $result 'Changes' | Where-Object { $null -ne $_ })
                    if ($action -notin $validActions) {
                        throw "Control '$($rec.Id)' Compare returned Action '$action', which is not one of: $($validActions -join ', ')."
                    }
                }
                else {
                    # The default compare only understands a settings MAP; a non-map
                    # desired (e.g. an array of policies for a collection control) needs
                    # a custom Compare — silently reporting NoChange would be a dangerous
                    # false pass, so fail loud instead (NFR-6).
                    if ($null -ne $rec.Desired -and
                        $rec.Desired -isnot [System.Collections.IDictionary] -and
                        $rec.Desired -isnot [System.Management.Automation.PSCustomObject]) {
                        throw "Control '$($rec.Id)' has a non-map desired shape but no Compare; the default comparison only supports a settings map — provide a Compare handler."
                    }
                    $changes = @(Get-M365ControlChange -Desired $rec.Desired -Current $current)
                    $action  = if ($changes.Count -gt 0) { 'Update' } else { 'NoChange' }
                }
            }
        }

        $summary[$action]++
        $items.Add([pscustomobject]@{
                PSTypeName = 'M365Configurator.PlanItem'
                Id       = $rec.Id
                Title    = $title
                Provider = $provider
                Action   = $action
                Changes  = @($changes)
                Gate     = $gate
            })
    }

    $signal = if ($summary.Create -or $summary.Update -or $summary.Blocked -or $summary.Unsupported) { 'NeedsAttention' } else { 'Pass' }

    [pscustomobject]@{
        PSTypeName  = 'M365Configurator.Plan'
        ProfileName = [string] (Get-M365MapValue $InputObject 'name')
        Signal      = $signal
        Summary     = [pscustomobject] $summary
        Items       = $items.ToArray()
    }
}

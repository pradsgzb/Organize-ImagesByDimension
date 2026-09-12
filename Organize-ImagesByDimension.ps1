#requires -Version 5.1
<#
.SYNOPSIS
    High-performance, resumable image organizer for Windows PowerShell.

.DESCRIPTION
    Organizes image files into folders by either exact pixel dimensions or the
    nearest configured aspect ratio.

    Default behavior:
      - Group by exact dimensions.
      - Folder names DO NOT include file counts.
      - Small-group routing to Others is OFF (MinFilesPerGroup = 0).
      - CSV export is OFF.
      - Resume/recovery is ON.
      - Common image formats are read with a fast header parser instead of
        fully decoding the image.

    Dimension folder examples:
        768 x 1376
        1920 x 1080

    Dimension folder examples with -AddCountToFolderName:
        100 - 768 x 1376
        25 - 1920 x 1080

    Ratio folder examples:
        Ratio 4x5
        Ratio 16x9

    Ratio folder examples with -AddCountToFolderName:
        250 - Ratio 4x5
        90 - Ratio 16x9

    IMPORTANT:
      Windows folder names cannot contain ":" so ratio "4:5" is represented
      on disk as "Ratio 4x5".

    Performance design:
      - Uses System.IO streaming enumeration.
      - Uses a compiled C# header reader for JPEG, PNG, GIF, BMP, TIFF and WebP.
      - Avoids Group-Object and large in-memory image inventories.
      - Uses a compact on-disk manifest only when folder counts, small-group
        routing or CSV export require a pre-inventory pass.
      - Throttles progress output to avoid console I/O becoming a bottleneck.
      - Uses deterministic collision names rather than repeatedly probing
        "_1", "_2", ... from the beginning.

    Recovery design:
      - A small state file is maintained while a real run is active.
      - Direct organization resumes from the most recently checkpointed
        directory.
      - Manifest-based organization resumes from the most recently
        checkpointed manifest row.
      - Work between checkpoints is idempotent: already-moved files are safely
        recognized/skipped on restart.
      - Temporary state files are deleted after a successful run.

.PARAMETER InputPath
    Root folder containing images to organize.

.PARAMETER Recurse
    Include all subdirectories present when the run starts.

    The script snapshots the directory list before it starts moving files.
    Therefore, newly-created destination folders are not accidentally scanned
    again during the same run.

.PARAMETER GroupByDimension
    Explicitly select exact dimension grouping.

    This is the default mode and normally does not need to be specified.

.PARAMETER GroupByRatio
    Group by the nearest configured width:height ratio instead of exact
    dimensions.

    This parameter is in a mutually-exclusive PowerShell parameter set, so it
    cannot be combined with -GroupByDimension.

.PARAMETER Ratios
    Aspect ratios available to -GroupByRatio.

    Ratios are normalized automatically (for example 2:4 becomes 1:2).

    Default ratios:
        1:1, 1:2, 2:1, 1:3, 3:1, 2:3, 3:2,
        3:4, 4:3, 4:5, 5:4, 9:16, 16:9

    Nearest-ratio matching uses logarithmic ratio distance. This treats portrait
    and landscape ratios consistently and avoids bias toward numerically larger
    width/height values.

.PARAMETER AddCountToFolderName
    Prefix destination folder names with the total image count for that group.

    OFF by default.

    When enabled, the script first builds a read-only inventory so counts are
    known before any file is moved.

.PARAMETER MinFilesPerGroup
    Minimum number of images required to keep a separate group folder.

    Default: 0 (disabled). Must be a non-negative integer.

    For example, -MinFilesPerGroup 3 puts groups containing 1 or 2 images
    directly into InputPath\Others. Groups containing exactly 3 or more images
    keep their normal dimension folders. With -GroupByRatio, the threshold
    applies to each selected ratio group instead of each exact dimension.

    Counts are calculated before any images move, using successfully read
    images in the selected scan scope. Add -Recurse to include images already
    inside dimension folders, Others, or other subdirectories. Counts include
    all scanned directories together, not each directory separately.

    Others is always named exactly 'Others', even with -AddCountToFolderName.
    The CSV Group column continues to show each image's original dimension
    or ratio group. Existing filename collision handling also applies in Others.

.PARAMETER ExportCsv
    Produce ImageMetadata.csv containing:
      - FileName
      - OriginalFullPath
      - WidthPixels
      - HeightPixels
      - HorizontalPPI
      - VerticalPPI
      - XPComment
      - LastModifiedDateTime
      - CreationDateTime
      - GroupingMode
      - Group

    OFF by default.

    The default CSV location is the current PowerShell working directory.
    Use -CsvPath to override it.

.PARAMETER CsvPath
    Optional CSV output path. Supplying -CsvPath automatically enables CSV
    export.

.PARAMETER Recurse
    Recursively scans the directory snapshot.

.PARAMETER LogLevel
    Console log threshold:
      Error, Warn, Info, Debug

    Errors are red. Warnings are yellow. Success messages are green.
    Informational messages are cyan. Debug messages are dark gray.

.PARAMETER LogEachFile
    Write one green success line for every moved file.

    OFF by default because per-file console output can materially reduce
    throughput when processing hundreds of thousands or millions of files.

.PARAMETER ProgressIntervalSeconds
    Minimum interval between detailed progress refreshes/log messages.

    Default: 5 seconds.

.PARAMETER CheckpointEvery
    Approximate number of processed image records between durable checkpoints.

    Default: 500.

    A larger value increases throughput. A smaller value minimizes repeated
    work after an unexpected interruption.

.PARAMETER Force
    If a destination file with the same name already exists, replace it.

    Without -Force, the script creates a deterministic collision-safe filename.

.PARAMETER DisableResume
    Disable persistent recovery state for this run.

    Resume is ON by default.

.PARAMETER ResetState
    Delete an incomplete recovery state created by a prior run.

    Use this when intentionally changing grouping options after an interrupted
    run.

.PARAMETER IncludeExtensions
    File extensions treated as images.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images"

    Groups by exact dimensions. Folder counts are NOT included.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -Recurse -AddCountToFolderName

    Recursively groups by dimensions and prefixes each target folder with the
    final count.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -GroupByRatio

    Groups each image into the nearest standard aspect-ratio folder.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -GroupByRatio -Ratios "1:1","2:3","3:2","4:5","5:4","9:16","16:9"

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -Recurse -ExportCsv

    Produces ImageMetadata.csv in the current PowerShell working directory.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -MinFilesPerGroup 3

    Moves dimension groups with fewer than 3 images into D:\Images\Others.
    Groups with exactly 3 or more images keep their dimension folders.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -Recurse -MinFilesPerGroup 3 -WhatIf

    Previews small-group routing, including images in existing subfolders.

.EXAMPLE
    .\Organize-ImagesByDimension.ps1 -InputPath "D:\Images" -WhatIf

    Scans and reports what would be moved without moving image files.
#>

[CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = 'Medium',
    DefaultParameterSetName = 'Dimension'
)]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter()]
    [switch]$Recurse,

    [Parameter(ParameterSetName = 'Dimension')]
    [switch]$GroupByDimension,

    [Parameter(Mandatory = $true, ParameterSetName = 'Ratio')]
    [switch]$GroupByRatio,

    [Parameter(ParameterSetName = 'Ratio')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Ratios = @(
        '1:1',
        '1:2', '2:1',
        '1:3', '3:1',
        '2:3', '3:2',
        '3:4', '4:3',
        '4:5', '5:4',
        '9:16', '16:9'
    ),

    [Parameter()]
    [switch]$AddCountToFolderName,

    [Parameter()]
    [ValidateRange(0, 2147483647)]
    [int]$MinFilesPerGroup = 0,

    [Parameter()]
    [switch]$ExportCsv,

    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [ValidateSet('Error', 'Warn', 'Info', 'Debug')]
    [string]$LogLevel = 'Info',

    [Parameter()]
    [switch]$LogEachFile,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int]$ProgressIntervalSeconds = 5,

    [Parameter()]
    [ValidateRange(1, 1000000)]
    [int]$CheckpointEvery = 500,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$DisableResume,

    [Parameter()]
    [switch]$ResetState,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$IncludeExtensions = @(
        '.jpg', '.jpeg', '.jpe', '.jfif',
        '.png',
        '.bmp',
        '.gif',
        '.tif', '.tiff',
        '.webp'
    )
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $script:MainCmdlet = $PSCmdlet
    $script:RunStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:LastProgressUtc = [DateTime]::UtcNow.AddYears(-1)
    $script:LastProgressMoved = 0L
    $script:TargetDirectoryCache = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:ExtendedMetadataWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $severityRank = @{
        'Debug'   = 0
        'Info'    = 1
        'Success' = 1
        'Warn'    = 2
        'Error'   = 3
    }
    $selectedRank = $severityRank[$LogLevel]

    function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $true)]
            [ValidateSet('Debug', 'Info', 'Success', 'Warn', 'Error')]
            [string]$Severity
        )

        if ($severityRank[$Severity] -lt $selectedRank) {
            return
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $prefix = '{0} [{1}]' -f $timestamp, $Severity.ToUpperInvariant()

        switch ($Severity) {
            'Debug'   { Write-Host "$prefix $Message" -ForegroundColor DarkGray }
            'Info'    { Write-Host "$prefix $Message" -ForegroundColor Cyan }
            'Success' { Write-Host "$prefix $Message" -ForegroundColor Green }
            'Warn'    { Write-Host "$prefix $Message" -ForegroundColor Yellow }
            'Error'   { Write-Host "$prefix $Message" -ForegroundColor Red }
        }
    }

    function Write-ProgressStatus {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Activity,

            [Parameter(Mandatory = $true)]
            [string]$Status,

            [long]$Current = 0,

            [long]$Total = 0,

            [switch]$ForceRefresh,

            [switch]$SuccessProgress
        )

        $now = [DateTime]::UtcNow
        if (-not $ForceRefresh) {
            $elapsedSinceLast = ($now - $script:LastProgressUtc).TotalSeconds
            if ($elapsedSinceLast -lt $ProgressIntervalSeconds) {
                return
            }
        }

        if ($Total -gt 0) {
            $percent = [Math]::Min(100.0, [Math]::Max(0.0, (($Current * 100.0) / $Total)))
            Write-Progress -Id 1 -Activity $Activity -Status $Status -PercentComplete $percent
        }
        else {
            Write-Progress -Id 1 -Activity $Activity -Status $Status -PercentComplete -1
        }

        if ($SuccessProgress) {
            Write-Log -Message $Status -Severity Success
        }
        else {
            Write-Log -Message $Status -Severity Info
        }

        $script:LastProgressUtc = $now
    }

    function Resolve-InputDirectory {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        try {
            $resolved = (Resolve-Path -LiteralPath $Path).Path
        }
        catch {
            throw "The specified InputPath does not exist or is inaccessible: $Path"
        }

        if (-not [System.IO.Directory]::Exists($resolved)) {
            throw "InputPath must be a directory: $resolved"
        }

        return [System.IO.Path]::GetFullPath($resolved)
    }

    function Resolve-OutputFilePath {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        if ([System.IO.Path]::IsPathRooted($Path)) {
            return [System.IO.Path]::GetFullPath($Path)
        }

        $basePath = (Get-Location).Path
        return [System.IO.Path]::GetFullPath((Join-Path -Path $basePath -ChildPath $Path))
    }

    function ConvertTo-Base64Utf8 {
        [CmdletBinding()]
        param (
            [AllowEmptyString()]
            [string]$Value
        )

        if ($null -eq $Value) {
            $Value = ''
        }

        return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
    }

    function ConvertFrom-Base64Utf8 {
        [CmdletBinding()]
        param (
            [AllowEmptyString()]
            [string]$Value
        )

        if ([string]::IsNullOrEmpty($Value)) {
            return ''
        }

        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
    }

    function Get-Sha256Hex {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Value
        )

        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
            $hash = $sha.ComputeHash($bytes)
            return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function Get-GreatestCommonDivisor {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [int]$A,

            [Parameter(Mandatory = $true)]
            [int]$B
        )

        $aValue = [Math]::Abs($A)
        $bValue = [Math]::Abs($B)

        while ($bValue -ne 0) {
            $temp = $aValue % $bValue
            $aValue = $bValue
            $bValue = $temp
        }

        return $aValue
    }

    function Get-NormalizedRatioTargets {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string[]]$RatioSpecs
        )

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $targets = [System.Collections.Generic.List[object]]::new()

        foreach ($ratioSpec in $RatioSpecs) {
            if ($ratioSpec -notmatch '^\s*(\d+)\s*:\s*(\d+)\s*$') {
                throw "Invalid ratio '$ratioSpec'. Ratios must use positive integer W:H syntax, for example 4:5."
            }

            $widthPart = [int]$Matches[1]
            $heightPart = [int]$Matches[2]

            if ($widthPart -le 0 -or $heightPart -le 0) {
                throw "Invalid ratio '$ratioSpec'. Width and height must both be greater than zero."
            }

            $gcd = Get-GreatestCommonDivisor -A $widthPart -B $heightPart
            $normalizedWidth = [int]($widthPart / $gcd)
            $normalizedHeight = [int]($heightPart / $gcd)
            $label = '{0}:{1}' -f $normalizedWidth, $normalizedHeight

            if (-not $seen.Add($label)) {
                continue
            }

            $ratioValue = [double]$normalizedWidth / [double]$normalizedHeight
            $targets.Add([PSCustomObject]@{
                Label    = $label
                LogValue = [Math]::Log($ratioValue)
            })
        }

        if ($targets.Count -eq 0) {
            throw 'At least one valid aspect ratio is required.'
        }

        return $targets.ToArray()
    }

    function Get-GroupKey {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [int]$Width,

            [Parameter(Mandatory = $true)]
            [int]$Height
        )

        if ($Width -le 0 -or $Height -le 0) {
            throw "Invalid image dimensions: ${Width}x${Height}."
        }

        if ($script:GroupingMode -eq 'Dimension') {
            return '{0} x {1}' -f $Width, $Height
        }

        $actualLog = [Math]::Log(([double]$Width / [double]$Height))
        $bestLabel = $null
        $bestDistance = [double]::MaxValue

        for ($i = 0; $i -lt $script:RatioTargets.Count; $i++) {
            $candidate = $script:RatioTargets[$i]
            $distance = [Math]::Abs($actualLog - $candidate.LogValue)

            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $bestLabel = $candidate.Label
            }
        }

        return $bestLabel
    }

    function Get-TargetFolderName {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$GroupKey,

            [System.Collections.Generic.Dictionary[string,long]]$GroupCounts
        )

        if ($AddCountToFolderName -or $MinFilesPerGroup -gt 0) {
            if ($null -eq $GroupCounts -or -not $GroupCounts.ContainsKey($GroupKey)) {
                throw "Count for group '$GroupKey' is unavailable. Recovery state may be incomplete or corrupted."
            }

            # Use the original inventory count, including after an interrupted
            # run. Exactly the threshold keeps its normal group folder.
            if ($MinFilesPerGroup -gt 0 -and $GroupCounts[$GroupKey] -lt $MinFilesPerGroup) {
                return 'Others'
            }
        }

        if ($script:GroupingMode -eq 'Ratio') {
            $baseName = 'Ratio {0}' -f $GroupKey.Replace(':', 'x')
        }
        else {
            $baseName = $GroupKey
        }

        if (-not $AddCountToFolderName) {
            return $baseName
        }

        return '{0} - {1}' -f $GroupCounts[$GroupKey], $baseName
    }

    function Test-SamePath {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$PathA,

            [Parameter(Mandatory = $true)]
            [string]$PathB
        )

        $a = [System.IO.Path]::GetFullPath($PathA).TrimEnd('\', '/')
        $b = [System.IO.Path]::GetFullPath($PathB).TrimEnd('\', '/')
        return [System.StringComparer]::OrdinalIgnoreCase.Equals($a, $b)
    }

    function Get-DeterministicCollisionBasePath {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourcePath,

            [Parameter(Mandatory = $true)]
            [string]$NominalDestinationPath
        )

        $directory = [System.IO.Path]::GetDirectoryName($NominalDestinationPath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($NominalDestinationPath)
        $extension = [System.IO.Path]::GetExtension($NominalDestinationPath)
        $hash = (Get-Sha256Hex -Value $SourcePath).Substring(0, 12)

        return [System.IO.Path]::Combine(
            $directory,
            ('{0}__{1}{2}' -f $baseName, $hash, $extension)
        )
    }

    function Get-CollisionSafeDestinationPath {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourcePath,

            [Parameter(Mandatory = $true)]
            [string]$NominalDestinationPath
        )

        $baseCandidate = Get-DeterministicCollisionBasePath -SourcePath $SourcePath -NominalDestinationPath $NominalDestinationPath

        if (-not [System.IO.File]::Exists($baseCandidate)) {
            return $baseCandidate
        }

        $directory = [System.IO.Path]::GetDirectoryName($baseCandidate)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseCandidate)
        $extension = [System.IO.Path]::GetExtension($baseCandidate)

        for ($counter = 2; $counter -lt [int]::MaxValue; $counter++) {
            $candidate = [System.IO.Path]::Combine(
                $directory,
                ('{0}_{1}{2}' -f $baseName, $counter, $extension)
            )

            if (-not [System.IO.File]::Exists($candidate)) {
                return $candidate
            }
        }

        throw "Unable to generate a unique destination filename for '$SourcePath'."
    }

    function Test-RecoveredDestinationExists {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourcePath,

            [Parameter(Mandatory = $true)]
            [string]$NominalDestinationPath
        )

        if ([System.IO.File]::Exists($NominalDestinationPath)) {
            return $true
        }

        $baseCandidate = Get-DeterministicCollisionBasePath -SourcePath $SourcePath -NominalDestinationPath $NominalDestinationPath
        if ([System.IO.File]::Exists($baseCandidate)) {
            return $true
        }

        $directory = [System.IO.Path]::GetDirectoryName($baseCandidate)
        if (-not [System.IO.Directory]::Exists($directory)) {
            return $false
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseCandidate)
        $extension = [System.IO.Path]::GetExtension($baseCandidate)
        $pattern = '{0}_*{1}' -f $baseName, $extension

        try {
            foreach ($match in [System.IO.Directory]::EnumerateFiles($directory, $pattern, [System.IO.SearchOption]::TopDirectoryOnly)) {
                if ([System.IO.File]::Exists($match)) {
                    return $true
                }
            }
        }
        catch {
            return $false
        }

        return $false
    }

    function Save-RecoveryState {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [psobject]$State,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        if ($script:IsWhatIfRun -or $DisableResume) {
            return
        }

        # IMPORTANT (Windows PowerShell 5.1 / .NET Framework compatibility):
        # Do not call File.Replace(..., $null) for the backup filename.
        # PowerShell can bind $null as an empty string, causing:
        #   "The path is empty. (Parameter 'path')"
        # Use a real backup path for the atomic replace and fall back to an
        # overwrite copy on file systems/runtimes where File.Replace is not
        # available or cannot complete.
        $State.LastCheckpointUtc = [DateTime]::UtcNow.ToString('o')
        $json = $State | ConvertTo-Json -Depth 8
        $tempPath = "$Path.tmp"
        $backupPath = "$Path.bak"
        $encoding = [System.Text.UTF8Encoding]::new($false)

        try {
            $parentPath = [System.IO.Path]::GetDirectoryName($Path)
            if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not [System.IO.Directory]::Exists($parentPath)) {
                [System.IO.Directory]::CreateDirectory($parentPath) | Out-Null
            }

            # A stale temp file can remain after a power loss or terminated
            # process. The per-root lock prevents a concurrent organizer from
            # legitimately owning this temp file during this run.
            if ([System.IO.File]::Exists($tempPath)) {
                [System.IO.File]::Delete($tempPath)
            }

            [System.IO.File]::WriteAllText($tempPath, $json, $encoding)

            if ([System.IO.File]::Exists($Path)) {
                $atomicReplaceError = $null

                try {
                    # File.Replace requires a non-empty backup path under some
                    # Windows PowerShell/.NET Framework combinations.
                    if ([System.IO.File]::Exists($backupPath)) {
                        [System.IO.File]::Delete($backupPath)
                    }

                    [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
                }
                catch {
                    $atomicReplaceError = $_.Exception.Message

                    # Compatibility fallback. This is not as strong as the
                    # same-volume atomic replace, but it works on file systems
                    # that do not support File.Replace and preserves resumable
                    # behavior instead of aborting the entire organization run.
                    try {
                        [System.IO.File]::Copy($tempPath, $Path, $true)
                        [System.IO.File]::Delete($tempPath)
                    }
                    catch {
                        throw "Atomic state replacement failed: $atomicReplaceError. Fallback overwrite failed: $($_.Exception.Message)"
                    }
                }

                # The backup is needed only while Replace is in progress.
                # Cleanup failure is intentionally non-fatal; a .bak file is
                # safer than aborting image processing after a valid checkpoint.
                try {
                    if ([System.IO.File]::Exists($backupPath)) {
                        [System.IO.File]::Delete($backupPath)
                    }
                }
                catch {
                    Write-Log -Message "Could not remove recovery-state backup '$backupPath': $($_.Exception.Message)" -Severity Debug
                }
            }
            else {
                [System.IO.File]::Move($tempPath, $Path)
            }
        }
        catch {
            $writeError = $_.Exception.Message

            try {
                if ([System.IO.File]::Exists($tempPath)) {
                    [System.IO.File]::Delete($tempPath)
                }
            }
            catch {
                # Best effort cleanup only.
            }

            throw "Unable to write recovery state '$Path': $writeError"
        }
    }

    function Read-RecoveryState {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        try {
            $raw = [System.IO.File]::ReadAllText($Path)
            return $raw | ConvertFrom-Json
        }
        catch {
            throw "Recovery state '$Path' is unreadable. Use -ResetState only after verifying that no other organizer run is active. Details: $($_.Exception.Message)"
        }
    }

    function Remove-FileIfPresent {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        try {
            if ([System.IO.File]::Exists($Path)) {
                [System.IO.File]::Delete($Path)
            }
        }
        catch {
            Write-Log -Message "Could not delete temporary file '$Path': $($_.Exception.Message)" -Severity Warn
        }
    }

    function Build-DirectorySnapshot {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$RootPath,

            [Parameter(Mandatory = $true)]
            [string]$SnapshotPath,

            [Parameter(Mandatory = $true)]
            [bool]$Recursive
        )

        $encoding = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($SnapshotPath, $false, $encoding, 65536)
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push($RootPath)
        $directoryCount = 0L
        $failedDirectories = 0L

        try {
            while ($stack.Count -gt 0) {
                $directory = $stack.Pop()
                $writer.WriteLine((ConvertTo-Base64Utf8 -Value $directory))
                $directoryCount++

                Write-ProgressStatus `
                    -Activity 'Discovering directories' `
                    -Status ("Directories discovered: {0:N0} | inaccessible: {1:N0}" -f $directoryCount, $failedDirectories) `
                    -Current $directoryCount

                if (-not $Recursive) {
                    continue
                }

                try {
                    foreach ($subdirectory in [System.IO.Directory]::EnumerateDirectories($directory)) {
                        try {
                            $attributes = [System.IO.File]::GetAttributes($subdirectory)
                            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                                Write-Log -Message "Skipping reparse point/junction to avoid recursion loops: $subdirectory" -Severity Debug
                                continue
                            }

                            $stack.Push($subdirectory)
                        }
                        catch {
                            $failedDirectories++
                            Write-Log -Message "Cannot inspect directory '$subdirectory': $($_.Exception.Message)" -Severity Error
                        }
                    }
                }
                catch {
                    $failedDirectories++
                    Write-Log -Message "Cannot enumerate subdirectories of '$directory': $($_.Exception.Message)" -Severity Error
                }
            }
        }
        finally {
            $writer.Flush()
            $writer.Dispose()
        }

        Write-ProgressStatus `
            -Activity 'Discovering directories' `
            -Status ("Directory snapshot complete: {0:N0} directories." -f $directoryCount) `
            -Current $directoryCount `
            -Total $directoryCount `
            -ForceRefresh

        Write-Progress -Id 1 -Activity 'Discovering directories' -Completed

        return [PSCustomObject]@{
            DirectoryCount    = $directoryCount
            FailedDirectories = $failedDirectories
        }
    }

    function Read-DirectorySnapshotLine {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$EncodedLine
        )

        return ConvertFrom-Base64Utf8 -Value $EncodedLine
    }

    function Get-ExtendedImageMetadata {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$FilePath
        )

        $fileStream = $null
        $image = $null

        try {
            $fileStream = [System.IO.FileStream]::new(
                $FilePath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete),
                65536,
                [System.IO.FileOptions]::SequentialScan
            )

            $image = [System.Drawing.Image]::FromStream($fileStream, $false, $false)

            $xPpi = $null
            $yPpi = $null
            try {
                if ($image.HorizontalResolution -gt 0) {
                    $xPpi = [Math]::Round([double]$image.HorizontalResolution, 3)
                }

                if ($image.VerticalResolution -gt 0) {
                    $yPpi = [Math]::Round([double]$image.VerticalResolution, 3)
                }
            }
            catch {
                # PPI is optional metadata. Leave it blank when unavailable.
            }

            $xpComment = ''
            try {
                foreach ($propertyItem in $image.PropertyItems) {
                    if ($propertyItem.Id -eq 40092) { # 0x9C9C = XPComment
                        $xpComment = [Text.Encoding]::Unicode.GetString($propertyItem.Value).Trim([char]0)
                        break
                    }
                }
            }
            catch {
                # XPComment is optional metadata. Leave it blank when unavailable.
            }

            return [PSCustomObject]@{
                Width      = [int]$image.Width
                Height     = [int]$image.Height
                Xppi       = $xPpi
                Yppi       = $yPpi
                XPComment  = $xpComment
                UsedGdiPlus = $true
            }
        }
        finally {
            if ($null -ne $image) {
                $image.Dispose()
            }

            if ($null -ne $fileStream) {
                $fileStream.Dispose()
            }
        }
    }

    function Get-InventoryImageMetadata {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$FilePath,

            [Parameter(Mandatory = $true)]
            [bool]$NeedExtendedMetadata
        )

        if ($NeedExtendedMetadata) {
            try {
                return Get-ExtendedImageMetadata -FilePath $FilePath
            }
            catch {
                $extension = [System.IO.Path]::GetExtension($FilePath)
                if ($script:ExtendedMetadataWarnings.Add($extension)) {
                    Write-Log -Message "Extended PPI/XPComment metadata is unavailable through System.Drawing for '$extension'. Fast dimensions will still be recorded. Example: $($_.Exception.Message)" -Severity Warn
                }

                $size = [ImageOrganizer.FastImageReader]::Read($FilePath)
                return [PSCustomObject]@{
                    Width       = [int]$size.Width
                    Height      = [int]$size.Height
                    Xppi        = $null
                    Yppi        = $null
                    XPComment   = ''
                    UsedGdiPlus = $false
                }
            }
        }

        $fastSize = [ImageOrganizer.FastImageReader]::Read($FilePath)
        return [PSCustomObject]@{
            Width       = [int]$fastSize.Width
            Height      = [int]$fastSize.Height
            Xppi        = $null
            Yppi        = $null
            XPComment   = ''
            UsedGdiPlus = $false
        }
    }

    function Format-InvariantNullableNumber {
        [CmdletBinding()]
        param (
            $Value
        )

        if ($null -eq $Value) {
            return ''
        }

        return [string]::Format(
            [Globalization.CultureInfo]::InvariantCulture,
            '{0:0.###}',
            [double]$Value
        )
    }

    function New-ManifestLine {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$FilePath,

            [Parameter(Mandatory = $true)]
            [int]$Width,

            [Parameter(Mandatory = $true)]
            [int]$Height,

            [Parameter(Mandatory = $true)]
            [string]$GroupKey,

            $Xppi,

            $Yppi,

            [AllowEmptyString()]
            [string]$XPComment,

            [Parameter(Mandatory = $true)]
            [DateTime]$LastWriteTime,

            [Parameter(Mandatory = $true)]
            [DateTime]$CreationTime
        )

        $fields = @(
            (ConvertTo-Base64Utf8 -Value $FilePath),
            $Width.ToString([Globalization.CultureInfo]::InvariantCulture),
            $Height.ToString([Globalization.CultureInfo]::InvariantCulture),
            $GroupKey,
            (Format-InvariantNullableNumber -Value $Xppi),
            (Format-InvariantNullableNumber -Value $Yppi),
            (ConvertTo-Base64Utf8 -Value $XPComment),
            $LastWriteTime.ToString('o', [Globalization.CultureInfo]::InvariantCulture),
            $CreationTime.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        )

        return [string]::Join("`t", $fields)
    }

    function Parse-ManifestLine {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Line
        )

        $parts = $Line.Split([char]9)
        if ($parts.Length -ne 9) {
            throw "Invalid manifest row: expected 9 fields but found $($parts.Length)."
        }

        return [PSCustomObject]@{
            FilePath    = ConvertFrom-Base64Utf8 -Value $parts[0]
            Width       = [int]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
            Height      = [int]::Parse($parts[2], [Globalization.CultureInfo]::InvariantCulture)
            GroupKey    = $parts[3]
            Xppi        = $parts[4]
            Yppi        = $parts[5]
            XPComment   = ConvertFrom-Base64Utf8 -Value $parts[6]
            LastWrite   = $parts[7]
            Creation    = $parts[8]
        }
    }

    function Escape-CsvField {
        [CmdletBinding()]
        param (
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Value
        )

        if ($null -eq $Value) {
            $Value = ''
        }

        return '"' + $Value.Replace('"', '""') + '"'
    }

    function Build-GroupCountsFile {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$ManifestPath,

            [Parameter(Mandatory = $true)]
            [string]$CountsPath,

            [long]$TotalRows
        )

        $counts = [System.Collections.Generic.Dictionary[string,long]]::new([System.StringComparer]::Ordinal)
        $reader = [System.IO.StreamReader]::new($ManifestPath, [Text.Encoding]::UTF8, $true, 65536)
        $row = 0L

        try {
            while (($line = $reader.ReadLine()) -ne $null) {
                $row++
                if ([string]::IsNullOrEmpty($line)) {
                    continue
                }

                $parts = $line.Split([char]9)
                if ($parts.Length -ne 9) {
                    throw "Manifest corruption at row $row."
                }

                $groupKey = $parts[3]
                [long]$current = 0L
                if ($counts.TryGetValue($groupKey, [ref]$current)) {
                    $counts[$groupKey] = $current + 1L
                }
                else {
                    $counts.Add($groupKey, 1L)
                }

                Write-ProgressStatus `
                    -Activity 'Calculating group counts' `
                    -Status ("Rows counted: {0:N0} / {1:N0} | groups: {2:N0}" -f $row, $TotalRows, $counts.Count) `
                    -Current $row `
                    -Total $TotalRows
            }
        }
        finally {
            $reader.Dispose()
        }

        $encoding = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($CountsPath, $false, $encoding, 65536)

        try {
            foreach ($entry in $counts.GetEnumerator()) {
                $writer.WriteLine(
                    ("{0}`t{1}" -f (ConvertTo-Base64Utf8 -Value $entry.Key), $entry.Value.ToString([Globalization.CultureInfo]::InvariantCulture))
                )
            }
        }
        finally {
            $writer.Flush()
            $writer.Dispose()
        }

        Write-ProgressStatus `
            -Activity 'Calculating group counts' `
            -Status ("Group counting complete: {0:N0} groups." -f $counts.Count) `
            -Current $TotalRows `
            -Total $TotalRows `
            -ForceRefresh

        Write-Progress -Id 1 -Activity 'Calculating group counts' -Completed

        return ,$counts
    }

    function Load-GroupCountsFile {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$CountsPath
        )

        $counts = [System.Collections.Generic.Dictionary[string,long]]::new([System.StringComparer]::Ordinal)
        $reader = [System.IO.StreamReader]::new($CountsPath, [Text.Encoding]::UTF8, $true, 65536)

        try {
            while (($line = $reader.ReadLine()) -ne $null) {
                if ([string]::IsNullOrEmpty($line)) {
                    continue
                }

                $parts = $line.Split([char]9)
                if ($parts.Length -ne 2) {
                    throw "Invalid group-count row in '$CountsPath'."
                }

                $groupKey = ConvertFrom-Base64Utf8 -Value $parts[0]
                $count = [long]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
                $counts[$groupKey] = $count
            }
        }
        finally {
            $reader.Dispose()
        }

        return ,$counts
    }

    function Convert-ManifestToCsv {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$ManifestPath,

            [Parameter(Mandatory = $true)]
            [string]$OutputCsvPath,

            [long]$TotalRows
        )

        $parent = [System.IO.Path]::GetDirectoryName($OutputCsvPath)
        if (-not [string]::IsNullOrEmpty($parent) -and -not [System.IO.Directory]::Exists($parent)) {
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        }

        $encoding = [System.Text.UTF8Encoding]::new($true)
        $writer = [System.IO.StreamWriter]::new($OutputCsvPath, $false, $encoding, 65536)
        $reader = [System.IO.StreamReader]::new($ManifestPath, [Text.Encoding]::UTF8, $true, 65536)

        try {
            $writer.WriteLine('FileName,OriginalFullPath,WidthPixels,HeightPixels,HorizontalPPI,VerticalPPI,XPComment,LastModifiedDateTime,CreationDateTime,GroupingMode,Group')

            $row = 0L
            while (($line = $reader.ReadLine()) -ne $null) {
                $row++
                if ([string]::IsNullOrEmpty($line)) {
                    continue
                }

                $record = Parse-ManifestLine -Line $line
                $fileName = [System.IO.Path]::GetFileName($record.FilePath)

                $csvFields = @(
                    (Escape-CsvField -Value $fileName),
                    (Escape-CsvField -Value $record.FilePath),
                    $record.Width.ToString([Globalization.CultureInfo]::InvariantCulture),
                    $record.Height.ToString([Globalization.CultureInfo]::InvariantCulture),
                    $record.Xppi,
                    $record.Yppi,
                    (Escape-CsvField -Value $record.XPComment),
                    (Escape-CsvField -Value $record.LastWrite),
                    (Escape-CsvField -Value $record.Creation),
                    (Escape-CsvField -Value $script:GroupingMode),
                    (Escape-CsvField -Value $record.GroupKey)
                )

                $writer.WriteLine([string]::Join(',', $csvFields))

                Write-ProgressStatus `
                    -Activity 'Writing CSV report' `
                    -Status ("CSV rows written: {0:N0} / {1:N0}" -f $row, $TotalRows) `
                    -Current $row `
                    -Total $TotalRows
            }
        }
        finally {
            $reader.Dispose()
            $writer.Flush()
            $writer.Dispose()
        }

        Write-ProgressStatus `
            -Activity 'Writing CSV report' `
            -Status ("CSV complete: {0:N0} image rows." -f $TotalRows) `
            -Current $TotalRows `
            -Total $TotalRows `
            -ForceRefresh `
            -SuccessProgress

        Write-Progress -Id 1 -Activity 'Writing CSV report' -Completed
    }

    function Invoke-ImageMove {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourcePath,

            [Parameter(Mandatory = $true)]
            [string]$GroupKey,

            [System.Collections.Generic.Dictionary[string,long]]$GroupCounts
        )

        $folderName = Get-TargetFolderName -GroupKey $GroupKey -GroupCounts $GroupCounts
        $targetDirectory = [System.IO.Path]::Combine($script:ResolvedInputPath, $folderName)
        $fileName = [System.IO.Path]::GetFileName($SourcePath)
        $nominalDestination = [System.IO.Path]::Combine($targetDirectory, $fileName)

        if (Test-SamePath -PathA $SourcePath -PathB $nominalDestination) {
            return [PSCustomObject]@{
                Status      = 'AlreadyOrganized'
                Destination = $nominalDestination
                Collision   = $false
            }
        }

        if (-not [System.IO.File]::Exists($SourcePath)) {
            if (Test-RecoveredDestinationExists -SourcePath $SourcePath -NominalDestinationPath $nominalDestination) {
                return [PSCustomObject]@{
                    Status      = 'Recovered'
                    Destination = $nominalDestination
                    Collision   = $false
                }
            }

            Write-Log -Message "Source file disappeared before it could be moved: $SourcePath" -Severity Error
            return [PSCustomObject]@{
                Status      = 'Missing'
                Destination = $nominalDestination
                Collision   = $false
            }
        }

        if (-not $script:TargetDirectoryCache.Contains($targetDirectory)) {
            if (-not [System.IO.Directory]::Exists($targetDirectory)) {
                if ($script:MainCmdlet.ShouldProcess($targetDirectory, 'Create destination directory')) {
                    [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
                    Write-Log -Message "Created destination folder: $targetDirectory" -Severity Success
                }
            }

            $null = $script:TargetDirectoryCache.Add($targetDirectory)
        }

        $destination = $nominalDestination
        $collision = $false

        if ([System.IO.File]::Exists($destination)) {
            if ($Force) {
                Write-Log -Message "Destination exists and will be replaced because -Force is enabled: $destination" -Severity Warn
            }
            else {
                $destination = Get-CollisionSafeDestinationPath -SourcePath $SourcePath -NominalDestinationPath $nominalDestination
                $collision = $true
                Write-Log -Message "Filename collision detected. Using deterministic destination '$destination'." -Severity Warn
            }
        }

        if (-not $script:MainCmdlet.ShouldProcess($SourcePath, "Move to '$destination'")) {
            return [PSCustomObject]@{
                Status      = 'WouldMove'
                Destination = $destination
                Collision   = $collision
            }
        }

        try {
            if ($Force -and [System.IO.File]::Exists($destination)) {
                [System.IO.File]::Delete($destination)
            }

            [System.IO.File]::Move($SourcePath, $destination)

            if ($LogEachFile) {
                Write-Log -Message "Moved '$SourcePath' -> '$destination'" -Severity Success
            }

            return [PSCustomObject]@{
                Status      = 'Moved'
                Destination = $destination
                Collision   = $collision
            }
        }
        catch {
            Write-Log -Message "Failed to move '$SourcePath' -> '$destination': $($_.Exception.Message)" -Severity Error
            return [PSCustomObject]@{
                Status      = 'Failed'
                Destination = $destination
                Collision   = $collision
            }
        }
    }

    # Compile the high-speed image header reader once per PowerShell session.
    if (-not ('ImageOrganizer.FastImageReader' -as [type])) {
        $fastImageReaderSource = @'
using System;
using System.IO;
using System.Text;

namespace ImageOrganizer
{
    public sealed class ImageSize
    {
        public int Width { get; private set; }
        public int Height { get; private set; }

        public ImageSize(int width, int height)
        {
            Width = width;
            Height = height;
        }
    }

    public static class FastImageReader
    {
        public static ImageSize Read(string path)
        {
            if (String.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Image path is empty.", "path");

            string extension = Path.GetExtension(path).ToLowerInvariant();

            using (FileStream stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                65536,
                FileOptions.SequentialScan))
            {
                switch (extension)
                {
                    case ".jpg":
                    case ".jpeg":
                    case ".jpe":
                    case ".jfif":
                        return ReadJpeg(stream);

                    case ".png":
                        return ReadPng(stream);

                    case ".gif":
                        return ReadGif(stream);

                    case ".bmp":
                        return ReadBmp(stream);

                    case ".webp":
                        return ReadWebP(stream);

                    case ".tif":
                    case ".tiff":
                        return ReadTiff(stream);

                    default:
                        throw new NotSupportedException("No fast header reader is available for extension '" + extension + "'.");
                }
            }
        }

        private static void ReadExactly(Stream stream, byte[] buffer, int offset, int count)
        {
            while (count > 0)
            {
                int read = stream.Read(buffer, offset, count);
                if (read <= 0)
                    throw new EndOfStreamException("Unexpected end of image file.");

                offset += read;
                count -= read;
            }
        }

        private static ushort UInt16LE(byte[] b, int o)
        {
            return (ushort)(b[o] | (b[o + 1] << 8));
        }

        private static ushort UInt16BE(byte[] b, int o)
        {
            return (ushort)((b[o] << 8) | b[o + 1]);
        }

        private static uint UInt24LE(byte[] b, int o)
        {
            return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16));
        }

        private static uint UInt32LE(byte[] b, int o)
        {
            return (uint)(
                b[o] |
                (b[o + 1] << 8) |
                (b[o + 2] << 16) |
                (b[o + 3] << 24));
        }

        private static uint UInt32BE(byte[] b, int o)
        {
            return (uint)(
                (b[o] << 24) |
                (b[o + 1] << 16) |
                (b[o + 2] << 8) |
                b[o + 3]);
        }

        private static string Ascii(byte[] b, int o, int count)
        {
            return Encoding.ASCII.GetString(b, o, count);
        }

        private static ImageSize ReadPng(Stream stream)
        {
            byte[] b = new byte[24];
            ReadExactly(stream, b, 0, b.Length);

            byte[] signature = new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 };
            for (int i = 0; i < signature.Length; i++)
            {
                if (b[i] != signature[i])
                    throw new InvalidDataException("Invalid PNG signature.");
            }

            int width = checked((int)UInt32BE(b, 16));
            int height = checked((int)UInt32BE(b, 20));
            Validate(width, height);
            return new ImageSize(width, height);
        }

        private static ImageSize ReadGif(Stream stream)
        {
            byte[] b = new byte[10];
            ReadExactly(stream, b, 0, b.Length);

            string signature = Ascii(b, 0, 6);
            if (signature != "GIF87a" && signature != "GIF89a")
                throw new InvalidDataException("Invalid GIF signature.");

            int width = UInt16LE(b, 6);
            int height = UInt16LE(b, 8);
            Validate(width, height);
            return new ImageSize(width, height);
        }

        private static ImageSize ReadBmp(Stream stream)
        {
            byte[] b = new byte[26];
            ReadExactly(stream, b, 0, b.Length);

            if (b[0] != (byte)'B' || b[1] != (byte)'M')
                throw new InvalidDataException("Invalid BMP signature.");

            uint dibSize = UInt32LE(b, 14);
            int width;
            int height;

            if (dibSize == 12)
            {
                width = UInt16LE(b, 18);
                height = UInt16LE(b, 20);
            }
            else
            {
                width = unchecked((int)UInt32LE(b, 18));
                height = unchecked((int)UInt32LE(b, 22));
                if (height < 0)
                    height = -height;
            }

            Validate(width, height);
            return new ImageSize(width, height);
        }

        private static int ReadByteRequired(Stream stream)
        {
            int value = stream.ReadByte();
            if (value < 0)
                throw new EndOfStreamException("Unexpected end of image file.");
            return value;
        }

        private static int ReadUInt16BE(Stream stream)
        {
            int a = ReadByteRequired(stream);
            int b = ReadByteRequired(stream);
            return (a << 8) | b;
        }

        private static ImageSize ReadJpeg(Stream stream)
        {
            if (ReadByteRequired(stream) != 0xFF || ReadByteRequired(stream) != 0xD8)
                throw new InvalidDataException("Invalid JPEG SOI marker.");

            while (stream.Position < stream.Length)
            {
                int prefix;
                do
                {
                    prefix = ReadByteRequired(stream);
                }
                while (prefix != 0xFF);

                int marker;
                do
                {
                    marker = ReadByteRequired(stream);
                }
                while (marker == 0xFF);

                if (marker == 0xD9 || marker == 0xDA)
                    break;

                if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7))
                    continue;

                int length = ReadUInt16BE(stream);
                if (length < 2)
                    throw new InvalidDataException("Invalid JPEG segment length.");

                if (IsStartOfFrame(marker))
                {
                    ReadByteRequired(stream); // precision
                    int height = ReadUInt16BE(stream);
                    int width = ReadUInt16BE(stream);
                    Validate(width, height);
                    return new ImageSize(width, height);
                }

                long skip = length - 2;
                if (stream.Position + skip > stream.Length)
                    throw new EndOfStreamException("JPEG segment exceeds file length.");

                stream.Seek(skip, SeekOrigin.Current);
            }

            throw new InvalidDataException("JPEG dimensions were not found.");
        }

        private static bool IsStartOfFrame(int marker)
        {
            switch (marker)
            {
                case 0xC0:
                case 0xC1:
                case 0xC2:
                case 0xC3:
                case 0xC5:
                case 0xC6:
                case 0xC7:
                case 0xC9:
                case 0xCA:
                case 0xCB:
                case 0xCD:
                case 0xCE:
                case 0xCF:
                    return true;
                default:
                    return false;
            }
        }

        private static ImageSize ReadWebP(Stream stream)
        {
            byte[] header = new byte[12];
            ReadExactly(stream, header, 0, header.Length);

            if (Ascii(header, 0, 4) != "RIFF" || Ascii(header, 8, 4) != "WEBP")
                throw new InvalidDataException("Invalid WebP RIFF signature.");

            byte[] chunkHeader = new byte[8];

            while (stream.Position + 8 <= stream.Length)
            {
                ReadExactly(stream, chunkHeader, 0, 8);
                string chunkType = Ascii(chunkHeader, 0, 4);
                uint chunkSize = UInt32LE(chunkHeader, 4);
                long dataStart = stream.Position;

                if (chunkType == "VP8X")
                {
                    byte[] b = new byte[10];
                    ReadExactly(stream, b, 0, b.Length);
                    int width = checked((int)(1 + UInt24LE(b, 4)));
                    int height = checked((int)(1 + UInt24LE(b, 7)));
                    Validate(width, height);
                    return new ImageSize(width, height);
                }

                if (chunkType == "VP8 ")
                {
                    byte[] b = new byte[10];
                    ReadExactly(stream, b, 0, b.Length);

                    if (b[3] != 0x9D || b[4] != 0x01 || b[5] != 0x2A)
                        throw new InvalidDataException("Invalid VP8 frame header.");

                    int width = UInt16LE(b, 6) & 0x3FFF;
                    int height = UInt16LE(b, 8) & 0x3FFF;
                    Validate(width, height);
                    return new ImageSize(width, height);
                }

                if (chunkType == "VP8L")
                {
                    byte[] b = new byte[5];
                    ReadExactly(stream, b, 0, b.Length);

                    if (b[0] != 0x2F)
                        throw new InvalidDataException("Invalid VP8L signature.");

                    int width = 1 + (b[1] | ((b[2] & 0x3F) << 8));
                    int height = 1 + ((b[2] >> 6) | (b[3] << 2) | ((b[4] & 0x0F) << 10));
                    Validate(width, height);
                    return new ImageSize(width, height);
                }

                long paddedSize = chunkSize + (chunkSize % 2);
                long next = dataStart + paddedSize;
                if (next > stream.Length)
                    throw new EndOfStreamException("WebP chunk exceeds file length.");

                stream.Position = next;
            }

            throw new InvalidDataException("WebP dimensions were not found.");
        }

        private static ushort ReadUInt16Endian(Stream stream, bool littleEndian)
        {
            int a = ReadByteRequired(stream);
            int b = ReadByteRequired(stream);
            return littleEndian
                ? (ushort)(a | (b << 8))
                : (ushort)((a << 8) | b);
        }

        private static uint ReadUInt32Endian(Stream stream, bool littleEndian)
        {
            int a = ReadByteRequired(stream);
            int b = ReadByteRequired(stream);
            int c = ReadByteRequired(stream);
            int d = ReadByteRequired(stream);

            if (littleEndian)
            {
                return (uint)(a | (b << 8) | (c << 16) | (d << 24));
            }

            return (uint)((a << 24) | (b << 16) | (c << 8) | d);
        }

        private static uint ReadTiffScalar(Stream stream, bool littleEndian, ushort type, uint count, uint rawValue)
        {
            if (count != 1)
                throw new NotSupportedException("TIFF width/height array values are not supported.");

            if (type == 3) // SHORT
            {
                return littleEndian
                    ? (rawValue & 0xFFFF)
                    : (rawValue >> 16);
            }

            if (type == 4) // LONG
                return rawValue;

            throw new NotSupportedException("Unsupported TIFF width/height field type: " + type);
        }

        private static ImageSize ReadTiff(Stream stream)
        {
            int byte1 = ReadByteRequired(stream);
            int byte2 = ReadByteRequired(stream);

            bool littleEndian;
            if (byte1 == 'I' && byte2 == 'I')
                littleEndian = true;
            else if (byte1 == 'M' && byte2 == 'M')
                littleEndian = false;
            else
                throw new InvalidDataException("Invalid TIFF byte-order marker.");

            ushort magic = ReadUInt16Endian(stream, littleEndian);
            if (magic != 42)
                throw new NotSupportedException("Only classic TIFF files are supported by the fast reader.");

            uint ifdOffset = ReadUInt32Endian(stream, littleEndian);
            if (ifdOffset >= stream.Length)
                throw new InvalidDataException("Invalid TIFF IFD offset.");

            stream.Position = ifdOffset;
            ushort entryCount = ReadUInt16Endian(stream, littleEndian);

            int width = 0;
            int height = 0;

            for (int i = 0; i < entryCount; i++)
            {
                ushort tag = ReadUInt16Endian(stream, littleEndian);
                ushort type = ReadUInt16Endian(stream, littleEndian);
                uint count = ReadUInt32Endian(stream, littleEndian);
                uint value = ReadUInt32Endian(stream, littleEndian);

                if (tag == 256)
                    width = checked((int)ReadTiffScalar(stream, littleEndian, type, count, value));
                else if (tag == 257)
                    height = checked((int)ReadTiffScalar(stream, littleEndian, type, count, value));

                if (width > 0 && height > 0)
                    break;
            }

            Validate(width, height);
            return new ImageSize(width, height);
        }

        private static void Validate(int width, int height)
        {
            if (width <= 0 || height <= 0)
                throw new InvalidDataException("Image has invalid dimensions.");
        }
    }
}
'@
        Add-Type -TypeDefinition $fastImageReaderSource -Language CSharp
    }

    Add-Type -AssemblyName System.Drawing

    $script:ResolvedInputPath = Resolve-InputDirectory -Path $InputPath
    $script:GroupingMode = if ($PSCmdlet.ParameterSetName -eq 'Ratio') { 'Ratio' } else { 'Dimension' }
    $script:IsWhatIfRun = [bool]$WhatIfPreference

    if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
        $ExportCsv = $true
    }

    if ($ExportCsv) {
        if ([string]::IsNullOrWhiteSpace($CsvPath)) {
            $CsvPath = Join-Path -Path (Get-Location).Path -ChildPath 'ImageMetadata.csv'
        }

        $script:ResolvedCsvPath = Resolve-OutputFilePath -Path $CsvPath
    }
    else {
        $script:ResolvedCsvPath = ''
    }

    $extensionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in $IncludeExtensions) {
        $normalized = $extension.Trim()
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }

        if (-not $normalized.StartsWith('.')) {
            $normalized = ".$normalized"
        }

        $null = $extensionSet.Add($normalized)
    }

    if ($extensionSet.Count -eq 0) {
        throw 'IncludeExtensions did not contain any valid extensions.'
    }

    if ($script:GroupingMode -eq 'Ratio') {
        $script:RatioTargets = @(Get-NormalizedRatioTargets -RatioSpecs $Ratios)
        $normalizedRatioLabels = @($script:RatioTargets | ForEach-Object { $_.Label })
    }
    else {
        $script:RatioTargets = @()
        $normalizedRatioLabels = @()
    }

    $configObject = [ordered]@{
        Version              = 3
        InputPath            = $script:ResolvedInputPath
        Recurse              = [bool]$Recurse
        GroupingMode         = $script:GroupingMode
        Ratios               = $normalizedRatioLabels
        AddCountToFolderName = [bool]$AddCountToFolderName
        ExportCsv            = [bool]$ExportCsv
        CsvPath              = $script:ResolvedCsvPath
        Extensions           = @($extensionSet | Sort-Object)
    }
    # Preserve existing recovery hashes when the new option is disabled.
    # When enabled, changing the threshold must not reuse an old move plan.
    if ($MinFilesPerGroup -gt 0) {
        $configObject['MinFilesPerGroup'] = $MinFilesPerGroup
    }
    $configJson = $configObject | ConvertTo-Json -Compress -Depth 5
    $script:ConfigHash = Get-Sha256Hex -Value $configJson

    $stateBaseName = '.Organize-ImagesByDimension'
    $script:StatePath = Join-Path -Path $script:ResolvedInputPath -ChildPath "$stateBaseName.state.json"
    $script:DirectorySnapshotPath = Join-Path -Path $script:ResolvedInputPath -ChildPath "$stateBaseName.directories.txt"
    $script:ManifestPath = Join-Path -Path $script:ResolvedInputPath -ChildPath "$stateBaseName.inventory.tsv"
    $script:GroupCountsPath = Join-Path -Path $script:ResolvedInputPath -ChildPath "$stateBaseName.groups.tsv"
    $script:LockPath = Join-Path -Path $script:ResolvedInputPath -ChildPath "$stateBaseName.lock"

    $script:TemporaryWhatIfFiles = [System.Collections.Generic.List[string]]::new()
    $script:LockStream = $null

    try {
        if ($script:IsWhatIfRun) {
            $tempRoot = [System.IO.Path]::GetTempPath()
        $runId = [Guid]::NewGuid().ToString('N')
        $script:DirectorySnapshotPath = Join-Path $tempRoot "$stateBaseName.$runId.directories.txt"
        $script:ManifestPath = Join-Path $tempRoot "$stateBaseName.$runId.inventory.tsv"
        $script:GroupCountsPath = Join-Path $tempRoot "$stateBaseName.$runId.groups.tsv"
        $script:TemporaryWhatIfFiles.Add($script:DirectorySnapshotPath)
        $script:TemporaryWhatIfFiles.Add($script:ManifestPath)
        $script:TemporaryWhatIfFiles.Add($script:GroupCountsPath)
    }
    else {
        try {
            $script:LockStream = [System.IO.FileStream]::new(
                $script:LockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        }
        catch {
            throw "Could not obtain the organizer lock '$($script:LockPath)'. Another instance may already be running for this folder. Details: $($_.Exception.Message)"
        }
    }

    if ($ResetState -and -not $script:IsWhatIfRun) {
        Write-Log -Message 'ResetState requested. Removing prior recovery sidecars.' -Severity Warn
        Remove-FileIfPresent -Path $script:StatePath
        Remove-FileIfPresent -Path $script:DirectorySnapshotPath
        Remove-FileIfPresent -Path $script:ManifestPath
        Remove-FileIfPresent -Path $script:GroupCountsPath
    }

    $requiresGroupCounts = [bool]($AddCountToFolderName -or $MinFilesPerGroup -gt 0)
    $requiresInventory = [bool]($requiresGroupCounts -or $ExportCsv)
    $script:State = $null
    $resumed = $false

    if (-not $script:IsWhatIfRun -and [System.IO.File]::Exists($script:StatePath)) {
        $existingState = Read-RecoveryState -Path $script:StatePath

        if ($existingState.Completed -eq $true) {
            Remove-FileIfPresent -Path $script:StatePath
        }
        elseif ($DisableResume) {
            throw "An incomplete organizer state already exists at '$($script:StatePath)'. For safety, either resume with the same options or explicitly use -ResetState."
        }
        elseif ($existingState.ConfigHash -ne $script:ConfigHash) {
            throw "An interrupted organizer run exists but its options differ from this run. Resume with the original options, or use -ResetState to intentionally start a new organization layout."
        }
        else {
            $script:State = $existingState
            $resumed = $true
            Write-Log -Message ("Resuming interrupted run. Phase: {0}." -f $script:State.Phase) -Severity Success
        }
    }

    if ($null -eq $script:State) {
        $initialPhase = if ($requiresInventory) { 'Inventory' } else { 'MoveDirect' }

        $script:State = [PSCustomObject][ordered]@{
            Version                 = 3
            ConfigHash              = $script:ConfigHash
            InputPath               = $script:ResolvedInputPath
            GroupingMode            = $script:GroupingMode
            StartedUtc              = [DateTime]::UtcNow.ToString('o')
            LastCheckpointUtc       = [DateTime]::UtcNow.ToString('o')
            Phase                   = $initialPhase
            Completed               = $false
            DirectoryCount          = 0L
            DirectoryIndex          = 0L
            ManifestCommittedLength = 0L
            InventoryRows           = 0L
            InventoryScanned        = 0L
            InventoryFailed         = 0L
            ReportComplete          = (-not [bool]$ExportCsv)
            MoveRowIndex            = 0L
            FilesScanned            = 0L
            ImagesMatched           = 0L
            FilesMoved              = 0L
            FilesAlreadyOrganized   = 0L
            FilesRecovered          = 0L
            FilesWouldMove          = 0L
            FilesFailed             = 0L
            Collisions              = 0L
        }
    }

    Write-Log -Message 'Starting image organization.' -Severity Info
    Write-Log -Message "InputPath                 : $($script:ResolvedInputPath)" -Severity Info
    Write-Log -Message "Recurse                   : $([bool]$Recurse)" -Severity Info
    Write-Log -Message "Grouping                  : $($script:GroupingMode)" -Severity Info
    Write-Log -Message "Add count to folder names : $([bool]$AddCountToFolderName)" -Severity Info
    Write-Log -Message "Minimum files per group   : $MinFilesPerGroup (0 = disabled)" -Severity Info
    if ($MinFilesPerGroup -gt 0) {
        Write-Log -Message "Groups with fewer than $MinFilesPerGroup images will be routed to 'Others'." -Severity Info
    }
    Write-Log -Message "CSV export                : $([bool]$ExportCsv)" -Severity Info
    if ($ExportCsv) {
        Write-Log -Message "CSV path                  : $($script:ResolvedCsvPath)" -Severity Info
    }
    Write-Log -Message "Resume enabled            : $(-not [bool]$DisableResume)" -Severity Info
    Write-Log -Message "Checkpoint every          : $CheckpointEvery image(s)" -Severity Info
    Write-Log -Message "Extensions                : $((@($extensionSet | Sort-Object)) -join ', ')" -Severity Info
    if ($script:GroupingMode -eq 'Ratio') {
        Write-Log -Message "Ratio targets             : $($normalizedRatioLabels -join ', ')" -Severity Info
    }

    # Build or recover the directory snapshot before processing.
    $needDirectorySnapshot = $script:State.Phase -in @('Inventory', 'MoveDirect')

    if ($needDirectorySnapshot -and -not [System.IO.File]::Exists($script:DirectorySnapshotPath)) {
        if ($resumed) {
            Write-Log -Message 'Directory snapshot is missing. It will be rebuilt and the current phase will safely restart from directory 0.' -Severity Warn
            $script:State.DirectoryIndex = 0L

            if ($script:State.Phase -eq 'Inventory') {
                $script:State.ManifestCommittedLength = 0L
                $script:State.InventoryRows = 0L
                $script:State.InventoryScanned = 0L
                $script:State.InventoryFailed = 0L
                Remove-FileIfPresent -Path $script:ManifestPath
            }
        }

        $snapshotResult = Build-DirectorySnapshot `
            -RootPath $script:ResolvedInputPath `
            -SnapshotPath $script:DirectorySnapshotPath `
            -Recursive ([bool]$Recurse)

        $script:State.DirectoryCount = [long]$snapshotResult.DirectoryCount
        Save-RecoveryState -State $script:State -Path $script:StatePath
    }
    elseif ($needDirectorySnapshot -and $script:State.DirectoryCount -le 0) {
        # Recount snapshot lines only when legacy/incomplete state omitted the count.
        $lineCount = 0L
        $reader = [System.IO.StreamReader]::new($script:DirectorySnapshotPath, [Text.Encoding]::UTF8, $true, 65536)
        try {
            while ($reader.ReadLine() -ne $null) {
                $lineCount++
            }
        }
        finally {
            $reader.Dispose()
        }
        $script:State.DirectoryCount = $lineCount
        Save-RecoveryState -State $script:State -Path $script:StatePath
    }
    }
    catch {
        if ($script:IsWhatIfRun) {
            foreach ($temporaryFile in $script:TemporaryWhatIfFiles) {
                Remove-FileIfPresent -Path $temporaryFile
            }
        }

        if ($null -ne $script:LockStream) {
            try {
                $script:LockStream.Dispose()
            }
            catch {
                # Best effort.
            }

            try {
                if ([System.IO.File]::Exists($script:LockPath)) {
                    [System.IO.File]::Delete($script:LockPath)
                }
            }
            catch {
                # Best effort. The operating system will release the file handle
                # when this PowerShell process exits.
            }
        }

        throw
    }
}

process {
    $groupCounts = $null
    $fatalError = $null

    try {
        # ---------------------------------------------------------------------
        # Phase 1: Read-only inventory for counts, small-group routing or CSV.
        # ---------------------------------------------------------------------
        if ($script:State.Phase -eq 'Inventory') {
            Write-Log -Message 'Inventory phase started. No image files are moved during this phase.' -Severity Info

            if ([System.IO.File]::Exists($script:ManifestPath)) {
                $actualLength = ([System.IO.FileInfo]::new($script:ManifestPath)).Length

                if ($actualLength -lt [long]$script:State.ManifestCommittedLength) {
                    throw "Inventory manifest is shorter than the last committed checkpoint. Use -ResetState to rebuild it safely."
                }
            }

            $manifestStream = [System.IO.FileStream]::new(
                $script:ManifestPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::Read,
                65536,
                [System.IO.FileOptions]::SequentialScan
            )

            if ($manifestStream.Length -gt [long]$script:State.ManifestCommittedLength) {
                # Discard rows written after the last durable state checkpoint.
                $manifestStream.SetLength([long]$script:State.ManifestCommittedLength)
            }

            $null = $manifestStream.Seek(0, [System.IO.SeekOrigin]::End)
            $manifestWriter = [System.IO.StreamWriter]::new(
                $manifestStream,
                ([System.Text.UTF8Encoding]::new($false)),
                65536,
                $true
            )

            $directoryReader = [System.IO.StreamReader]::new(
                $script:DirectorySnapshotPath,
                [Text.Encoding]::UTF8,
                $true,
                65536
            )

            $directoryIndex = 0L
            $rowsSinceCheckpoint = 0L
            $directoriesSinceCheckpoint = 0L

            try {
                while (($encodedDirectory = $directoryReader.ReadLine()) -ne $null) {
                    if ($directoryIndex -lt [long]$script:State.DirectoryIndex) {
                        $directoryIndex++
                        continue
                    }

                    $directory = Read-DirectorySnapshotLine -EncodedLine $encodedDirectory
                    $directoryImages = 0L

                    try {
                        foreach ($filePath in [System.IO.Directory]::EnumerateFiles($directory)) {
                            $script:State.InventoryScanned = [long]$script:State.InventoryScanned + 1L
                            $extension = [System.IO.Path]::GetExtension($filePath)

                            if (-not $extensionSet.Contains($extension)) {
                                continue
                            }

                            try {
                                $metadata = Get-InventoryImageMetadata `
                                    -FilePath $filePath `
                                    -NeedExtendedMetadata ([bool]$ExportCsv)

                                $groupKey = Get-GroupKey -Width $metadata.Width -Height $metadata.Height
                                $fileInfo = [System.IO.FileInfo]::new($filePath)

                                $manifestLine = New-ManifestLine `
                                    -FilePath $filePath `
                                    -Width $metadata.Width `
                                    -Height $metadata.Height `
                                    -GroupKey $groupKey `
                                    -Xppi $metadata.Xppi `
                                    -Yppi $metadata.Yppi `
                                    -XPComment $metadata.XPComment `
                                    -LastWriteTime $fileInfo.LastWriteTime `
                                    -CreationTime $fileInfo.CreationTime

                                $manifestWriter.WriteLine($manifestLine)

                                $script:State.InventoryRows = [long]$script:State.InventoryRows + 1L
                                $directoryImages++
                                $rowsSinceCheckpoint++
                            }
                            catch {
                                $script:State.InventoryFailed = [long]$script:State.InventoryFailed + 1L
                                Write-Log -Message "Failed to read image metadata for '$filePath': $($_.Exception.Message)" -Severity Error
                            }

                            $elapsed = [Math]::Max(0.001, $script:RunStopwatch.Elapsed.TotalSeconds)
                            $rate = [long]([long]$script:State.InventoryRows / $elapsed)

                            Write-ProgressStatus `
                                -Activity 'Inventorying images' `
                                -Status ("Directory {0:N0}/{1:N0} | scanned {2:N0} | images {3:N0} | failed {4:N0} | ~{5:N0} images/sec" -f ($directoryIndex + 1), $script:State.DirectoryCount, $script:State.InventoryScanned, $script:State.InventoryRows, $script:State.InventoryFailed, $rate) `
                                -Current ($directoryIndex + 1) `
                                -Total $script:State.DirectoryCount
                        }
                    }
                    catch {
                        $script:State.InventoryFailed = [long]$script:State.InventoryFailed + 1L
                        Write-Log -Message "Failed to enumerate files in '$directory': $($_.Exception.Message)" -Severity Error
                    }

                    $directoryIndex++
                    $directoriesSinceCheckpoint++

                    if ($rowsSinceCheckpoint -ge $CheckpointEvery -or $directoriesSinceCheckpoint -ge 100) {
                        $manifestWriter.Flush()
                        $manifestStream.Flush($true)

                        $script:State.DirectoryIndex = $directoryIndex
                        $script:State.ManifestCommittedLength = $manifestStream.Length
                        Save-RecoveryState -State $script:State -Path $script:StatePath

                        $rowsSinceCheckpoint = 0L
                        $directoriesSinceCheckpoint = 0L
                    }
                }

                $manifestWriter.Flush()
                $manifestStream.Flush($true)

                $script:State.DirectoryIndex = $directoryIndex
                $script:State.ManifestCommittedLength = $manifestStream.Length
                Save-RecoveryState -State $script:State -Path $script:StatePath
            }
            finally {
                $directoryReader.Dispose()
                $manifestWriter.Dispose()
                $manifestStream.Dispose()
            }

            Write-ProgressStatus `
                -Activity 'Inventorying images' `
                -Status ("Inventory complete: {0:N0} images | {1:N0} metadata failures." -f $script:State.InventoryRows, $script:State.InventoryFailed) `
                -Current $script:State.DirectoryCount `
                -Total $script:State.DirectoryCount `
                -ForceRefresh `
                -SuccessProgress

            Write-Progress -Id 1 -Activity 'Inventorying images' -Completed

            $script:State.Phase = 'Prepare'
            $script:State.DirectoryIndex = 0L
            Save-RecoveryState -State $script:State -Path $script:StatePath
        }

        # ---------------------------------------------------------------------
        # Phase 2: Build counts and/or the requested CSV from the stable manifest.
        # This phase is safe to rerun because no images have moved yet.
        # ---------------------------------------------------------------------
        if ($script:State.Phase -eq 'Prepare') {
            if ($requiresGroupCounts) {
                Write-Log -Message 'Calculating image counts for each original group.' -Severity Info
                $groupCounts = Build-GroupCountsFile `
                    -ManifestPath $script:ManifestPath `
                    -CountsPath $script:GroupCountsPath `
                    -TotalRows ([long]$script:State.InventoryRows)
            }

            if ($ExportCsv) {
                Write-Log -Message "Writing CSV metadata report: $($script:ResolvedCsvPath)" -Severity Info
                Convert-ManifestToCsv `
                    -ManifestPath $script:ManifestPath `
                    -OutputCsvPath $script:ResolvedCsvPath `
                    -TotalRows ([long]$script:State.InventoryRows)

                $script:State.ReportComplete = $true
            }

            $script:State.Phase = 'MoveManifest'
            $script:State.MoveRowIndex = 0L
            Save-RecoveryState -State $script:State -Path $script:StatePath
        }

        # ---------------------------------------------------------------------
        # Phase 3A: Move using the manifest for counts, small-group routing or CSV.
        # ---------------------------------------------------------------------
        if ($script:State.Phase -eq 'MoveManifest') {
            if ($requiresGroupCounts -and $null -eq $groupCounts) {
                if (-not [System.IO.File]::Exists($script:GroupCountsPath)) {
                    Write-Log -Message 'Group-count sidecar is missing. Rebuilding it from the completed inventory.' -Severity Warn
                    $groupCounts = Build-GroupCountsFile `
                        -ManifestPath $script:ManifestPath `
                        -CountsPath $script:GroupCountsPath `
                        -TotalRows ([long]$script:State.InventoryRows)
                }
                else {
                    $groupCounts = Load-GroupCountsFile -CountsPath $script:GroupCountsPath
                }
            }

            if ($ExportCsv -and (-not [System.IO.File]::Exists($script:ResolvedCsvPath))) {
                Write-Log -Message 'CSV report is missing during resume. Recreating it from the stable manifest before moving files.' -Severity Warn
                Convert-ManifestToCsv `
                    -ManifestPath $script:ManifestPath `
                    -OutputCsvPath $script:ResolvedCsvPath `
                    -TotalRows ([long]$script:State.InventoryRows)
            }

            Write-Log -Message 'Move phase started using the stable inventory manifest.' -Severity Info

            $reader = [System.IO.StreamReader]::new($script:ManifestPath, [Text.Encoding]::UTF8, $true, 65536)
            $rowIndex = 0L
            $processedSinceCheckpoint = 0L
            $sessionStartRow = [long]$script:State.MoveRowIndex
            $moveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                while (($line = $reader.ReadLine()) -ne $null) {
                    if ($rowIndex -lt [long]$script:State.MoveRowIndex) {
                        $rowIndex++
                        continue
                    }

                    if ([string]::IsNullOrEmpty($line)) {
                        $rowIndex++
                        continue
                    }

                    try {
                        $record = Parse-ManifestLine -Line $line
                        $result = Invoke-ImageMove `
                            -SourcePath $record.FilePath `
                            -GroupKey $record.GroupKey `
                            -GroupCounts $groupCounts

                        switch ($result.Status) {
                            'Moved' {
                                $script:State.FilesMoved = [long]$script:State.FilesMoved + 1L
                            }
                            'AlreadyOrganized' {
                                $script:State.FilesAlreadyOrganized = [long]$script:State.FilesAlreadyOrganized + 1L
                            }
                            'Recovered' {
                                $script:State.FilesRecovered = [long]$script:State.FilesRecovered + 1L
                            }
                            'WouldMove' {
                                $script:State.FilesWouldMove = [long]$script:State.FilesWouldMove + 1L
                            }
                            default {
                                $script:State.FilesFailed = [long]$script:State.FilesFailed + 1L
                            }
                        }

                        if ($result.Collision) {
                            $script:State.Collisions = [long]$script:State.Collisions + 1L
                        }
                    }
                    catch {
                        $script:State.FilesFailed = [long]$script:State.FilesFailed + 1L
                        Write-Log -Message "Failed to process manifest row $($rowIndex + 1): $($_.Exception.Message)" -Severity Error
                    }

                    $rowIndex++
                    $processedSinceCheckpoint++

                    if ($processedSinceCheckpoint -ge $CheckpointEvery) {
                        $script:State.MoveRowIndex = $rowIndex
                        Save-RecoveryState -State $script:State -Path $script:StatePath
                        $processedSinceCheckpoint = 0L
                    }

                    $sessionProcessed = [Math]::Max(1L, ($rowIndex - $sessionStartRow))
                    $elapsed = [Math]::Max(0.001, $moveStopwatch.Elapsed.TotalSeconds)
                    $rate = [long]($sessionProcessed / $elapsed)
                    $remainingRows = [Math]::Max(0L, ([long]$script:State.InventoryRows - $rowIndex))
                    $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds($remainingRows / [double]$rate) } else { [TimeSpan]::Zero }

                    $status = "Processed {0:N0}/{1:N0} | moved {2:N0} | already {3:N0} | recovered {4:N0} | failed {5:N0} | collisions {6:N0} | ~{7:N0}/sec | ETA {8:hh\:mm\:ss}" -f `
                        $rowIndex,
                        $script:State.InventoryRows,
                        $script:State.FilesMoved,
                        $script:State.FilesAlreadyOrganized,
                        $script:State.FilesRecovered,
                        $script:State.FilesFailed,
                        $script:State.Collisions,
                        $rate,
                        $eta

                    $progressMoved = [long]$script:State.FilesMoved
                    $successProgress = $progressMoved -gt $script:LastProgressMoved

                    Write-ProgressStatus `
                        -Activity 'Organizing images' `
                        -Status $status `
                        -Current $rowIndex `
                        -Total ([long]$script:State.InventoryRows) `
                        -SuccessProgress:$successProgress

                    if ($successProgress) {
                        $script:LastProgressMoved = $progressMoved
                    }
                }
            }
            finally {
                $reader.Dispose()
                $moveStopwatch.Stop()
            }

            $script:State.MoveRowIndex = $rowIndex
            Save-RecoveryState -State $script:State -Path $script:StatePath

            Write-Progress -Id 1 -Activity 'Organizing images' -Completed
        }

        # ---------------------------------------------------------------------
        # Phase 3B: Fast direct move. Used when neither counts nor CSV are needed.
        # No manifest is built, so this is the fastest and lowest-memory path.
        # ---------------------------------------------------------------------
        if ($script:State.Phase -eq 'MoveDirect') {
            Write-Log -Message 'Fast direct-move phase started (no count prepass and no CSV inventory).' -Severity Info

            $directoryReader = [System.IO.StreamReader]::new(
                $script:DirectorySnapshotPath,
                [Text.Encoding]::UTF8,
                $true,
                65536
            )

            $directoryIndex = 0L
            $processedSinceCheckpoint = 0L
            $directoriesSinceCheckpoint = 0L
            $moveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                while (($encodedDirectory = $directoryReader.ReadLine()) -ne $null) {
                    if ($directoryIndex -lt [long]$script:State.DirectoryIndex) {
                        $directoryIndex++
                        continue
                    }

                    $directory = Read-DirectorySnapshotLine -EncodedLine $encodedDirectory

                    try {
                        foreach ($filePath in [System.IO.Directory]::EnumerateFiles($directory)) {
                            $script:State.FilesScanned = [long]$script:State.FilesScanned + 1L
                            $extension = [System.IO.Path]::GetExtension($filePath)

                            if (-not $extensionSet.Contains($extension)) {
                                continue
                            }

                            $script:State.ImagesMatched = [long]$script:State.ImagesMatched + 1L

                            try {
                                $size = [ImageOrganizer.FastImageReader]::Read($filePath)
                                $groupKey = Get-GroupKey -Width $size.Width -Height $size.Height
                                $result = Invoke-ImageMove -SourcePath $filePath -GroupKey $groupKey -GroupCounts $null

                                switch ($result.Status) {
                                    'Moved' {
                                        $script:State.FilesMoved = [long]$script:State.FilesMoved + 1L
                                    }
                                    'AlreadyOrganized' {
                                        $script:State.FilesAlreadyOrganized = [long]$script:State.FilesAlreadyOrganized + 1L
                                    }
                                    'Recovered' {
                                        $script:State.FilesRecovered = [long]$script:State.FilesRecovered + 1L
                                    }
                                    'WouldMove' {
                                        $script:State.FilesWouldMove = [long]$script:State.FilesWouldMove + 1L
                                    }
                                    default {
                                        $script:State.FilesFailed = [long]$script:State.FilesFailed + 1L
                                    }
                                }

                                if ($result.Collision) {
                                    $script:State.Collisions = [long]$script:State.Collisions + 1L
                                }
                            }
                            catch {
                                $script:State.FilesFailed = [long]$script:State.FilesFailed + 1L
                                Write-Log -Message "Failed to inspect/process '$filePath': $($_.Exception.Message)" -Severity Error
                            }

                            $processedSinceCheckpoint++

                            $elapsed = [Math]::Max(0.001, $moveStopwatch.Elapsed.TotalSeconds)
                            $rate = [long]([long]$script:State.ImagesMatched / $elapsed)

                            $status = "Directory {0:N0}/{1:N0} | scanned {2:N0} | images {3:N0} | moved {4:N0} | already {5:N0} | failed {6:N0} | ~{7:N0} images/sec" -f `
                                ($directoryIndex + 1),
                                $script:State.DirectoryCount,
                                $script:State.FilesScanned,
                                $script:State.ImagesMatched,
                                $script:State.FilesMoved,
                                $script:State.FilesAlreadyOrganized,
                                $script:State.FilesFailed,
                                $rate

                            $progressMoved = [long]$script:State.FilesMoved
                            $successProgress = $progressMoved -gt $script:LastProgressMoved

                            Write-ProgressStatus `
                                -Activity 'Organizing images' `
                                -Status $status `
                                -Current ($directoryIndex + 1) `
                                -Total ([long]$script:State.DirectoryCount) `
                                -SuccessProgress:$successProgress

                            if ($successProgress) {
                                $script:LastProgressMoved = $progressMoved
                            }
                        }
                    }
                    catch {
                        $script:State.FilesFailed = [long]$script:State.FilesFailed + 1L
                        Write-Log -Message "Failed to enumerate files in '$directory': $($_.Exception.Message)" -Severity Error
                    }

                    $directoryIndex++
                    $directoriesSinceCheckpoint++

                    if ($processedSinceCheckpoint -ge $CheckpointEvery -or $directoriesSinceCheckpoint -ge 100) {
                        $script:State.DirectoryIndex = $directoryIndex
                        Save-RecoveryState -State $script:State -Path $script:StatePath
                        $processedSinceCheckpoint = 0L
                        $directoriesSinceCheckpoint = 0L
                    }
                }
            }
            finally {
                $directoryReader.Dispose()
                $moveStopwatch.Stop()
            }

            $script:State.DirectoryIndex = $directoryIndex
            Save-RecoveryState -State $script:State -Path $script:StatePath
            Write-Progress -Id 1 -Activity 'Organizing images' -Completed
        }

        $script:State.Phase = 'Completed'
        $script:State.Completed = $true
        Save-RecoveryState -State $script:State -Path $script:StatePath

        $elapsedTotal = $script:RunStopwatch.Elapsed
        $finalStatus = if ([long]$script:State.FilesFailed -gt 0 -or [long]$script:State.InventoryFailed -gt 0) {
            'CompletedWithErrors'
        }
        elseif ($script:IsWhatIfRun) {
            'WhatIfCompleted'
        }
        else {
            'Completed'
        }

        Write-Log -Message 'Execution summary:' -Severity Info
        if ($requiresInventory) {
            Write-Log -Message ("Inventory images       : {0:N0}" -f [long]$script:State.InventoryRows) -Severity Info
            Write-Log -Message ("Inventory failures     : {0:N0}" -f [long]$script:State.InventoryFailed) -Severity Info
        }
        else {
            Write-Log -Message ("Files scanned          : {0:N0}" -f [long]$script:State.FilesScanned) -Severity Info
            Write-Log -Message ("Images matched         : {0:N0}" -f [long]$script:State.ImagesMatched) -Severity Info
        }

        Write-Log -Message ("Files moved            : {0:N0}" -f [long]$script:State.FilesMoved) -Severity Success
        Write-Log -Message ("Already organized      : {0:N0}" -f [long]$script:State.FilesAlreadyOrganized) -Severity Info
        Write-Log -Message ("Recovered after resume : {0:N0}" -f [long]$script:State.FilesRecovered) -Severity Success
        Write-Log -Message ("Would move (-WhatIf)   : {0:N0}" -f [long]$script:State.FilesWouldMove) -Severity Info
        Write-Log -Message ("Collisions handled     : {0:N0}" -f [long]$script:State.Collisions) -Severity Info
        $failureSeverity = if ([long]$script:State.FilesFailed -gt 0) { 'Error' } else { 'Info' }
        Write-Log -Message ("Move/process failures  : {0:N0}" -f [long]$script:State.FilesFailed) -Severity $failureSeverity
        Write-Log -Message ("Elapsed                 : {0:hh\:mm\:ss\.fff}" -f $elapsedTotal) -Severity Info

        if ($ExportCsv) {
            Write-Log -Message "CSV report              : $($script:ResolvedCsvPath)" -Severity Success
        }

        if ($finalStatus -eq 'Completed') {
            Write-Log -Message 'Image organization completed successfully.' -Severity Success
        }
        elseif ($finalStatus -eq 'WhatIfCompleted') {
            Write-Log -Message 'WhatIf analysis completed successfully. No image files were moved.' -Severity Success
        }
        else {
            Write-Log -Message 'Image organization completed, but one or more files/directories reported errors. Review the red error lines above.' -Severity Warn
        }

        [PSCustomObject]@{
            Status                 = $finalStatus
            InputPath              = $script:ResolvedInputPath
            GroupingMode           = $script:GroupingMode
            AddCountToFolderName   = [bool]$AddCountToFolderName
            MinFilesPerGroup       = $MinFilesPerGroup
            CsvExported            = [bool]$ExportCsv
            CsvPath                = if ($ExportCsv) { $script:ResolvedCsvPath } else { $null }
            InventoryImages        = [long]$script:State.InventoryRows
            FilesScanned           = [long]$script:State.FilesScanned
            ImagesMatched          = [long]$script:State.ImagesMatched
            FilesMoved             = [long]$script:State.FilesMoved
            FilesAlreadyOrganized  = [long]$script:State.FilesAlreadyOrganized
            FilesRecovered         = [long]$script:State.FilesRecovered
            FilesWouldMove         = [long]$script:State.FilesWouldMove
            FilesFailed            = [long]$script:State.FilesFailed
            InventoryFailed        = [long]$script:State.InventoryFailed
            CollisionsHandled      = [long]$script:State.Collisions
            Elapsed                = $elapsedTotal
        }
    }
    catch {
        $fatalError = $_
        Write-Log -Message "Fatal error: $($_.Exception.Message)" -Severity Error

        try {
            if ($null -ne $script:State -and -not $script:IsWhatIfRun) {
                Save-RecoveryState -State $script:State -Path $script:StatePath
                Write-Log -Message "Recovery state preserved. Re-run the same command to continue." -Severity Warn
            }
        }
        catch {
            Write-Log -Message "Additionally failed to persist recovery state: $($_.Exception.Message)" -Severity Error
        }

        throw
    }
    finally {
        $script:RunStopwatch.Stop()
        Write-Progress -Id 1 -Activity 'Organizing images' -Completed -ErrorAction SilentlyContinue

        if ($null -eq $fatalError -and $null -ne $script:State -and $script:State.Completed -eq $true -and -not $script:IsWhatIfRun) {
            Remove-FileIfPresent -Path $script:StatePath
            Remove-FileIfPresent -Path $script:DirectorySnapshotPath
            Remove-FileIfPresent -Path $script:ManifestPath
            Remove-FileIfPresent -Path $script:GroupCountsPath
        }

        if ($script:IsWhatIfRun) {
            foreach ($temporaryFile in $script:TemporaryWhatIfFiles) {
                Remove-FileIfPresent -Path $temporaryFile
            }
        }

        if ($null -ne $script:LockStream) {
            try {
                $script:LockStream.Dispose()
            }
            catch {
                # Best effort.
            }

            try {
                if ([System.IO.File]::Exists($script:LockPath)) {
                    [System.IO.File]::Delete($script:LockPath)
                }
            }
            catch {
                Write-Log -Message "Could not remove lock file '$($script:LockPath)': $($_.Exception.Message)" -Severity Warn
            }
        }
    }
}

#Requires -Version 5.1
<#
.SYNOPSIS
Install the official Windows applications corresponding to macos-resources.sh.
.EXAMPLE
.\windows-resources.ps1 -List
.EXAMPLE
.\windows-resources.ps1 -WhatIf
.EXAMPLE
.\windows-resources.ps1 -App 'Cursor','Grok Bot'
.NOTES
Run on Windows 10/11 with App Installer (WinGet) installed.
Microsoft Store apps may require sign-in. Paid apps require their own licenses.
Installer prompts and elevation requests remain interactive. No reboot is requested.
Direct EXE installers are verified for Windows x64; WinGet selects compatible builds.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$App,
    [switch]$List
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Save-OfficialInstaller {
    param([string]$Url, [string]$Destination)
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(15)
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    try {
        $uri = [Uri]$Url
        for ($redirect = 0; $redirect -le 5; $redirect++) {
            if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https') { throw 'Installer downloads require HTTPS.' }
            $response = $client.GetAsync($uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                $status = [int]$response.StatusCode
                if ($status -ge 300 -and $status -lt 400) {
                    if (-not $response.Headers.Location) { throw 'Download redirect has no destination.' }
                    $uri = New-Object Uri($uri, $response.Headers.Location)
                    continue
                }
                [void]$response.EnsureSuccessStatusCode()
                $stream = [IO.File]::Create($Destination)
                try { $response.Content.CopyToAsync($stream).GetAwaiter().GetResult() } finally { $stream.Dispose() }
                return
            } finally { $response.Dispose() }
        }
        throw 'Too many installer download redirects.'
    } finally { $client.Dispose(); $handler.Dispose() }
}

function Install-OfficialExe {
    param($Application)
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $temporary)
    $installer = Join-Path $temporary 'setup.exe'
    try {
        Save-OfficialInstaller -Url $Application.InstallerUrl -Destination $installer
        $signature = Get-AuthenticodeSignature -FilePath $installer
        if ($signature.Status -ne 'Valid') { throw 'The official installer does not have a valid Windows signature.' }
        $process = Start-Process -FilePath $installer -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010, 1641)) { throw ('Installer exited with code {0}.' -f $process.ExitCode) }
        return $process.ExitCode
    } finally { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}

$catalogPath = Join-Path $PSScriptRoot 'windows-applications.json'
# Assign before normalizing: Windows PowerShell 5.1 emits the JSON array as one pipeline object.
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$catalog = @($catalog)
foreach ($entry in $catalog) {
    if (-not $entry.Name -or ([Uri]$entry.OfficialUrl).Scheme -ne 'https') { throw 'Invalid application catalog entry.' }
    if ($entry.PackageId) {
        if ($entry.Source -notin @('winget', 'msstore') -or $entry.InstallerUrl) { throw 'Invalid package source.' }
    } elseif (-not $entry.InstallerUrl -or ([Uri]$entry.InstallerUrl).Scheme -ne 'https') {
        throw 'An official HTTPS installer is required.'
    }
}
$selected = $catalog
if ($App) {
    foreach ($name in $App) {
        if (@($catalog | Where-Object { $_.Name -eq $name -or $_.Aliases -contains $name }).Count -eq 0) {
            throw ('Unknown application: {0}. Use -List to see the available applications.' -f $name)
        }
    }
    $selected = @($catalog | Where-Object {
        $entry = $_
        @($App | Where-Object { $entry.Name -eq $_ -or $entry.Aliases -contains $_ }).Count -gt 0
    })
}
if ($List) { $selected; return }
if (-not $WhatIfPreference) {
    if ($env:OS -ne 'Windows_NT') { throw 'Installation requires Windows. Use -List or -WhatIf to preview elsewhere.' }
    if (@($selected | Where-Object { $_.PackageId }).Count -gt 0 -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'WinGet is missing. Install Microsoft App Installer from https://apps.microsoft.com/detail/9NBLGGH4NNS1 and rerun.'
    }
}
$results = @()
foreach ($entry in $selected) {
    if (-not $PSCmdlet.ShouldProcess($entry.Name, 'Install official Windows application')) { continue }
    try {
        $reboot = $false
        if ($entry.PackageId) {
            & winget install --id $entry.PackageId --exact --source $entry.Source --accept-source-agreements --accept-package-agreements | Out-Host
            $code = $LASTEXITCODE
            # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE means already current.
            if ($code -notin @(0, -1978335189, 2316632107)) { throw ('WinGet exited with code {0}.' -f $code) }
        } else {
            $architecture = $env:PROCESSOR_ARCHITEW6432
            if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
            $architecture = if ($architecture -eq 'AMD64') { 'x64' } else { $architecture.ToLowerInvariant() }
            if ($entry.Architectures -notcontains $architecture) { throw ('No verified official installer for architecture {0}.' -f $architecture) }
            $code = Install-OfficialExe -Application $entry
            $reboot = $code -in @(3010, 1641)
        }
        $results += [PSCustomObject]@{ Name = $entry.Name; Status = 'InstalledOrCurrent'; RebootRequired = $reboot; Detail = '' }
    } catch {
        Write-Warning ('{0}: {1}' -f $entry.Name, $_.Exception.Message)
        $results += [PSCustomObject]@{ Name = $entry.Name; Status = 'Failed'; RebootRequired = $false; Detail = $_.Exception.Message }
    }
}
$results
$global:LASTEXITCODE = if (@($results | Where-Object { $_.Status -eq 'Failed' }).Count) { 1 } else { 0 }
if ($MyInvocation.InvocationName -ne '.') { exit $global:LASTEXITCODE }

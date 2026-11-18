# Dot-source from PowerShell to configure the current session and its children.
$projectRoot = Split-Path -Parent $PSScriptRoot
$rLock = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'renv.lock') | ConvertFrom-Json
$rCandidates = @()
if ($env:TRANSCRIPTOMICS_RSCRIPT) { $rCandidates += $env:TRANSCRIPTOMICS_RSCRIPT }
if ($env:ProgramFiles) {
    $rCandidates += Join-Path $env:ProgramFiles ("R/R-" + $rLock.R.Version + "/bin/Rscript.exe")
}
$rCommand = Get-Command Rscript -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($rCommand) { $rCandidates += $rCommand.Source }
$rscript = $rCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (!$rscript) { throw 'Install the R version recorded in environment/renv.lock or set TRANSCRIPTOMICS_RSCRIPT.' }
$rBinDirectory = Split-Path -Parent $rscript
$env:TRANSCRIPTOMICS_ROOT = $projectRoot
$referenceConfig = Join-Path $projectRoot 'config/reference_paths.json'
if (Test-Path -LiteralPath $referenceConfig -PathType Leaf) {
    $referencePaths = Get-Content -Raw -Encoding UTF8 -LiteralPath $referenceConfig | ConvertFrom-Json
    $env:BMS_BULK_ROOT = Join-Path $projectRoot $referencePaths.bms_bulk
    $env:SENCAT_ROOT = Join-Path $projectRoot $referencePaths.sencat
} else {
    $env:BMS_BULK_ROOT = $null
    $env:SENCAT_ROOT = $null
}
$env:R_LIBS_USER = Join-Path $PSScriptRoot 'R-library'
$env:R_LIBS = $env:R_LIBS_USER
$env:R_LIBS_SITE = 'NULL'
$env:R_PROFILE_USER = Join-Path $projectRoot '.Rprofile'
$env:QUARTO_R = $rBinDirectory
$toolDirs = @($rBinDirectory)
if ($env:OS -eq 'Windows_NT') {
    $env:LC_ALL = 'English_United States.utf8'
    $env:LANG = 'en_US.UTF-8'
    if (!(Get-Command quarto -CommandType Application -ErrorAction SilentlyContinue)) {
        $quartoCandidates = @('Quarto/bin', 'RStudio/resources/app/bin/quarto/bin')
        foreach ($candidate in $quartoCandidates) {
            $quartoBin = Join-Path $env:ProgramFiles $candidate
            if (Test-Path -LiteralPath (Join-Path $quartoBin 'quarto.exe')) {
                $toolDirs += $quartoBin
                break
            }
        }
    }
}
$pathDirs = $toolDirs + ($env:PATH -split [IO.Path]::PathSeparator)
$env:PATH = ($pathDirs | Select-Object -Unique) -join [IO.Path]::PathSeparator
Set-Location -LiteralPath $projectRoot
Write-Output "Transcriptomics workspace: $projectRoot"

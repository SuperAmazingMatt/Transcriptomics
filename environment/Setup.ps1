# The child process confines PATH, R settings and package changes to this project.
$setupEntry = Join-Path $PSScriptRoot 'Activate.ps1'
& {
    $savedLocation = Get-Location
    $envKeys = @('TRANSCRIPTOMICS_ROOT','BMS_BULK_ROOT','SENCAT_ROOT','R_LIBS_USER',
        'R_LIBS','R_LIBS_SITE','R_PROFILE_USER','QUARTO_R','PATH','LC_ALL','LANG')
    $envBefore = @{}
    foreach ($key in $envKeys) { $envBefore[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
    try {
        . $setupEntry
        & $rscript --vanilla environment/setup.R
        if ($LASTEXITCODE -ne 0) { throw 'Project environment restore failed.' }
    } finally {
        foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $envBefore[$key], 'Process') }
        Set-Location -LiteralPath $savedLocation.Path
    }
}

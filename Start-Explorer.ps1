# Start the workstation app against its private R library, opening the local URL.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment/Activate.ps1')
& Rscript --vanilla -e "shiny::runApp('app', host='127.0.0.1', launch.browser=TRUE)"
exit $LASTEXITCODE

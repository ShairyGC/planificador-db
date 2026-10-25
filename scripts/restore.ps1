param([Parameter(Mandatory = $true)][string]$Archivo)
$ErrorActionPreference = 'Stop'
$origen = (Resolve-Path -LiteralPath $Archivo).Path
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    docker compose cp $origen db:/tmp/planificador-restore.dump
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la copia del respaldo' }
    # Sustituye los objetos de esta BD. --single-transaction evita restauraciones parciales.
    docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-acl --single-transaction /tmp/planificador-restore.dump'
    if ($LASTEXITCODE -ne 0) { throw 'Fallo pg_restore' }
    Write-Host 'Base de datos restaurada.'
} finally { Pop-Location }

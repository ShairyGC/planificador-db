param([string]$Destino)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    if (-not $Destino) {
        New-Item -ItemType Directory -Force -Path backups | Out-Null
        $Destino = Join-Path (Get-Location) ('backups/planificador-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.dump')
    }
    # Sin redireccion binaria de PowerShell: pg_dump escribe dentro del contenedor.
    docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl --file=/tmp/planificador-backup.dump'
    if ($LASTEXITCODE -ne 0) { throw 'Fallo pg_dump' }
    docker compose cp db:/tmp/planificador-backup.dump $Destino
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la copia del respaldo' }
    Write-Host "Respaldo creado: $Destino"
} finally { Pop-Location }

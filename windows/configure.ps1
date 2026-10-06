$ErrorActionPreference = 'Stop'

$candidates = @()
$onPath = Get-Command sbcl.exe -ErrorAction SilentlyContinue
if ($onPath) {
    $candidates += $onPath.Source
}

$standardRoot = Join-Path $env:ProgramFiles 'Steel Bank Common Lisp'
if (Test-Path $standardRoot) {
    $candidates += Get-ChildItem $standardRoot -Filter sbcl.exe -Recurse |
        Select-Object -ExpandProperty FullName
}

$sbcl = $null
foreach ($candidate in ($candidates | Select-Object -Unique)) {
    $reported = (& $candidate --noinform --non-interactive --eval '(princ (lisp-implementation-version))' --quit 2>&1 | Out-String).Trim()
    if (($reported -match '(\d+\.\d+\.\d+)') -and
        ([version]$Matches[1] -ge [version]'2.6.9')) {
        $sbcl = $candidate
        break
    }
}

if (-not $sbcl) {
    throw 'A recent SBCL (2.6.9 or newer) was not found. Install the latest official 64-bit Windows release from https://www.sbcl.org/platform-table.html, then run this installer again.'
}

$appRoot = Split-Path $PSScriptRoot -Parent
Push-Location $appRoot
try {
    & $sbcl --noinform --non-interactive --no-sysinit --no-userinit --load build.lisp
    if ($LASTEXITCODE -ne 0) {
        throw "SBCL could not create sbemacs.exe (exit code $LASTEXITCODE)."
    }
    if (-not (Test-Path (Join-Path $appRoot 'sbemacs.exe'))) {
        throw 'SBCL finished without creating sbemacs.exe.'
    }
}
finally {
    Pop-Location
}

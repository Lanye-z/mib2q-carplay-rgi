param(
    [string]$QnxRoot = "C:\QNX650",
    [string]$Output = (Join-Path $PSScriptRoot "build\maneuver_render"),
    [switch]$Grid
)

$ErrorActionPreference = "Stop"

$env:QNX_HOST = Join-Path $QnxRoot "host\win32\x86"
$env:QNX_TARGET = Join-Path $QnxRoot "target\qnx6"
$env:QNX_CONFIGURATION = "C:\Program Files (x86)\QNX Software Systems"
$qnxBin = Join-Path $env:QNX_HOST "usr\bin"
$env:PATH = "$qnxBin;$env:PATH"

$rendererDir = Join-Path $PSScriptRoot "c_render"
$compiler = Join-Path $qnxBin "ntoarmv7-gcc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "QNX ARMv7 compiler not found: $compiler"
}

$outputPath = [IO.Path]::GetFullPath($Output)
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$sources = @(
    "main.c",
    "render.c",
    "maneuver.c",
    "route_path.c",
    "server.c",
    "platform_qnx.c"
) | ForEach-Object { Join-Path $rendererDir $_ }

$arguments = @(
    "-O2",
    "-std=gnu99",
    "-Wall",
    "-D__QNX__",
    "-DPLATFORM_QNX",
    "-fdata-sections",
    "-ffunction-sections"
)
if ($Grid) {
    $arguments += "-DCR_DEBUG_GRID"
}
$arguments += "-I$rendererDir"
$arguments += $sources
$arguments += @(
    "-o",
    $outputPath,
    "-Wl,--gc-sections",
    "-lEGL",
    "-lGLESv2",
    "-lsocket",
    "-lm"
)

& $compiler @arguments
if ($LASTEXITCODE -ne 0) {
    throw "QNX renderer compilation failed with exit code $LASTEXITCODE"
}

Get-Item -LiteralPath $outputPath |
    Select-Object FullName, Length, LastWriteTime

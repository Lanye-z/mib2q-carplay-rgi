param(
    [string]$Output = (Join-Path $PSScriptRoot "dist\local-test-windows\c_render_windows.exe"),
    [switch]$Grid,
    [switch]$NoBootstrap
)

$ErrorActionPreference = "Stop"

$zigVersion = "0.16.0"
$zigArchiveName = "zig-x86_64-windows-$zigVersion.zip"
$zigSha256 = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"
$glfwVersion = "3.4"
$glfwCommit = "7b6aead9fb88b3623e3b3725ebb42670cbe4c579"

$toolsDir = Join-Path $PSScriptRoot ".tools"
$downloadsDir = Join-Path $toolsDir "downloads"
$zigDir = Join-Path $toolsDir "zig-$zigVersion"
$zigExe = Join-Path $zigDir "zig.exe"
$glfwDir = Join-Path $toolsDir "glfw-$glfwVersion"

function Get-VerifiedZig {
    if (Test-Path -LiteralPath $zigExe) { return }
    if ($NoBootstrap) { throw "Zig $zigVersion not found at $zigExe" }

    New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
    $archive = Join-Path $downloadsDir $zigArchiveName
    $urls = @(
        "https://ziglang.freetls.fastly.net/$zigArchiveName?source=carplay-rgi-local-renderer",
        "https://pkg.hexops.org/zig/$zigArchiveName?source=carplay-rgi-local-renderer",
        "https://ziglang.org/download/$zigVersion/$zigArchiveName"
    )

    foreach ($url in $urls) {
        try {
            Write-Host "Downloading Zig from $url"
            & curl.exe -L --fail --retry 3 --retry-delay 2 -o $archive $url
            if ($LASTEXITCODE -ne 0) { throw "curl exit code $LASTEXITCODE" }
            $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $zigSha256) { throw "checksum mismatch: $actual" }
            break
        } catch {
            Write-Warning $_
            Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $archive)) {
        throw "Unable to download a verified Zig $zigVersion archive"
    }

    $extractDir = Join-Path $toolsDir "zig-extract-$zigVersion"
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    & tar.exe -xf $archive -C $extractDir
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract Zig archive" }
    $inner = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if ($null -eq $inner) { throw "Zig archive contains no root directory" }
    Move-Item -LiteralPath $inner.FullName -Destination $zigDir
    Remove-Item -LiteralPath $extractDir -Recurse -Force
}

function Get-PinnedGlfw {
    if (Test-Path -LiteralPath (Join-Path $glfwDir ".git")) {
        $actual = (& git -c "safe.directory=$glfwDir" -C $glfwDir rev-parse HEAD).Trim()
        if ($actual -eq $glfwCommit) { return }
        throw "Unexpected GLFW revision at $glfwDir`: $actual"
    }
    if ($NoBootstrap) { throw "GLFW $glfwVersion not found at $glfwDir" }

    & git clone --depth 1 --branch $glfwVersion https://github.com/glfw/glfw.git $glfwDir
    if ($LASTEXITCODE -ne 0) { throw "Unable to clone GLFW" }
    $actual = (& git -c "safe.directory=$glfwDir" -C $glfwDir rev-parse HEAD).Trim()
    if ($actual -ne $glfwCommit) {
        throw "GLFW revision mismatch: expected $glfwCommit, got $actual"
    }
}

Get-VerifiedZig
Get-PinnedGlfw

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $toolsDir "zig-cache-global"
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $toolsDir "zig-cache-local"

$rendererDir = Join-Path $PSScriptRoot "c_render"
$glfwSrc = Join-Path $glfwDir "src"
$outputPath = [IO.Path]::GetFullPath($Output)
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$rendererSources = @(
    "main.c", "render.c", "maneuver.c", "route_path.c",
    "server_windows.c", "platform_windows.c"
) | ForEach-Object { Join-Path $rendererDir $_ }

$glfwSources = @(
    "context.c", "init.c", "input.c", "monitor.c", "platform.c",
    "vulkan.c", "window.c", "egl_context.c", "osmesa_context.c",
    "null_init.c", "null_monitor.c", "null_window.c", "null_joystick.c",
    "win32_module.c", "win32_time.c", "win32_thread.c", "win32_init.c",
    "win32_joystick.c", "win32_monitor.c", "win32_window.c", "wgl_context.c"
) | ForEach-Object { Join-Path $glfwSrc $_ }

$arguments = @(
    "cc", "-target", "x86_64-windows-gnu", "-O2", "-std=gnu99",
    "-Wall", "-Wextra", "-Wno-unused-parameter",
    "-Wno-missing-field-initializers", "-Wno-sign-compare",
    "-DPLATFORM_WINDOWS", "-D_GLFW_WIN32", "-DUNICODE", "-D_UNICODE",
    "-I$rendererDir", "-I$(Join-Path $glfwDir 'include')",
    "-I$(Join-Path $glfwDir 'deps')", "-I$glfwSrc"
)
if ($Grid) { $arguments += "-DCR_DEBUG_GRID" }
$arguments += $rendererSources
$arguments += $glfwSources
$arguments += @(
    "-o", $outputPath, "-lopengl32", "-lws2_32", "-lgdi32",
    "-luser32", "-lshell32", "-ladvapi32"
)

Write-Host "Building Windows local renderer..."
& $zigExe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Windows renderer compilation failed with exit code $LASTEXITCODE"
}

$pdbPath = [IO.Path]::ChangeExtension($outputPath, ".pdb")
Remove-Item -LiteralPath $pdbPath -Force -ErrorAction SilentlyContinue

Copy-Item -LiteralPath (Join-Path $rendererDir "resources\flag_atlas.rgba") `
    -Destination (Join-Path $outputDir "flag_atlas.rgba") -Force

$item = Get-Item -LiteralPath $outputPath
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
Write-Host "Built: $($item.FullName)"
Write-Host "Size:  $($item.Length) bytes"
Write-Host "SHA256: $hash"

param(
    [string]$Renderer = (Join-Path $PSScriptRoot "c_render_windows.exe"),
    [ValidateRange(1, 4)][int]$Scale = 2,
    [switch]$AutoTest,
    [ValidateSet("None", "Original", "R3")][string]$Scenario = "None",
    [string]$ScenarioOutput = (Join-Path $PSScriptRoot "complex-scenario")
)

$ErrorActionPreference = "Stop"
$port = 19800
$packetSize = 48
$rx = New-Object 'System.Collections.Generic.List[byte]'

$presets = @(
    [pscustomobject]@{ Name="Straight";   Icon=1; Direction=0;  Angle=0;    Junctions=@() },
    [pscustomobject]@{ Name="Right";      Icon=2; Direction=0;  Angle=90;   Junctions=@() },
    [pscustomobject]@{ Name="Left";       Icon=2; Direction=0;  Angle=-90;  Junctions=@() },
    [pscustomobject]@{ Name="SharpRight"; Icon=2; Direction=0;  Angle=135;  Junctions=@() },
    [pscustomobject]@{ Name="UTurn";      Icon=3; Direction=0;  Angle=0;    Junctions=@() },
    [pscustomobject]@{ Name="MergeRight"; Icon=4; Direction=1;  Angle=0;    Junctions=@() },
    [pscustomobject]@{ Name="ExitLeft";   Icon=5; Direction=-1; Angle=0;    Junctions=@() },
    [pscustomobject]@{ Name="Roundabout"; Icon=6; Direction=0;  Angle=90;   Junctions=@(90,0,-90,-150) },
    [pscustomobject]@{ Name="Arrived";    Icon=7; Direction=0;  Angle=0;    Junctions=@() }
)

$presetIndex = 1
$perspective = 1
$bargraphLevel = 12
$bargraphMode = 1
$listener = $null
$client = $null
$stream = $null
$rendererProcess = $null
$scenarioEvents = New-Object 'System.Collections.Generic.List[object]'
$scenarioStep = 0
$scenarioMode = ""

function Get-MonotonicMilliseconds {
    return [long](([Diagnostics.Stopwatch]::GetTimestamp() * 1000.0) / `
        [Diagnostics.Stopwatch]::Frequency)
}

function Set-Int16BE([byte[]]$packet, [int]$offset, [int]$value) {
    $bytes = [BitConverter]::GetBytes([int16]$value)
    $packet[$offset] = $bytes[1]
    $packet[$offset + 1] = $bytes[0]
}

function New-ManeuverPacket($preset, [byte]$command) {
    $packet = New-Object byte[] $packetSize
    $packet[0] = $command
    $packet[1] = 0x03
    $packet[2] = [byte]$preset.Icon
    $packet[3] = [byte]($preset.Direction -band 0xFF)
    Set-Int16BE $packet 4 $preset.Angle
    $packet[6] = 0
    $packet[7] = [byte][Math]::Min($preset.Junctions.Count, 18)
    for ($i = 0; $i -lt $packet[7]; $i++) {
        Set-Int16BE $packet (8 + $i * 2) $preset.Junctions[$i]
    }
    $packet[45] = [byte]$perspective
    $packet[46] = [byte]$bargraphLevel
    $packet[47] = [byte]$bargraphMode
    return ,$packet
}

function Send-Packet([byte[]]$packet, [string]$description) {
    if ($null -eq $stream) { throw "Renderer is not connected" }
    $stream.Write($packet, 0, $packet.Length)
    $stream.Flush()
    Write-Host "-> $description"
}

function Receive-RendererEvents {
    $events = New-Object 'System.Collections.Generic.List[byte]'
    while ($null -ne $stream -and $stream.DataAvailable) {
        $buffer = New-Object byte[] 512
        $count = $stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0) { break }
        for ($i = 0; $i -lt $count; $i++) { $rx.Add($buffer[$i]) }
    }
    while ($rx.Count -ge $packetSize) {
        $eventId = $rx[0]
        $rx.RemoveRange(0, $packetSize)
        $events.Add($eventId)
        if ($eventId -eq 0x81) { Write-Host "<- EVT_READY" }
        elseif ($eventId -eq 0x82) { Write-Host "<- EVT_FRAME_READY" }
    }
    return $events.ToArray()
}

function Wait-RendererEvent([byte]$eventId, [int]$timeoutMs) {
    $deadline = (Get-MonotonicMilliseconds) + $timeoutMs
    while ((Get-MonotonicMilliseconds) -lt $deadline) {
        if ($rendererProcess.HasExited) { throw "Renderer exited with code $($rendererProcess.ExitCode)" }
        if (@(Receive-RendererEvents) -contains $eventId) { return $true }
        Start-Sleep -Milliseconds 20
    }
    return $false
}

function Send-NormalManeuver {
    $preset = $presets[$presetIndex]
    Send-Packet (New-ManeuverPacket $preset 0x01) "CMD_MANEUVER $($preset.Name)"
}

function Send-R3FirstManeuver {
    $preset = $presets[$presetIndex]
    Send-Packet (New-ManeuverPacket $preset 0x07) "CMD_PRELOAD_MANEUVER $($preset.Name)"
    if (-not (Wait-RendererEvent 0x82 1200)) { throw "EVT_FRAME_READY timeout" }
    Start-Sleep -Milliseconds 100
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x08
    Send-Packet $packet "CMD_START_ANIMATION after 100 ms"
}

function Send-Hide {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x09
    Send-Packet $packet "CMD_HIDE_DISPLAY"
}

function Send-Bargraph {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x06
    $packet[2] = [byte]$bargraphLevel
    $packet[3] = [byte]$bargraphMode
    Send-Packet $packet "CMD_BARGRAPH level=$bargraphLevel mode=$bargraphMode"
}

function Send-Perspective {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x04
    $packet[2] = [byte]$perspective
    Send-Packet $packet "CMD_PERSPECTIVE $perspective"
}

function Send-Screenshot([string]$label) {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x02
    $labelBytes = [Text.Encoding]::ASCII.GetBytes($label)
    [Array]::Copy($labelBytes, 0, $packet, 2, [Math]::Min(16, $labelBytes.Length))
    Send-Packet $packet "CMD_SCREENSHOT $label"
}

function Send-DebugGrid {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x05
    $packet[2] = 2
    Send-Packet $packet "CMD_DEBUG grid toggle"
}

function Send-Shutdown {
    $packet = New-Object byte[] $packetSize
    $packet[0] = 0x03
    Send-Packet $packet "CMD_SHUTDOWN"
}

function Add-ScenarioEvent(
    [string]$phase,
    [string]$input,
    [string]$rendererAction,
    [string]$visible,
    [string]$displayed,
    [string]$result
) {
    $script:scenarioStep++
    $script:scenarioEvents.Add([pscustomobject]@{
        Step = $script:scenarioStep
        Phase = $phase
        Input = $input
        RendererAction = $rendererAction
        WindowVisible = $visible
        DisplayedSymbol = $displayed
        ExpectedResult = $result
    })
    Write-Host ("[{0}:{1:00}] {2} -> {3}" -f $script:scenarioMode, $script:scenarioStep, $phase, $result)
}

function Save-ScenarioFrame([string]$label) {
    Start-Sleep -Milliseconds 4200
    Send-Screenshot $label
    Start-Sleep -Milliseconds 220
}

function Run-OriginalComplexScenario {
    $script:scenarioMode = "Original"
    Write-Host "Running complex navigation scenario with upstream/original behavior..."

    $script:bargraphLevel = 0
    $script:bargraphMode = 0
    $script:presetIndex = 0
    Send-NormalManeuver
    Add-ScenarioEvent "Route starts, 4200 m before turn" "Valid route, outside approach zone" `
        "Cold-start FOLLOW_STREET; renderer/context remain exposed" "Yes" "Straight placeholder" `
        "The custom window appears immediately and keeps a straight symbol during the long cruise."
    Save-ScenarioFrame "o01_far"

    $script:presetIndex = 1
    Send-NormalManeuver
    $script:bargraphLevel = 3
    $script:bargraphMode = 1
    Send-Bargraph
    Add-ScenarioEvent "Enter approach at 1450 m" "First real maneuver: right turn" `
        "Normal CMD_MANEUVER transition from FOLLOW_STREET" "Yes" "Right turn" `
        "The real arrow pushes/fades in after the already-visible straight placeholder."
    Save-ScenarioFrame "o02_right"

    $script:bargraphLevel = 14
    $script:bargraphMode = 2
    Send-Bargraph
    Add-ScenarioEvent "80 m before right turn" "Distance update" `
        "Update bargraph to blink mode" "Yes" "Right turn" `
        "The same arrow remains while the distance bar reaches call-for-action blinking."
    Start-Sleep -Milliseconds 700

    $script:presetIndex = 2
    Send-NormalManeuver
    Start-Sleep -Milliseconds 280
    $script:presetIndex = 5
    Send-NormalManeuver
    Add-ScenarioEvent "Dense junction sequence" "Left turn followed 280 ms later by merge right" `
        "Renderer queues the newest maneuver while the previous push is active" "Yes" "Merge right after queued transition" `
        "Intermediate transitions can be visually busy, but the renderer eventually promotes the latest queued maneuver."
    Save-ScenarioFrame "o03_dense"

    Add-ScenarioEvent "Maneuver list becomes empty for 900 ms" "Transient invalid/cleared list" `
        "No hide command in the original protocol" "Yes" "Previous merge-right remains latched" `
        "A stale arrow can remain visible while CarPlay is recalculating or temporarily clears the list."
    Save-ScenarioFrame "o04_invalid"

    $script:presetIndex = 7
    Send-NormalManeuver
    Add-ScenarioEvent "Route recalculated" "New first real maneuver: roundabout" `
        "Normal transition from the stale symbol" "Yes" "Roundabout" `
        "The new route replaces the latched arrow without closing the custom window."
    Save-ScenarioFrame "o05_reroute"

    $script:bargraphLevel = 0
    $script:bargraphMode = 0
    Send-Bargraph
    $script:presetIndex = 0
    Send-NormalManeuver
    Add-ScenarioEvent "Leave approach, next turn 5200 m away" "Valid maneuver outside approach zone" `
        "Send FOLLOW_STREET and leave gfx/context enabled" "Yes" "Straight placeholder" `
        "The custom window stays on for the entire long section."
    Save-ScenarioFrame "o06_cruise"

    Add-ScenarioEvent "Transient route_state=0, recovers after 1200 ms" "Temporary route stop" `
        "Original onStop is lightweight; no hide or renderer shutdown" "Yes" "Straight placeholder" `
        "The window does not react to the transient stop and remains visible."
    Start-Sleep -Milliseconds 1200

    $script:presetIndex = 6
    Send-NormalManeuver
    Add-ScenarioEvent "Recovered route enters approach" "Exit left" `
        "Normal transition" "Yes" "Exit left" `
        "Rendering resumes from the still-visible placeholder."
    Save-ScenarioFrame "o07_recover"

    Add-ScenarioEvent "Navigation ends" "Confirmed route_state=0" `
        "Original route stop keeps renderer/context alive until session shutdown" "Yes" "Last exit-left may remain" `
        "The last symbol can remain until CarPlay disconnect or a later state update clears it."
    Save-ScenarioFrame "o08_end"
    Send-Shutdown
}

function Run-R3ComplexScenario {
    $script:scenarioMode = "R3"
    Write-Host "Running complex navigation scenario with R3 behavior..."

    Add-ScenarioEvent "Route starts, 4200 m before turn" "Valid route, outside approach zone" `
        "Renderer is prepared, but no maneuver is exposed" "No" "None" `
        "The cluster keeps its normal layout; there is no synthetic straight placeholder."
    Start-Sleep -Milliseconds 800

    $script:presetIndex = 1
    $script:bargraphLevel = 3
    $script:bargraphMode = 1
    Send-R3FirstManeuver
    Add-ScenarioEvent "Enter approach at 1450 m" "First real maneuver: right turn" `
        "Preload real arrow -> frame-ready -> 100 ms -> expose -> animate" "Yes" "Right turn" `
        "The window and first real arrow appear as one cold-start animation."
    Save-ScenarioFrame "r01_right"

    $script:bargraphLevel = 14
    $script:bargraphMode = 2
    Send-Bargraph
    Add-ScenarioEvent "80 m before right turn" "Distance update" `
        "Update bargraph to blink mode" "Yes" "Right turn" `
        "Behavior matches the original renderer once R3 is already visible."
    Start-Sleep -Milliseconds 700

    $script:presetIndex = 2
    Send-NormalManeuver
    Start-Sleep -Milliseconds 280
    $script:presetIndex = 5
    Send-NormalManeuver
    Add-ScenarioEvent "Dense junction sequence" "Left turn followed 280 ms later by merge right" `
        "Same renderer queue/transition engine as upstream" "Yes" "Merge right after queued transition" `
        "R3 does not alter normal subsequent-maneuver animation or queue behavior."
    Save-ScenarioFrame "r02_dense"

    Send-Hide
    Add-ScenarioEvent "Maneuver list becomes empty for 900 ms" "Transient invalid/cleared list" `
        "Immediately hide context/gfx; keep renderer prepared" "No" "None" `
        "The stale merge-right arrow is removed instead of remaining latched."
    Start-Sleep -Milliseconds 900

    $script:presetIndex = 7
    $script:bargraphLevel = 8
    $script:bargraphMode = 1
    Send-R3FirstManeuver
    Add-ScenarioEvent "Route recalculated" "New first real maneuver: roundabout" `
        "Fresh real-maneuver preload and one activation sequence" "Yes" "Roundabout" `
        "Re-entry starts from the current route and does not inherit the old arrow/bar state."
    Save-ScenarioFrame "r03_reroute"

    Send-Hide
    Add-ScenarioEvent "Leave approach, next turn 5200 m away" "Valid maneuver outside approach zone" `
        "Hide context/gfx; renderer process remains prepared" "No" "None" `
        "The custom window disappears for the long section."
    Start-Sleep -Milliseconds 800

    Add-ScenarioEvent "Transient route_state=0, recovers after 1200 ms" "Temporary route stop" `
        "Remain hidden; arm 2500 ms shutdown debounce" "No" "None" `
        "Recovery occurs before the debounce expires, so the prepared renderer is reused."
    Start-Sleep -Milliseconds 1200

    $script:presetIndex = 6
    $script:bargraphLevel = 5
    $script:bargraphMode = 1
    Send-R3FirstManeuver
    Add-ScenarioEvent "Recovered route enters approach" "Exit left" `
        "Cancel delayed shutdown; preload current real arrow and expose once" "Yes" "Exit left" `
        "The recovered route gets a clean first-arrow animation with no straight placeholder."
    Save-ScenarioFrame "r04_recover"

    Send-Hide
    Add-ScenarioEvent "Navigation ends" "Confirmed route_state=0" `
        "Hide immediately; fully stop renderer after 2500 ms" "No" "None" `
        "No last-arrow residue remains after navigation finishes."
    Start-Sleep -Milliseconds 2500
    Send-Shutdown
}

function Convert-PpmToPng([string]$ppmPath, [string]$pngPath) {
    Add-Type -AssemblyName PresentationCore
    $bytes = [IO.File]::ReadAllBytes($ppmPath)
    $newlines = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $bytes.Length -and $newlines.Count -lt 3; $i++) {
        if ($bytes[$i] -eq 10) { $newlines.Add($i) }
    }
    if ($newlines.Count -ne 3) { throw "Invalid PPM header: $ppmPath" }

    $dimensions = [Text.Encoding]::ASCII.GetString(
        $bytes, $newlines[0] + 1, $newlines[1] - $newlines[0] - 1).Split(' ')
    $width = [int]$dimensions[0]
    $height = [int]$dimensions[1]
    $pixelOffset = $newlines[2] + 1
    $stride = $width * 3
    $pixels = New-Object byte[] ($stride * $height)
    [Array]::Copy($bytes, $pixelOffset, $pixels, 0, $pixels.Length)

    $bitmap = [Windows.Media.Imaging.BitmapSource]::Create(
        $width, $height, 96, 96, [Windows.Media.PixelFormats]::Rgb24,
        $null, $pixels, $stride)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $output = [IO.File]::Create($pngPath)
    try { $encoder.Save($output) } finally { $output.Dispose() }
}

function Export-ScenarioResults {
    if ($Scenario -eq "None") { return }
    $modeDir = Join-Path $ScenarioOutput $Scenario.ToLowerInvariant()
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $scenarioEvents | Export-Csv -NoTypeInformation -Encoding UTF8 `
        -Path (Join-Path $modeDir "timeline.csv")

    $framePattern = if ($Scenario -eq "Original") { "snap_*_o??_*.ppm" } else { "snap_*_r??_*.ppm" }
    Get-ChildItem -LiteralPath $PSScriptRoot -Filter $framePattern | ForEach-Object {
        $ppmPath = Join-Path $modeDir $_.Name
        Move-Item -Force -LiteralPath $_.FullName -Destination $ppmPath
        $pngPath = [IO.Path]::ChangeExtension($ppmPath, ".png")
        Convert-PpmToPng $ppmPath $pngPath
        Remove-Item -LiteralPath $ppmPath
    }
    Write-Host "Scenario output: $modeDir"
}

function Run-AutomatedTest {
    Write-Host "Running R3 automated sequence..."
    Send-R3FirstManeuver
    Start-Sleep -Milliseconds 4500
    Send-Screenshot "r3_first"
    Start-Sleep -Milliseconds 200
    $script:presetIndex = 2
    Send-NormalManeuver
    Start-Sleep -Milliseconds 4500
    Send-Screenshot "r3_next"
    Start-Sleep -Milliseconds 200
    Send-Hide
    Start-Sleep -Milliseconds 350
    $script:presetIndex = 7
    Send-R3FirstManeuver
    Start-Sleep -Milliseconds 4500
    Send-Screenshot "r3_reenter"
    Start-Sleep -Milliseconds 250
    Receive-RendererEvents | Out-Null
    Send-Shutdown
}

function Show-Help {
    Write-Host ""
    Write-Host "F     R3 first real maneuver (preload, frame-ready, 100 ms, animate)"
    Write-Host "E     Hide, select next preset, then R3 re-enter"
    Write-Host "H     Hide preview window"
    Write-Host "Left/Right  Select and send normal subsequent maneuver"
    Write-Host "Up/Down     Adjust bargraph"
    Write-Host "B     Cycle bargraph mode   P  Toggle perspective"
    Write-Host "S     Screenshot            G  Toggle debug grid"
    Write-Host "A     Automated R3 sequence Q  Quit"
    Write-Host ""
}

try {
    if (-not (Test-Path -LiteralPath $Renderer)) {
        throw "Renderer not found: $Renderer. Run compile_render_windows.ps1 first."
    }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
    $listener.Start()
    Write-Host "Harness listening on 127.0.0.1:$port"

    $env:CR_LOCAL_SCALE = [string]$Scale
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [IO.Path]::GetFullPath($Renderer)
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $rendererProcess = [Diagnostics.Process]::Start($startInfo)

    $deadline = (Get-MonotonicMilliseconds) + 5000
    while (-not $listener.Pending()) {
        if ($rendererProcess.HasExited) { throw "Renderer exited with code $($rendererProcess.ExitCode)" }
        if ((Get-MonotonicMilliseconds) -ge $deadline) { throw "Renderer connection timeout" }
        Start-Sleep -Milliseconds 25
    }
    $client = $listener.AcceptTcpClient()
    $client.NoDelay = $true
    $stream = $client.GetStream()
    Write-Host "Renderer connected"
    if (-not (Wait-RendererEvent 0x81 2500)) { throw "EVT_READY timeout" }

    if ($Scenario -eq "Original") {
        Run-OriginalComplexScenario
    } elseif ($Scenario -eq "R3") {
        Run-R3ComplexScenario
    } elseif ($AutoTest) {
        Run-AutomatedTest
    } else {
        Show-Help
        while (-not $rendererProcess.HasExited) {
            Receive-RendererEvents | Out-Null
            if (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 25
                continue
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "F" { Send-R3FirstManeuver }
                "E" {
                    Send-Hide
                    Start-Sleep -Milliseconds 300
                    $presetIndex = ($presetIndex + 1) % $presets.Count
                    Send-R3FirstManeuver
                }
                "H" { Send-Hide }
                "RightArrow" {
                    $presetIndex = ($presetIndex + 1) % $presets.Count
                    Send-NormalManeuver
                }
                "LeftArrow" {
                    $presetIndex = ($presetIndex - 1 + $presets.Count) % $presets.Count
                    Send-NormalManeuver
                }
                "UpArrow" { if ($bargraphLevel -lt 16) { $bargraphLevel++ }; Send-Bargraph }
                "DownArrow" { if ($bargraphLevel -gt 0) { $bargraphLevel-- }; Send-Bargraph }
                "B" { $bargraphMode = ($bargraphMode + 1) % 3; Send-Bargraph }
                "P" { $perspective = 1 - $perspective; Send-Perspective }
                "S" { Send-Screenshot $presets[$presetIndex].Name }
                "G" { Send-DebugGrid }
                "A" { Run-AutomatedTest; break }
                "Q" { Send-Shutdown; break }
                "Escape" { Send-Shutdown; break }
            }
        }
    }

    [void]$rendererProcess.WaitForExit(2500)
    Write-Host "Renderer exit code: $($rendererProcess.ExitCode)"
    Export-ScenarioResults
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $listener) { $listener.Stop() }
    if ($null -ne $rendererProcess -and -not $rendererProcess.HasExited) {
        $rendererProcess.Kill()
        [void]$rendererProcess.WaitForExit(1000)
    }
}

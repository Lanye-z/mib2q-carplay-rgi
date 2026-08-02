param(
    [string]$Renderer = (Join-Path $PSScriptRoot "c_render_windows.exe"),
    [ValidateRange(1, 4)][int]$Scale = 2,
    [switch]$AutoTest
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

    if ($AutoTest) {
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
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $listener) { $listener.Stop() }
    if ($null -ne $rendererProcess -and -not $rendererProcess.HasExited) {
        $rendererProcess.Kill()
        [void]$rendererProcess.WaitForExit(1000)
    }
}

$path = 'c:\Users\wh\Documents\whgame_Tetris-godot\scenes\ui\game_over_panel.tscn'
$bytes = [System.IO.File]::ReadAllBytes($path)

# Check BOM
Write-Host "=== BOM Check ==="
Write-Host "First 3 bytes: $($bytes[0]) $($bytes[1]) $($bytes[2])"
$hasBOM = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
Write-Host "Has UTF-8 BOM: $hasBOM"

# Check for null bytes
Write-Host "`n=== Null Byte Check ==="
$nullCount = 0
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 0) {
        $nullCount++
        Write-Host "Null byte at offset: $i"
    }
}
Write-Host "Total null bytes: $nullCount"

# Check for non-ASCII bytes (excluding BOM)
Write-Host "`n=== Non-ASCII Byte Check ==="
$nonAscii = 0
$startIdx = 0
if ($hasBOM) { $startIdx = 3 }
for ($i = $startIdx; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -gt 127) {
        $nonAscii++
        # Show context: the line
        $lineStart = $i
        while ($lineStart -gt 0 -and $bytes[$lineStart-1] -ne 10) { $lineStart-- }
        $lineEnd = $i
        while ($lineEnd -lt $bytes.Length -and $bytes[$lineEnd] -ne 13 -and $bytes[$lineEnd] -ne 10) { $lineEnd++ }
        $lineBytes = $bytes[$lineStart..($lineEnd-1)]
        $lineText = [System.Text.Encoding]::UTF8.GetString($lineBytes)
        Write-Host "Non-ASCII at offset $i (byte value: $($bytes[$i])): $lineText"
    }
}
Write-Host "Total non-ASCII bytes: $nonAscii"

# Parse header
Write-Host "`n=== Header Check ==="
$text = [System.IO.File]::ReadAllText($path)
$lines = $text.Split("`n")
Write-Host "Total lines: $($lines.Length)"
Write-Host "First line: $($lines[0].Trim())"

# Check load_steps vs actual resources
Write-Host "`n=== Resource Count Check ==="
$extResCount = ([regex]::Matches($text, '\[ext_resource')).Count
$subResCount = ([regex]::Matches($text, '\[sub_resource')).Count
$nodeCount = ([regex]::Matches($text, '\[node ')).Count
Write-Host "ext_resource count: $extResCount"
Write-Host "sub_resource count: $subResCount"
Write-Host "node count: $nodeCount"

# Check if gd_scene header has load_steps
$headerMatch = [regex]::Match($text, '\[gd_scene(.+?)\]')
Write-Host "Header: $($headerMatch.Value)"

# Check for format version
Write-Host "`n=== Format Check ==="
if ($text -match 'format=(\d+)') {
    Write-Host "Format version: $($Matches[1])"
}

# Check unique_id values - are they valid?
Write-Host "`n=== Unique ID Check ==="
$uidMatches = [regex]::Matches($text, 'unique_id=(\d+)')
foreach ($m in $uidMatches) {
    Write-Host "unique_id: $($m.Groups[1].Value)"
}

# Check for load_steps
Write-Host "`n=== Load Steps Check ==="
if ($text -match 'load_steps=(\d+)') {
    Write-Host "load_steps declared: $($Matches[1])"
    $expected = $extResCount + $subResCount + 1
    Write-Host "Expected (ext + sub + 1): $expected"
} else {
    Write-Host "No load_steps in header"
    Write-Host "This might be the issue! Godot 4 scenes need load_steps"
}

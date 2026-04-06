$path = 'c:\Users\wh\Documents\whgame_Tetris-godot\scenes\ui\game_over_panel.tscn'
$bytes = [System.IO.File]::ReadAllBytes($path)

# Check and remove BOM
$startIdx = 0
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "Removing UTF-8 BOM..."
    $startIdx = 3
}

# Get text without BOM
$text = [System.Text.Encoding]::UTF8.GetString($bytes, $startIdx, $bytes.Length - $startIdx)

# Normalize all line endings to LF (matching other tscn files in the project)
$text = $text.Replace("`r`n", "`n")
$text = $text.Replace("`r", "`n")

# Trim trailing whitespace/newlines and ensure single trailing newline
$text = $text.TrimEnd() + "`n"

# Write back without BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $text, $utf8NoBom)

# Verify
$newBytes = [System.IO.File]::ReadAllBytes($path)
Write-Host "Original size: $($bytes.Length) bytes"
Write-Host "New size: $($newBytes.Length) bytes"
Write-Host "First 3 bytes: $($newBytes[0]) $($newBytes[1]) $($newBytes[2])"
$hasBOM = ($newBytes[0] -eq 0xEF -and $newBytes[1] -eq 0xBB -and $newBytes[2] -eq 0xBF)
Write-Host "Has BOM: $hasBOM"

# Count line endings
$crlfCount = 0
$lfCount = 0
for ($i = 0; $i -lt $newBytes.Length; $i++) {
    if ($newBytes[$i] -eq 10) {
        if ($i -gt 0 -and $newBytes[$i-1] -eq 13) {
            $crlfCount++
        } else {
            $lfCount++
        }
    }
}
Write-Host "CRLF count: $crlfCount"
Write-Host "LF count: $lfCount"
Write-Host "Done!"

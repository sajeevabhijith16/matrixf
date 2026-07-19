$path = 'lib\src\components\module_text_renderer.dart'
$lines = Get-Content $path
$newlines = @()
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($i -eq 4) {
        $newlines += "import 'text_blocks.dart';"
    }
    if ($i -ge 6 -and $i -le 229) {
        continue
    }
    $newlines += $lines[$i]
}
$newlines | Set-Content $path -Encoding UTF8

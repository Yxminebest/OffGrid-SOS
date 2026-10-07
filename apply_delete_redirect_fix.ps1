$ErrorActionPreference = "Stop"

$project = (Get-Location).Path
$file = Join-Path $project "lib\features\profile\account_settings_screen.dart"

if (-not (Test-Path $file)) {
  throw "Target file not found: $file"
}

$text = [System.IO.File]::ReadAllText($file)

$already = @"
      final navigator = Navigator.of(context, rootNavigator: true);
      await widget.onDeleted();
      navigator.popUntil((route) => route.isFirst);
"@

if ($text.Contains($already)) {
  Write-Host "Delete redirect fix is already applied." -ForegroundColor Green
  exit 0
}

$old = @"
      if (!mounted) return;

      await widget.onDeleted();
"@

$new = @"
      if (!mounted) return;

      final navigator = Navigator.of(context, rootNavigator: true);
      await widget.onDeleted();
      navigator.popUntil((route) => route.isFirst);
"@

if (-not $text.Contains($old)) {
  throw "Expected delete-account block was not found. No file was changed."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "$file.before_delete_redirect_$stamp.bak"
Copy-Item $file $backup -Force

$text = $text.Replace($old, $new)
[System.IO.File]::WriteAllText(
  $file,
  $text,
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Delete redirect fix applied successfully." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next commands:"
Write-Host "  dart format lib\features\profile\account_settings_screen.dart"
Write-Host "  flutter analyze"

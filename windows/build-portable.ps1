$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot "MediaShelf.Windows/MediaShelf.Windows.csproj"
$output = Join-Path $root "dist/MediaShelf-Windows"

dotnet test (Join-Path $PSScriptRoot "MediaShelf.Windows.Tests/MediaShelf.Windows.Tests.csproj") -c Release
dotnet publish $project -c Release -r win-x64 --self-contained true -o $output

$archive = Join-Path $root "dist/MediaShelf-Windows-x64.zip"
if (Test-Path $archive) { Remove-Item $archive }
Compress-Archive -Path $output -DestinationPath $archive
Write-Host "Portable build: $archive"

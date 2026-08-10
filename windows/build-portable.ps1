$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot "MediaShelf.Windows/MediaShelf.Windows.csproj"
$output = Join-Path $root "dist/MediaShelf-Windows"

dotnet test (Join-Path $PSScriptRoot "MediaShelf.Windows.Tests/MediaShelf.Windows.Tests.csproj") -c Release
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $output

$executable = Join-Path $output "MediaShelf.exe"
Write-Host "Portable build: $executable"

param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "QuickHighlight/QuickHighlight.csproj"
$publishDir = Join-Path $root "artifacts/publish"
$zipPath = Join-Path $root "artifacts/QuickHighlight-win-x64.zip"

if (Test-Path (Join-Path $root "artifacts")) {
    Remove-Item (Join-Path $root "artifacts") -Recurse -Force
}

dotnet publish $project `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $publishDir

Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath -Force
Write-Host "Built $zipPath"

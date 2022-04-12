$Url = "https://go.eset.eu/ecp-ads"
$OutDir = Join-Path -Path "AzureADScanner" -ChildPath "ADScanner"
$ZipFile = Join-Path -Path $OutDir -ChildPath "adscanner.zip"
$ADScannerDir = Join-Path -Path $OutDir -ChildPath "ActiveDirectoryScanner"

Invoke-WebRequest -Uri $Url -OutFile $ZipFile
[IO.Compression.Zipfile]::ExtractToDirectory($ZipFile, $OutDir, $true);
Move-Item -Path "$ADScannerDir\*" -Destination $OutDir -Force
Remove-Item -Path $ADScannerDir, $ZipFile
$Url = "https://go.eset.eu/ecp-ads"
$OutDir = "AzureADScanner"
$ZipFile = Join-Path -Path $OutDir -ChildPath "adscanner.zip"

Invoke-WebRequest -Uri $Url -OutFile $ZipFile
[IO.Compression.Zipfile]::ExtractToDirectory($ZipFile, $OutDir, $true); , $ZipFile
Remove-Item $ZipFile
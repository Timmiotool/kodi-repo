# Erzeugt addons.xml und addons.xml.md5 aus den Addon-ZIPs im Repo-Ordner.
#
# Erwartete Struktur (Skript liegt im Hauptordner des Repos):
#   addon.id\addon.id-1.0.0.zip   (darin: addon.id\addon.xml)
# Pro Ordner wird die ZIP mit der höchsten Version verwendet.

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ordner = $PSScriptRoot
$xmlPfad = Join-Path $ordner 'addons.xml'
$md5Pfad = Join-Path $ordner 'addons.xml.md5'

function Get-Version([string]$text) {
    try { return [version]$text } catch { return [version]'0.0.0' }
}

# ZIPs, die direkt im Hauptordner liegen, in den Ordner ihrer Addon-ID verschieben
foreach ($zip in Get-ChildItem -Path $ordner -Filter '*.zip' -File) {
    $archiv = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
    try {
        $eintrag = $archiv.Entries | Where-Object { $_.FullName -match '^[^/\\]+[/\\]addon\.xml$' } | Select-Object -First 1
        if (-not $eintrag) {
            Write-Host "Übersprungen (keine addon.xml in der ZIP): $($zip.Name)" -ForegroundColor Yellow
            continue
        }
        $leser = New-Object System.IO.StreamReader($eintrag.Open(), [System.Text.Encoding]::UTF8)
        $inhalt = $leser.ReadToEnd()
        $leser.Close()
    } finally {
        $archiv.Dispose()
    }
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.LoadXml($inhalt) } catch {
        Write-Host "Übersprungen (addon.xml fehlerhaft): $($zip.Name)" -ForegroundColor Yellow
        continue
    }
    $id = $doc.DocumentElement.GetAttribute('id')
    if (-not $id) { continue }
    $ziel = Join-Path $ordner $id
    New-Item -ItemType Directory -Path $ziel -Force | Out-Null
    Move-Item -Path $zip.FullName -Destination (Join-Path $ziel $zip.Name) -Force
    Write-Host "Verschoben: $($zip.Name)  ->  $id\" -ForegroundColor Cyan
}

$eintraege = @()

foreach ($dir in Get-ChildItem -Path $ordner -Directory | Sort-Object Name) {
    $zips = Get-ChildItem -Path $dir.FullName -Filter '*.zip' -File
    if (-not $zips) { continue }

    $besteZip = $null
    $besteVersion = [version]'0.0.0'
    $besteXml = $null

    foreach ($zip in $zips) {
        $archiv = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
        try {
            $eintrag = $archiv.Entries | Where-Object { $_.FullName -match '^[^/\\]+[/\\]addon\.xml$' } | Select-Object -First 1
            if (-not $eintrag) {
                Write-Host "Übersprungen (keine addon.xml in der ZIP): $($zip.Name)" -ForegroundColor Yellow
                continue
            }
            $leser = New-Object System.IO.StreamReader($eintrag.Open(), [System.Text.Encoding]::UTF8)
            $inhalt = $leser.ReadToEnd()
            $leser.Close()
        } finally {
            $archiv.Dispose()
        }

        $doc = New-Object System.Xml.XmlDocument
        try { $doc.LoadXml($inhalt) } catch {
            Write-Host "Übersprungen (addon.xml fehlerhaft): $($zip.Name)" -ForegroundColor Yellow
            continue
        }
        $version = Get-Version $doc.DocumentElement.GetAttribute('version')
        if (-not $besteZip -or $version -gt $besteVersion) {
            $besteZip = $zip
            $besteVersion = $version
            $besteXml = $doc.DocumentElement.OuterXml
        }
    }

    if ($besteXml) {
        Write-Host ("Gefunden: {0}  ->  {1}" -f $dir.Name, $besteZip.Name) -ForegroundColor Cyan
        $eintraege += $besteXml
    }
}

if ($eintraege.Count -eq 0) {
    Write-Host "Fehler: Keine Addon-ZIPs gefunden in $ordner" -ForegroundColor Red
    exit 1
}

$ausgabe = "<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"yes`"?>`n<addons>`n" +
           ($eintraege -join "`n") + "`n</addons>`n"

# UTF-8 ohne BOM schreiben
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($xmlPfad, $ausgabe, $utf8)

# MD5 der addons.xml: nur die Prüfsumme, ohne Zeilenumbruch
$hash = (Get-FileHash -Path $xmlPfad -Algorithm MD5).Hash.ToLower()
[System.IO.File]::WriteAllText($md5Pfad, $hash, (New-Object System.Text.ASCIIEncoding))

Write-Host ""
Write-Host "addons.xml erstellt mit $($eintraege.Count) Addon(s)." -ForegroundColor Green
Write-Host "addons.xml.md5 erstellt: $hash" -ForegroundColor Green

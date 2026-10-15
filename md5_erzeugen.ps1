# Erzeugt addons.xml und addons.xml.md5 aus den Addon-ZIPs im Repo-Ordner.
#
# Erwartete Struktur (Skript liegt im Hauptordner des Repos):
#   addon.id\addon.id-1.0.0.zip   (darin: addon.id\addon.xml)
# Pro Addon-Ordner werden die letzten $MaxVersionen ZIPs behalten, aeltere ZIPs werden geloescht.
# Alle behaltenen Versionen kommen in die addons.xml (so kann Kodi ueber "Versionen" ein Downgrade anbieten).

$MaxVersionen = 5

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ordner = $PSScriptRoot
$xmlPfad = Join-Path $ordner 'addons.xml'
$md5Pfad = Join-Path $ordner 'addons.xml.md5'

function Get-Version([string]$text) {
    try { return [version]$text } catch { return [version]'0.0.0' }
}

# Liest die addon.xml aus einer ZIP. Gibt $null zurueck, wenn sie fehlt oder fehlerhaft ist.
function Get-AddonXml([string]$zipPfad) {
    $archiv = [System.IO.Compression.ZipFile]::OpenRead($zipPfad)
    try {
        $eintrag = $archiv.Entries | Where-Object { $_.FullName -match '^[^/\\]+[/\\]addon\.xml$' } | Select-Object -First 1
        if (-not $eintrag) { return $null }
        $leser = New-Object System.IO.StreamReader($eintrag.Open(), [System.Text.Encoding]::UTF8)
        $inhalt = $leser.ReadToEnd()
        $leser.Close()
    } finally {
        $archiv.Dispose()
    }
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.LoadXml($inhalt) } catch { return $null }
    return $doc
}

# ZIPs, die direkt im Hauptordner liegen, in den Ordner ihrer Addon-ID verschieben
foreach ($zip in Get-ChildItem -Path $ordner -Filter '*.zip' -File) {
    $doc = Get-AddonXml $zip.FullName
    if (-not $doc) {
        Write-Host "Uebersprungen (addon.xml fehlt oder fehlerhaft): $($zip.Name)" -ForegroundColor Yellow
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
$anzahlAddons = 0

foreach ($dir in Get-ChildItem -Path $ordner -Directory | Sort-Object Name) {
    $zips = Get-ChildItem -Path $dir.FullName -Filter '*.zip' -File
    if (-not $zips) { continue }

    $liste = @()
    foreach ($zip in $zips) {
        $doc = Get-AddonXml $zip.FullName
        if (-not $doc) {
            Write-Host "Uebersprungen (addon.xml fehlt oder fehlerhaft): $($zip.Name)" -ForegroundColor Yellow
            continue
        }
        $liste += [pscustomobject]@{
            Zip     = $zip
            Version = Get-Version $doc.DocumentElement.GetAttribute('version')
            Xml     = $doc.DocumentElement.OuterXml
        }
    }
    if (-not $liste) { continue }

    # neueste zuerst; die ersten $MaxVersionen behalten, den Rest loeschen
    $sortiert = @($liste | Sort-Object -Property Version -Descending)
    $behalten = @($sortiert | Select-Object -First $MaxVersionen)
    $loeschen = @($sortiert | Select-Object -Skip $MaxVersionen)

    foreach ($alt in $loeschen) {
        Remove-Item -LiteralPath $alt.Zip.FullName -Force
        Write-Host ("Geloescht (aelter als die letzten {0}): {1}" -f $MaxVersionen, $alt.Zip.Name) -ForegroundColor Magenta
    }

    # in addons.xml: aelteste Version zuerst, neueste zuletzt
    foreach ($v in @($behalten | Sort-Object -Property Version)) {
        $eintraege += $v.Xml
    }
    $anzahlAddons++
    Write-Host ("Gefunden: {0}  ->  {1} Version(en), neueste: {2}" -f $dir.Name, $behalten.Count, $behalten[0].Zip.Name) -ForegroundColor Cyan
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

# MD5 der addons.xml: nur die Pruefsumme, ohne Zeilenumbruch
$hash = (Get-FileHash -Path $xmlPfad -Algorithm MD5).Hash.ToLower()
[System.IO.File]::WriteAllText($md5Pfad, $hash, (New-Object System.Text.ASCIIEncoding))

Write-Host ""
Write-Host "addons.xml erstellt mit $($eintraege.Count) Eintraegen fuer $anzahlAddons Addon(s)." -ForegroundColor Green
Write-Host "addons.xml.md5 erstellt: $hash" -ForegroundColor Green
param(
  [Parameter(Mandatory=$True)]
  $FileName,
  $NumFiles=2,
  $TrackPointsPerFile=500
)

$ErrorActionPreference = "Stop"

if((Test-Path $FileName) -eq $false) {
  write-error "Can't find file $FileName"
  return
}

$xmlTemplate = @"
<?xml version="1.0"?>
<gpx version="1.0" creator="cycle.travel"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://www.topografix.com/GPX/1/0"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd">
  <trk>
  <name>Trip</name>
</trk>
</gpx>
"@

$fileNameStub = ([io.fileinfo]$filename).basename
$outputFiles = @()

#Skip splitting if only target file
if($NumFiles -eq 1) {
  $outputFiles += $FileName
}
else {
  $gpxXml = [xml](gc $FileName)
  $trackName = $gpxXml.gpx.trk.name
  $totalNumTrkpts = $gpxXml.gpx.trk.trkseg.trkpt | measure | select -expand count
  $trkptsPerFile = [int]($totalNumTrkpts / $NumFiles)
  write-host "$fileName has $totalNumTrkpts trkpts - will split into $trkptsPerFile per file"

  for($i = 0; $i -lt $numFiles; $i++) {
    $newGpx = [xml]$xmlTemplate
    $newGpx.gpx.trk.name = $trackName
    $start = $trkptsPerFile * $i
    $segments =  $gpxXml.gpx.trk.trkseg.trkpt | select -First $trkptsPerFile -Skip $start
    $trksegElem = $newGpx.CreateElement("trkseg")

    foreach($segment in $segments) {
      $elem = $newGpx.ImportNode($segment, $true)
      $trksegElem.appendChild($elem) | out-null
    }
    $newGpx.gpx.trk.appendChild($trksegElem) | out-null

    $outputFileName = "{0}_part{1}.gpx" -f $fileNameStub, ($i + 1)
    $newGpx.outerxml | out-file $outputFileName -Force
    write-host "Written $outputFileName"
    $outputFiles += $outputFileName
  }
}

#Now simplify to N points using gpsbabel
$zippedOutputFiles = @()
foreach($file in $outputFiles) {
  $outputFileName = "{0}_simplify.gpx" -f ([io.fileinfo]$file).basename
  & gpsbabel -r -i gpx -f $file -x simplify`,count=$TrackPointsPerFile -o gpx -F $outputFileName
  write-host "Simplified file $file to $TrackPointsPerFile points"
  $zippedOutputFiles += $outputFileName
}

#Then Zip
$outputZipName = "{0}_output.zip" -f $fileNameStub
zip -r $outputZipName ($zippedOutputFiles -split " ")

write-host "Zip saved to $outputZipName"

#Cleanup
$zippedOutputFiles | remove-item
if($NumFiles -gt 1) {
  $outputFiles | remove-item
}

##################################################################################
###### Campsites Near Route.ps1
###### Filter list of Archies Europe campsites that are close to a given route
######
###### Written by: Robin Watkins (@robwatkins)
###### More details: TODO
######
######
##################################################################################

#### Useful variables
$PathToArchies = "Y:\Dropbox\Holiday Docs\Bike Touring PowerShell\Campsites\archies_europe.csv"
$PathToRouteGPX =  "Y:\Dropbox\Holiday Docs\Bike Touring PowerShell\Campsites\WholeRoute.GPX"
$PathToGPSBabel = "C:\program files (x86)\gpsbabel\gpsbabel.exe"
$OutputFile = "Y:\Dropbox\Holiday Docs\Bike Touring PowerShell\Campsites\Campsites.gpx"
$RecreateCampsiteTable = $false
$numPoints = 500 #Number of points to use in simplified GPX of route

$ServerInstance = "." #SQL Server instance name
$Database = "ArchiesCamping" #Name of database on SQL Server instance
$DistanceFromRouteInMeters = 30000 #How far from the route you want to include campsites

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

if(!(Test-Path -PathType Leaf -Path $PathToArchies)) {
    write-error "Unable to find Archies CSV at $PathToArchies"
}

if(!(Test-Path -PathType Leaf -Path $PathToRouteGPX)) {
    write-error "Unable to find route GPX at $PathToRouteGPX"
}

if(!(Test-Path -PathType Leaf -Path $PathToGPSBabel)) {
    write-error "Unable to find GPSBabel.exe at $PathToGPSBabel"
}

if((get-module -ListAvailable -Name sqlps) -eq $null) {
    write-error "Cannot find SQLPS module"
}

### SQLPS overwrites your pwd which is annoying
$currentlocation = get-location
if((get-module sqlps) -eq $null) 
{
    import-module sqlps
}
set-location $currentlocation

Write-Verbose "Creating SQL Server Tables..."

####### Create tables in SQL Server
$query = "IF EXISTS(SELECT * FROM sys.tables WHERE name='TheRoute') BEGIN
            DROP TABLE TheRoute
            END
            CREATE TABLE TheRoute(line geography)"
invoke-sqlcmd -serverinstance $ServerInstance -database $Database -query $query | out-null

$campsiteTableExists = invoke-sqlcmd -serverinstance $ServerInstance -database $Database -query "SELECT COUNT(*) as count from sys.tables where name='Campsites'" 

$campsiteTableExists = $campsiteTableExists.count -eq 1

if($RecreateCampsiteTable -or !$campsiteTableExists) {
    $query = "IF EXISTS(SELECT * FROM sys.tables WHERE name='Campsites') BEGIN
                DROP TABLE Campsites
                END
                CREATE TABLE [dbo].[Campsites](
	                [ID] [int] IDENTITY(1,1) NOT NULL,
	                [Name] [nvarchar](255) NULL,
	                [Location] [geography] NULL,
	                [Lat] [numeric](9, 6) NULL,
	                [Lon] [numeric](9, 6) NULL
                )"

    invoke-sqlcmd -serverinstance $ServerInstance -database $Database -query $query | out-null

    Write-Verbose "Importing campsites from $PathToArchies into SQLServer ..."

    ######## Convert archies europe points to a list of PSobjects using import-csv
    $points = import-csv $PathToArchies -header Lon,Lat,Name

    #### Now load all points into table as Geography type and include Lat/Lon for future retrieval
    foreach($point in $points) {
        $newName = $point.Name -replace "'","''"
        $query = "insert into Campsites(Name, Lat, Lon, Location) values ('{0}',{1},{2}, geography::Point({1},{2}, 4326))" -f $newName,$point.Lat,$point.Lon
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $query
    }
}

Write-Verbose "Simplifying GPX to $numPoints points ..."

##### Now you have to load the route we are cycling into SQL server table called TheRoute, column line
##### I exported our cycle route as a GPX *track* now simplify to 500 points using GPSBabel
$simplifyfilename = $PathToRouteGPX -replace ".gpx","_simplify.gpx"

& $PathToGPSBabel -r -i gpx -f $PathToRouteGPX -x simplify`,count=$numPoints -o gpx -F $simplifyfilename

Write-Verbose "Importing simplified GPX into SQLServer ..."

$route = [xml] (gc $simplifyfilename)

##### Buildup a LINESTRING variable for the INSERT statement
$linestring = "LINESTRING ("
$linestring += ($x.gpx.trk.trkseg.trkpt | % { "{0} {1}" -f [double]$_.Lon,[double]$_.Lat }) -join ","
$linestring += ")"

#### Insert data into SQL Server table, making it valid at the same time
$query = "DECLARE @validGeom geometry;
SET @validGeom = geometry::STLineFromText('$linestring', 4326);
DECLARE @validGeo geography;
SET @validGeo = geography::STGeomFromText(@validGeom.STAsText(), 4326).MakeValid();
DECLARE @placemark geography;
SET @placemark = @validGeo;

INSERT INTO TheRoute (line) VALUES (@placemark)"

$results = invoke-sqlcmd -serverinstance $ServerInstance -database $Database -query $query


Write-Verbose "Retrieving all campsites $DistanceFromRouteInMetres m from the route ..."

$query = "declare @theRoute geography
select @theRoute = Line from dbo.TheRoute

select Name,lat,lon from dbo.campsites c where c.location.STDistance(@theRoute) < $DistanceFromRouteInMeters"

$results = invoke-sqlcmd -serverinstance $ServerInstance -database $Database -query $query

#### Create a very basic GPX with list of points which can then be reimported into Basecamp
Write-Verbose "Saving to file $outputFile ..."

$xml = '<?xml version="1.0" ?><gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd" version="1.1">'

$results | select Lon,Lat,Name | foreach-object `
     {
        ##### Escape some special chars to stop BaseCamp from failing to import GPX
        $name = $_.Name
        $name = $Name -replace "<","&lt;"
        $name = $Name -replace ">","&gt;"
        $xml += '<wpt lon="{0}" lat="{1}"><name>{2}</name><sym>Campground</sym></wpt>' -f $_.Lon,$_.Lat,$name 
     
     }
$xml += '</gpx>'

$xml | Out-File -Encoding UTF8 -FilePath $OutputFile -Force

Write-Verbose "Done!"



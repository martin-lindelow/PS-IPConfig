
## Sökvägar
$ScriptPath = $PSScriptRoot 
$ConfigFile = Join-Path -Path $ScriptPath -ChildPath "Config.json"
$ConfigData = $null

## Globala Funktioner

# Funktion för att convertera två arrayer till ett ps objekt
function Convert-ArrayToObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$Titles, # Titlar/Namn
        
        [Parameter(Mandatory=$true, Position=1)]
        [object[][]]$Data # Tvådimensionella array med data
    )

    # Kontrollera att all data har titlar/namn
    if ($Data[0].Count -ne $Titles.Count) {
        Write-Error "Antalet titlar/namn ($($Titles.Count)) matchar inte antalet kolumner i datan ($($Data[0].Count))."
        return
    }

    $ResultObjects = 
    foreach ($Row in $Data) {
        
        # Skapa en ordnad hashtabell för att lagra Key/Value-par för det aktuella objektet
        $HashTable = [ordered]@{ }
        
        # Loopa igenom titlarna
        for ($i = 0; $i -lt $Titles.Count; $i++) {
            
            $Title = $Titles[$i]
            $Value = $Row[$i]
            
            # Lägg till paret i hashtabellen.
            $HashTable.Add($Title, $Value)
        }

        # Konvertera hashtabellen till ett PSCustomObject och skicka till pipelinen
        [PSCustomObject]$HashTable
    }

    return $ResultObjects
}

# Funktion för att skriva titel och beskrivning för aktuell menyn
function Write-Title {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Title,
		
        [Parameter(Mandatory=$false, Position=1)]
        [string]$Body,
		
        [Parameter(Mandatory=$false)]
        [string]$TitleColor="Magenta",
		
        [Parameter(Mandatory=$false)]
        [string]$BodyColor="Cyan"
    )
	Clear-Host
    Write-Host "`n--- $($Title.ToUpper()) ---" -ForegroundColor $TitleColor
	if ($Body){
		Write-Host "$Body`n" -ForegroundColor $BodyColor
	}
}

# Funktion för att skriva en notis till användaren
function Write-Notice {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Notice,
		
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor="White",
		
        [Parameter(Mandatory=$false)]
        [float]$SleepTime=1.5
    )
	
	Write-Host $Notice -ForegroundColor $ForegroundColor
	Start-Sleep -Seconds $SleepTime
}

# Funktion för att skapa en lista över systemets nätverkskort. 
function Get-SystemAdapters {
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string[]]$ExcludeNames
    )
        
	return Get-NetAdapter | Where-Object {$_.Name -notin $ExcludeNames} | Where-Object {$_.Status -ne "Not Present"}

}

# Funktion som tar en lista av nätverkskortssnamn och hämtar ip-adresser
function Format-IPList {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$AdapterNames
    )
	
	$ResultList = @()
    
    foreach ($Adapter in $AdapterNames) {
        
        # Hämta IP-adresser för det aktuella kortet
		try {
			$IPConfig = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $Adapter
			
			# Läs ut IP-adressen
			if ($IPConfig.PrefixOrigin) {
				# DHCP?
				if ($IPConfig.PrefixOrigin -eq "Manual"){
					$DHCPStatus = "Nej"
				} else {
					$DHCPStatus = "Ja"
				}
				# Kopiera IP-Adress
				$CurrentIP = $IPConfig[0].IPAddress
			} else {
				$CurrentIP = "-"
				$DHCPStatus = "-"
			}
		}
		catch {
			Write-Notice "`nFel vid läsning av IP-adress." -ForegroundColor Red
            $CurrentIP = "-"
			$DHCPStatus = "-"
		}
        
        # Skapa ett nytt objekt med nätverkskortets namn och den aktuella IP-adressen
        $AdapterObject = [PSCustomObject]@{
            Nätverkskort = $Adapter
            "Aktuell IP" = $CurrentIP
			DHCP = $DHCPStatus
        }
		
        # Kopiera till array
        $ResultList += $AdapterObject
    }    
	Return $ResultList
}

# Funktion för att läsa användar input
function Read-RequiredInput {
    param(
		[Parameter(Mandatory=$true, Position=0)]
        [string]$Prompt,
		
        [Parameter(Mandatory=$false)]
        [string]$DefaultValue = ""
    )
    do {
        $Input = Read-Host $Prompt $(if ($DefaultValue) {"Standardvärde: '$DefaultValue'"})
		
		# Ska standardvärde användas
        if (-not $Input -and $DefaultValue) { $Input = $DefaultValue }
		
		# Data inmatad?
        if (-not [string]::IsNullOrWhiteSpace($Input)) {
            return $Input.Trim()
        }
		
		# Ingen data inmatad
        Write-Notice -Notice "Ingen data inmatad. Försök igen." -ForegroundColor Red
    } while ($true)
}

# Funktion för användarval. Q/q avbryter val
function Read-UserChoice {
    [CmdletBinding()]
    param(
		# Array med strängar eller objekt
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Choices,
        
		# Rubrik för menyn
        [Parameter(Mandatory=$false)]
        [string]$Title = "Gör ett val:",
        
		# Vilka kolumner/vilken data som ska visas vid objekt i Choices
        [Parameter(Mandatory=$false)]
        [string[]]$DisplayProperties = @(),
		
		# Ska "Klar" visas
        [Parameter(Mandatory=$false)]
        [bool[]]$ShowDone = $false,
		
		# Ska "Titlar" visas
        [Parameter(Mandatory=$false)]
        [bool[]]$ShowTitles = $false
    )

	# Initiera variablerna
    $MenuList = @()
    $MaxChoice = 0
    $DisplayHeaders = @("#")

    # Förbered objekten för Format-Table
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $Index = $i + 1
        $MaxChoice = $Index
        $CurrentObject = $Choices[$i]
        
        # Basobjekt för tabellen
        $ItemHashTable = [ordered]@{
            "#" = $Index
            "OriginalObject" = $CurrentObject
        }

        # Lägg till de specificerade egenskaperna till hash-tabellen
        if ($DisplayProperties.Count -gt 0 -and $CurrentObject -is [psobject]) {
            foreach ($PropName in $DisplayProperties) {
                # Se till att egenskapen faktiskt finns, annars skrivs ingenting ut
                if ($CurrentObject.PSObject.Properties.Name -contains $PropName) {
                    $ItemHashTable[$PropName] = $CurrentObject.$PropName.ToString()
                    
                    # Lägg till rubriken (endast en gång vid första iterationen)
                    if ($i -eq 0) {
                        $DisplayHeaders += $PropName
                    }
                }
            }
        } 
        # Fallback om ingen $DisplayProperties angavs (eller om inmatningen var strängar)
        elseif ($i -eq 0 -and $DisplayProperties.Count -eq 0) {
            # Om inga kolumner specificerats, faller vi tillbaka till att visa text i en kolumn
            $ItemHashTable["Alternativ"] = $CurrentObject.ToString()
            $DisplayHeaders += "Alternativ"
        } 
        elseif ($DisplayProperties.Count -eq 0) {
            # Används för efterföljande rader i fallback-fallet
            $ItemHashTable["Alternativ"] = $CurrentObject.ToString()
        }

        $MenuList += [PSCustomObject]$ItemHashTable
    }
    
    # Skapa den listan och lägg till (inklusive "Klar")
    $ReadyObject = [ordered]@{ "#"=0 }
    foreach ($Header in $DisplayHeaders -notlike '#') {
        $ReadyObject[$Header] = ""
    }
	# Ska "Klar" visas?
	if ($ShowDone -eq $true){
		# Lägg till alternativet "Klar"
		$ReadyObject[$DisplayHeaders[1]] = "Klar"
		$ReadyObject["OriginalObject"] = "Klar"
		
		$OptionList = ([PSCustomObject]$ReadyObject), $MenuList
	} else {
		# Lägg inte till "Klar"
		$OptionList = $MenuList
	}

    # Räkna ut aktuella bredden på terminalen
    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - 2
    if ($ConsoleWidth -le 0) { $ConsoleWidth = 80 } # Sätt 80 ifall värdet blir fel

    Write-Host "`n$Title" -ForegroundColor Yellow
    Write-Host "------------------------------------"

    # Generera tabellen
    $TableString = $OptionList | Format-Table -Property $DisplayHeaders -AutoSize | Out-String -Width $ConsoleWidth

    # Skriv ut rader hoppa över de första 3 raderna (Tom, Rubrik, Linje) om $ShowTitles är false
    $TableLines = $TableString -split "`n"
    $TableLines[$(if ($ShowTitles -eq $true) {1} else {3})..($TableLines.Count - 4)] | Out-Host
    
    Write-Host "Q. Avsluta"
    Write-Host "------------------------------------"

    # Användarval
    while ($true) {
        $Choice = Read-Host "Ange ditt val ($(if ($ShowDone -eq $true) {0}else{1})-$MaxChoice, eller Q)"
        
        # Q valt
        if ($Choice -eq 'Q') {
            return "Q"
        }
        
        # Klar valt
        if ($Choice -eq '0' -and $ShowDone -eq $true) {
            return "D"
        }
        
        # Ett specifikt val
        if ([int]$Choice -ge 1 -and [int]$Choice -le $MaxChoice) {
            $Index = [int]$Choice
            $SelectedItem = $MenuList | Where-Object { $_.'#' -eq $Index } | Select-Object -First 1
            
            # Returnerar det valda originalobjektet
            return $SelectedItem.OriginalObject
            
        } else {
            Write-Host "Ogiltigt val. Försök igen." -ForegroundColor Red
        }
    }
}

## Funktioner för Konfigurationshantering
# Funktion för att ladda data från config
function Load-ConfigData {
    # Kontrollera om config filen finns
	# Om config filen inte finns starta wizard
    if (-not (Test-Path $ConfigFile)) {
        Write-Notice "Konfigurationsfilen '$ConfigFile' hittades inte. Startar wizard..." -ForegroundColor Yellow
        $Global:ConfigData = Get-DefaultConfig
        Save-ConfigData $Global:ConfigData
        return
    }
    
	# Försök läsa in config filen
    try {
        $Global:ConfigData = Get-Content $ConfigFile | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "`nFel vid inläsning av konfigurationen." -ForegroundColor Red
        Write-Notice "Fel: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Funktion för att spara data till config fil
function Save-ConfigData {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [psobject]$Data
    )
    try {
        $Data | ConvertTo-Json -Depth 5 | Set-Content $ConfigFile -Encoding UTF8 -Force
        Write-Notice -Notice "`nKonfigurationen sparades till '$ConfigFile'." -ForegroundColor Green
    }
    catch {
        Write-Notice -Notice "`nEtt fel uppstod vid sparande av konfigurationen: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Skapa en ny config file ---WIZARD---
function Get-DefaultConfig {
	$Title = "SKAPA KONFIGURATION"
	$Body = "Scripter hittade ingen konfigurationsfil. Följ instuktionerna för att skapa en ny fil"
	
	# Skriv title
	Write-Title $Title $Body
	
    $SelectedAdapters = @()
	$FavoriteConfigs = @()
    
    # Hämta alla nätverkskort på systemet
	$SystemAdapters = Get-SystemAdapters | Select-Object -ExpandProperty Name
	
    if (-not $SystemAdapters) {
        Write-Notice -Notice "Inga nätverkskort hittades på systemet." -ForegroundColor Red
        exit 1 
    }
    else {
        do {
	
			# Skriv title
			Write-Title $Title $Body
	
            # De kort som finns på systemet men ännu inte valts
            $AvailableToChoose = $SystemAdapters | Where-Object {$_ -notin $SelectedAdapters.Name}
            
            if (-not $AvailableToChoose) {
                Write-Notice "Alla nätverkskort på systemet är redan valda." -ForegroundColor Green
                break
            }
            
			# Skapa lista med aktuell IP-Adress
			Write-Host "Läser in IP-adresser..."
			$AdapterList = Format-IPList $AvailableToChoose
	
			# Skriv title
			Write-Title $Title $Body
	
            # Lägg till valet "Klar" i menyn som val 1
			$MenuOptions = @("Klar") + $AdapterMenu
            
            $AdapterChoice = Read-UserChoice $AdapterList -Title "Välj ett nätverkskort att lägga till" -DisplayProperties @("Nätverkskort", "Aktuell IP", "DHCP") -ShowDone $true -ShowTitles $true
            
            if ($AdapterChoice -eq "Q") { 
                # Användaren valde Q, avbryt hela konfigurationen
                Write-Notice "Konfiguration avbruten." -ForegroundColor Red
                exit 1 
            }
			
            if ($AdapterChoice -eq "D") {
                # Användaren valde "KLAR"
                break
            }
			
			# Spara namnet på det valda nätverkskortet
            $AdapterName = $AdapterChoice."Nätverkskort"
            
            # Skapa alias för det valda nätverkskortet
            $AdapterAlias = Read-RequiredInput "Ange ett alias för '$AdapterName'." -DefaultValue $AdapterName
            
            # Skapa det nya objektet och lägg till i listan
            $SelectedAdapters += [pscustomobject]@{
                Name = $AdapterName
                Alias = $AdapterAlias
            }
            
            Write-Notice "Nätverkskortet '$AdapterName' med alias '$AdapterAlias' lades till i listan." -ForegroundColor Green
            
        } while ($true)
    }
    
    # Lägg till DHCP
    $FavoriteConfigs += [pscustomobject]@{
        Name = "Standard DHCP"
        Type = "DHCP"
    }

	do{
	$Continue = $false
    # Ska EXEMPEL-konfigurationen läggas till
    $AddExample = Read-RequiredInput "Vill du lägga till 'EXEMPEL - Statisk' konfigurationen? (J/N)"

		if ($AddExample -eq "J") {
			$FavoriteConfigs += [pscustomobject]@{
				Name = "EXEMPEL - Statisk"
				Type = "Static"
				IPAddress = "192.168.1.100"
				SubnetMask = "255.255.255.0"
				Gateway = "192.168.1.1"
				DNSServer = "8.8.8.8"
			}
			Write-Host "Statisk EXEMPEL-konfiguration lades till." -ForegroundColor Green
		} elseif ($AddExample -eq "N") {
			Write-Host "Statisk EXEMPEL-konfiguration hoppades över." -ForegroundColor Yellow
		}
		else {
			Write-Notice "Ogiltligt val" -ForegroundColor Red
			$Continue = $true
		}
	} while ($Continue)

    Write-Notice "Du kan redigera, radera eller lägga till fler favoriter senare i menyn 'Hantera/Redigera'." -ForegroundColor Green

    # Skapa det kompletta konfigurationsobjektet
    return @{
        NetworkAdapters = $SelectedAdapters
        FavoriteConfigurations = $FavoriteConfigs
    }
}

## Funktioner för Konfigurationsredigering

function Manage-Adapters {
    Write-Host "`n--- HANTERA NÄTVERKSKORT ---" -ForegroundColor Yellow
    $CurrentAdapters = $Global:ConfigData.NetworkAdapters
    
    # 1. Lista tillgängliga kort på systemet
    $SystemAdapters = Get-NetAdapter | Where-Object {$_.Status -ne "Disconnected"} | Select-Object -ExpandProperty Name
    
    if (-not $SystemAdapters) {
        Write-Host "Hittade inga nätverkskort på systemet." -ForegroundColor Red
        return
    }
    
    $AvailableToAdd = $SystemAdapters | Where-Object {$_ -notin $CurrentAdapters}
    
    Write-Host "`nAktuella kort i konfigurationen:" -ForegroundColor Cyan
    $CurrentAdapters | ForEach-Object { Write-Host " * $_" }
    
    $EditOptions = @("Lägg till nätverkskort", "Radera nätverkskort", "Gå tillbaka till Huvudmenyn")
    $EditChoice = Read-UserChoice -Prompt "Välj åtgärd" -Options $EditOptions
    
    if ($EditChoice -eq "Q") { return }
    $EditChoice = [int]$EditChoice
    
    # Lägg till kort
    if ($EditChoice -eq 1) {
        if (-not $AvailableToAdd) {
            Write-Host "Alla tillgängliga kort är redan tillagda." -ForegroundColor Red
            return
        }
        
        $AddChoice = Read-UserChoice -Prompt "Välj kort att lägga till" -Options $AvailableToAdd
        if ($AddChoice -ne "Q") {
            $AdapterToAdd = $AvailableToAdd[([int]$AddChoice - 1)]
            $Global:ConfigData.NetworkAdapters += $AdapterToAdd
            Write-Host "Kortet '$AdapterToAdd' lades till i konfigurationen." -ForegroundColor Green
            Save-ConfigData $Global:ConfigData
        }
    }
    # Radera kort
    elseif ($EditChoice -eq 2) {
        if (-not $CurrentAdapters) {
            Write-Host "Inga kort är konfigurerade att radera." -ForegroundColor Red
            return
        }
        
        $RemoveChoice = Read-UserChoice -Prompt "Välj kort att radera" -Options $CurrentAdapters
        if ($RemoveChoice -ne "Q") {
            $AdapterToRemove = $CurrentAdapters[([int]$RemoveChoice - 1)]
            $Global:ConfigData.NetworkAdapters = $CurrentAdapters | Where-Object {$_ -ne $AdapterToRemove}
            Write-Host "Kortet '$AdapterToRemove' raderades från konfigurationen." -ForegroundColor Green
            Save-ConfigData $Global:ConfigData
        }
    }
}

function Add-Favorite {
    Write-Host "`n--- LÄGG TILL NY FAVORIT ---" -ForegroundColor Yellow
    
    $TypeOptions = @("DHCP (Automatisk IP)", "Statisk IP")
    $TypeChoice = Read-UserChoice -Prompt "Välj konfigurationstyp" -Options $TypeOptions
    if ($TypeChoice -eq "Q") { return }
    
    $NewConfig = @{}
    $NewConfig.Name = Read-RequiredInput "Ange namn för favoriten (t.ex. Kontor Statisk)"
    
    if ([int]$TypeChoice -eq 1) { # DHCP
        $NewConfig.Type = "DHCP"
    }
    else { # Statisk
        $NewConfig.Type = "Static"
        
        # Enkel validering (inte komplett validering, men bättre än inget)
        do {
            $NewConfig.IPAddress = Read-RequiredInput "Ange IP-adress"
            if ($NewConfig.IPAddress -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") { break }
            Write-Host "Ogiltigt format för IP-adress." -ForegroundColor Red
        } while ($true)

        $NewConfig.SubnetMask = Read-RequiredInput "Ange Subnätmask" -DefaultValue "255.255.255.0"
        $NewConfig.Gateway = Read-RequiredInput"Ange Standard Gateway"
        $NewConfig.DNSServer = Read-RequiredInput"Ange DNS Server" -DefaultValue "8.8.8.8"
    }

    # Lägg till i konfigurationen och spara
    $Global:ConfigData.FavoriteConfigurations += [pscustomobject]$NewConfig
    Write-Host "`nFavoriten '$($NewConfig.Name)' lades till." -ForegroundColor Green
    Save-ConfigData $Global:ConfigData
}

function Remove-Favorite {
    Write-Host "`n--- RADERA FAVORIT ---" -ForegroundColor Yellow
    $Favorites = $Global:ConfigData.FavoriteConfigurations
    
    if (-not $Favorites) {
        Write-Host "Inga favoriter finns att radera." -ForegroundColor Red
        return
    }
    
    $FavoriteNames = $Favorites.Name
    $RemoveChoice = Read-UserChoice -Prompt "Välj favorit att radera" -Options $FavoriteNames
    
    if ($RemoveChoice -ne "Q") {
        $IndexToRemove = [int]$RemoveChoice - 1
        $RemovedName = $Favorites[$IndexToRemove].Name
        
        # Ta bort objektet från arrayen
        $FavoritesList = [System.Collections.ArrayList]$Favorites
        $FavoritesList.RemoveAt($IndexToRemove)
        
        # Uppdatera konfigurationen med den nya listan
        $Global:ConfigData.FavoriteConfigurations = $FavoritesList
        
        Write-Host "Favoriten '$RemovedName' raderades." -ForegroundColor Green
        Save-ConfigData $Global:ConfigData
    }
}

function Manage-Configuration {
    do {
        Clear-Host
        Write-Host "======= KONFIGURATIONSHANTERARE =======" -ForegroundColor Magenta
        $ConfigOptions = @("Hantera Nätverkskort (Välj vilka som listas)", "Lägg till ny favoritkonfiguration", "Radera favoritkonfiguration", "Gå tillbaka till Huvudmenyn")
        $ConfigChoice = Read-UserChoice -Prompt "Välj konfigurationsåtgärd" -Options $ConfigOptions
        
        switch ($ConfigChoice) {
            "1" { Manage-Adapters }
            "2" { Add-Favorite }
            "3" { Remove-Favorite }
            "Q" { return }
        }
        
        Read-Host "Tryck [Enter] för att fortsätta..." | Out-Null
        
    } while ($true)
}

## Funktioner för IP-Konfiguration

function Apply-Configuration {
    
    Write-Host "`n--- TILLÄMPA IP-INSTÄLLNINGAR ---" -ForegroundColor Cyan
    
    # 1. Välj nätverkskort
    $ConfiguredAdapters = $Global:ConfigData.NetworkAdapters
    
    # Hitta vilka konfigurerade kort som faktiskt är anslutna/upp
    $AvailableAdapterObjects = $ConfiguredAdapters | Where-Object { 
        (Get-NetAdapter -Name $_.Name -ErrorAction SilentlyContinue).Status -ne "Disconnected" 
    }

    if (-not $AvailableAdapterObjects) {
        Write-Host "Hittade inga aktiva nätverkskort som matchade konfigurationen." -ForegroundColor Red
        Write-Host "Kontrollera att korten är anslutna och att namnen är korrekta." -ForegroundColor Yellow
        return
    }

    $AdapterAliases = $AvailableAdapterObjects.Alias
    $AdapterChoice = Read-UserChoice -Prompt "Välj Nätverkskort att konfigurera:" -Options $AdapterAliases

    if ($AdapterChoice -ceq "Q") { return }

    $SelectedAdapterObject = $AvailableAdapterObjects[([int]$AdapterChoice - 1)]
    
    # **NYCKELN**: Vi använder Alias för visning men sparar det tekniska namnet
    $SelectedAdapterAlias = $SelectedAdapterObject.Alias
    $SelectedAdapterName = $SelectedAdapterObject.Name

    Write-Host "`nDu valde kortet: **$SelectedAdapterAlias** ($SelectedAdapterName)" -ForegroundColor Green

    # 2. Välj konfiguration (ingen ändring här)
    $FavoriteConfigs = $Global:ConfigData.FavoriteConfigurations
    $ConfigNames = $FavoriteConfigs.Name
    $ConfigChoice = Read-UserChoice -Prompt "Välj konfiguration för **$SelectedAdapterAlias**:" -Options $ConfigNames

    if ($ConfigChoice -ceq "Q") { return }

    $SelectedConfig = $FavoriteConfigs[([int]$ConfigChoice - 1)]

    # 3. Tillämpa konfiguration (använd $SelectedAdapterName)
    Write-Host "`nTillämpar: $($SelectedConfig.Name) på $SelectedAdapterName..." -ForegroundColor Yellow

    try {
        if ($SelectedConfig.Type -ceq "DHCP") {
            Set-DHCP -AdapterName $SelectedAdapterName
            Write-Host "`nInställningarna har tillämpats. IP-adress erhålls via DHCP." -ForegroundColor Green
        }
        elseif ($SelectedConfig.Type -ceq "Static") {
            # Anropar den befintliga funktionen med det tekniska namnet
            Set-StaticIP `
                -AdapterName $SelectedAdapterName ` 
                -IPAddress $SelectedConfig.IPAddress `
                -SubnetMask $SelectedConfig.SubnetMask `
                -Gateway $SelectedConfig.Gateway `
                -DNSServer $SelectedConfig.DNSServer
                
            Write-Host "`nInställningarna har tillämpats. Kortet har nu statisk IP." -ForegroundColor Green
        }
        # ... resten av try/catch blocket ...
    }
    catch {
        Write-Host "`nEtt fel inträffade vid tillämpning av inställningarna:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Set-StaticIP {
    param(
        [string]$AdapterName,
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNSServer
    )
    
    Write-Host "`n--- Ställer in statisk IP ---" -ForegroundColor Cyan
    
    # Ta bort eventuella befintliga statiska IP-adresser
    Get-NetIPConfiguration -InterfaceAlias $AdapterName | Where-Object {$_.NetAdapter.Status -eq "Up"} | ForEach-Object {
        Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -ne "Dhcp"} | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Lägg till ny statisk IP-adress
    New-NetIPAddress -InterfaceAlias $AdapterName -IPAddress $IPAddress -PrefixLength ([IPAddress]$SubnetMask).GetAddressBytes() | ForEach-Object {
        Write-Host "Satt IP: $($_.IPAddress) / $($_.PrefixLength)" -ForegroundColor Green
    }

    # Sätt Gateway (krävs bara en gång per kort)
    Set-NetIPInterface -InterfaceAlias $AdapterName -InterfaceMetric 10 
    Set-NetRoute -InterfaceAlias $AdapterName -NextHop $Gateway -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Satt Gateway: $Gateway" -ForegroundColor Green
    
    # Sätt DNS-servrar
    Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $DNSServer
    Write-Host "Satt DNS: $DNSServer" -ForegroundColor Green
}

function Set-DHCP {
    param(
        [string]$AdapterName
    )
    
    Write-Host "`n--- Ställer in DHCP ---" -ForegroundColor Cyan
    
    # Sätt kortet till DHCP
    Set-NetIPInterface -InterfaceAlias $AdapterName -Dhcp Enabled
    
    # Ställ in DNS till att ta emot adresser automatiskt
    Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses
    
    Write-Host "Nätverkskort '$AdapterName' är nu inställt på **DHCP** (Automatisk IP)." -ForegroundColor Green
}

## Huvudkörning
	$Title = "IP-KONFIGURATIONSMENY"

# Kontrollera att skriptet körs som administratör
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Detta skript måste köras som administratör!" -ForegroundColor Red
    $ScriptToRun = $MyInvocation.MyCommand.Path
    Start-Process powershell -Verb RunAs -ArgumentList "-File `"$ScriptToRun`""
    exit 1
}

# Ladda konfigurationen (Starta Wizard om den inte finns)
Load-ConfigData

# Huvudmeny Loop
do {
	# Skriv title
	Write-Title -Title $Title
    
    $MainMenuOptions = @("Tillämpa sparad IP-konfiguration", "Hantera/Redigera Favoriter och Nätverkskort", "Avsluta")
    $MenuChoice = Read-UserChoice -Prompt "Välj åtgärd" -Options $MainMenuOptions
    
    switch ($MenuChoice) {
        "1" { Apply-Configuration }
        "M" { Manage-Configuration }
        "Q" { exit }
    }
    
} while ($true)
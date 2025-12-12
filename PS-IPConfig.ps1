#Requires -RunAsAdministrator
#Requires -Version 5.1

## Variabler
# Säkerställ att vi använder den absoluta sökvägen för robusthet.
$ScriptPath = $PSScriptRoot 
$ConfigFile = Join-Path -Path $ScriptPath -ChildPath "Config.json"
$ConfigData = $null

## Globala Funktioner
# Funktion för att skriva titel och beskrivning för aktuell menyn
function Write-Title {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
		
        [Parameter(Mandatory=$false)]
        [string]$Body
    )
	Clear-Host
    Write-Host "`n--- $($Title.ToUpper()) ---" -ForegroundColor Magenta
    Write-Host "$Body`n" -ForegroundColor Cyan
}

# Funktion för att skriva en notis till användaren
function Write-Notice {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Notice,
		
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor=""
    )
	
	if ($ForegroundColor){
		Write-Host "$Notice" -ForegroundColor $ForegroundColor
	}else{
		Write-Host "$Notice"
	}
	Start-Sleep -Seconds 1.5
}

# Funktion för att skapa en lista över systemets nätverkskort. 
function Get-SystemAdapters {
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string[]]$ExcludeNames
    )
        
	return Get-NetAdapter | Where-Object {$_.Name -notin $ExcludeNames} | Where-Object {$_.Status -ne "Not Present"}

}

# Funktion som tar en lista av nätverkskortssnamn och hämtar ip-information om dem
function Format-IPList {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$AdapterNames
    )
	
	$ResultList = @()
    
    foreach ($Adapter in $AdapterNames) {
        
        # Hämta IP-information för det aktuella kortet
		try {
			$IPConfig = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $Adapter
			
			# Läs ut IP-adressen
			if ($IPConfig.PrefixOrigin) {
				if ($IPConfig.PrefixOrigin -eq "Manual"){
					$DHCPStatus = "Nej"
					$CurrentIP = $IPConfig[0].IPAddress
				} else {
					$DHCPStatus = "Ja"
					$CurrentIP = $IPConfig[0].IPAddress
				}
			} else {
				$DHCPStatus = "-"
				$CurrentIP = "-"
			}
		}
		catch {
			Write-Notice -Notice "`nFel vid läsning av IP-information." -ForegroundColor Red
            $CurrentIP = " - "
		}
        
        # Skapa ett nytt objekt med nätverkskortets namn och den aktuella IP-adressen
        $AdapterObject = [PSCustomObject]@{
            Name = $Adapter
            CurrentIP = $CurrentIP
			DHCP = $DHCPStatus
        }
        
        $ResultList += $AdapterObject
    }    
	Return $ResultList
}

# Funktion för att läsa användar input
function Read-RequiredInput {
    param(
		[Parameter(Mandatory=$true)]
        [string]$Prompt,
		
        [Parameter(Mandatory=$false)]
        [string]$DefaultValue = ""
    )
    do {
        $Input = Read-Host $Prompt $(if ($DefaultValue) {"Standardvärde: '$DefaultValue'"})
        if (-not $Input) { $Input = $DefaultValue }
        if (-not [string]::IsNullOrWhiteSpace($Input)) {
            return $Input.Trim()
        }
        Write-Notice -Notice "Input får inte vara tomt. Försök igen." -ForegroundColor Red
    } while ($true)
}

# Funktion för användarval. Q/q avbryter val
function Read-UserChoice {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [Parameter(Mandatory=$true)]
        [array]$Options
    )
    
    do {
        Write-Host ""
        Write-Host "$Prompt" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "$($i+1). $($Options[$i])"
        }
        Write-Host "Q. Avsluta"
        
        $Choice = Read-RequiredInput -Prompt "Ange ditt val (1-$($Options.Count) eller Q)"
        
		try{
			if ([int]$Choice -ge 1 -and [int]$Choice -le $Options.Count) {
				return $Choice
			}
		}
		catch{
			if ($Choice -eq "Q") {
				return $Choice
			}
		}
        
        Write-Notice -Notice "`nFelaktigt val. Försök igen." -ForegroundColor Red
        
    } while ($true)
}

## Funktioner för Konfigurationshantering
# Funktion för att ladda data från config
function Load-ConfigData {
    # Kontrollera om config filen finns
	# Om config filen inte finns starta wizard
    if (-not (Test-Path $ConfigFile)) {
        Write-Notice -Notice "Konfigurationsfilen '$ConfigFile' hittades inte. Startar wizard..." -ForegroundColor Yellow
        $Global:ConfigData = Get-DefaultConfig
        Save-ConfigData -Data $Global:ConfigData
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
        [Parameter(Mandatory=$true)]
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
	Write-Title -Title $Title -Body $Body
	
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
			Write-Title $Title -Body $Body
	
            # De kort som finns på systemet men ännu inte valts
            $AvailableToChoose = $SystemAdapters | Where-Object {$_ -notin $SelectedAdapters.Name}
            
            if (-not $AvailableToChoose) {
                Write-Notice -Notice "Alla nätverkskort på systemet är redan valda." -ForegroundColor Green
                break
            }
            
			# Skapa lista med aktuell IP-Adress
			Write-Host "Läser in IP-adresser..."
			$AdapterList = Format-IPList -AdapterNames $AvailableToChoose
			$AdapterMenu = $AdapterList | ForEach-Object { 
				"$($_.Name)	(IP: $($_.CurrentIP))	(DHCP: $($_.DHCP))"
			}
	
			# Skriv title
			Write-Title $Title -Body $Body
	
            # Lägg till valet "Klar" i menyn som val 1
			$MenuOptions = @("Klar") + $AdapterMenu
            
            $AdapterChoice = Read-UserChoice -Prompt "Välj ett nätverkskort att lägga till" -Options $MenuOptions
            
            if ($AdapterChoice -eq "Q") { 
                # Användaren valde Q, avbryt hela konfigurationen
                Write-Notice -Notice "Konfiguration avbruten." -ForegroundColor Red
                exit 1 
            }
			
            if ($AdapterChoice -eq 1) {
                # Användaren valde "KLAR"
                break
            }
			
			# Spara namnet på det valda nätverkskortet
            $AdapterName = $AvailableToChoose[$AdapterChoice - 2]
            
            # Skapa alias för det valda nätverkskortet
            $AdapterAlias = Read-RequiredInput -Prompt "Ange ett alias för '$AdapterName'." -DefaultValue $AdapterName
            
            # Skapa det nya objektet och lägg till i listan
            $SelectedAdapters += [pscustomobject]@{
                Name = $AdapterName
                Alias = $AdapterAlias
            }
            
            Write-Notice -Notice "Nätverkskortet '$AdapterName' med alias '$AdapterAlias' lades till i listan." -ForegroundColor Green
            
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
    $AddExample = Read-RequiredInput -Prompt "Vill du lägga till 'EXEMPEL - Statisk' konfigurationen? (J/N)"

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
			Write-Notice -Notice "Ogiltligt val" -ForegroundColor Red
			$Continue = $true
		}
	} while ($Continue)

    Write-Notice -Notice "Du kan redigera, radera eller lägga till fler favoriter senare i menyn 'Hantera/Redigera'." -ForegroundColor Green

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
            Save-ConfigData -Data $Global:ConfigData
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
            Save-ConfigData -Data $Global:ConfigData
        }
    }
}

function Add-Favorite {
    Write-Host "`n--- LÄGG TILL NY FAVORIT ---" -ForegroundColor Yellow
    
    $TypeOptions = @("DHCP (Automatisk IP)", "Statisk IP")
    $TypeChoice = Read-UserChoice -Prompt "Välj konfigurationstyp" -Options $TypeOptions
    if ($TypeChoice -eq "Q") { return }
    
    $NewConfig = @{}
    $NewConfig.Name = Read-RequiredInput -Prompt "Ange namn för favoriten (t.ex. Kontor Statisk)"
    
    if ([int]$TypeChoice -eq 1) { # DHCP
        $NewConfig.Type = "DHCP"
    }
    else { # Statisk
        $NewConfig.Type = "Static"
        
        # Enkel validering (inte komplett validering, men bättre än inget)
        do {
            $NewConfig.IPAddress = Read-RequiredInput -Prompt "Ange IP-adress"
            if ($NewConfig.IPAddress -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") { break }
            Write-Host "Ogiltigt format för IP-adress." -ForegroundColor Red
        } while ($true)

        $NewConfig.SubnetMask = Read-RequiredInput -Prompt "Ange Subnätmask" -DefaultValue "255.255.255.0"
        $NewConfig.Gateway = Read-RequiredInput -Prompt "Ange Standard Gateway"
        $NewConfig.DNSServer = Read-RequiredInput -Prompt "Ange DNS Server" -DefaultValue "8.8.8.8"
    }

    # Lägg till i konfigurationen och spara
    $Global:ConfigData.FavoriteConfigurations += [pscustomobject]$NewConfig
    Write-Host "`nFavoriten '$($NewConfig.Name)' lades till." -ForegroundColor Green
    Save-ConfigData -Data $Global:ConfigData
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
        Save-ConfigData -Data $Global:ConfigData
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
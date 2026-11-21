#Requires -Version 5.1
<#
.SYNOPSIS
    Inventaire initial de l'infrastructure personnelle - Windows.
.DESCRIPTION
    Produit un rapport technique en lecture seule, sans elevation, installation
    ni modification volontaire de la configuration.
    Les identifiants materiels (numeros de serie, UUID, MAC/BSSID) et les secrets
    ne sont pas demandes ni inscrits volontairement dans le rapport.
.NOTES
    Compatible Windows PowerShell 5.1 et PowerShell 7 sous Windows.
    Le rapport contient tout de meme des informations potentiellement sensibles
    (nom du PC, adresses IP locales, DNS, SSID Wi-Fi, ports et services).
#> 

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# -----------------------------------------------------------------------------
# Verification de la plateforme
# -----------------------------------------------------------------------------
if ($env:OS -ne 'Windows_NT') {
    Write-Host 'ERREUR : ce script est concu pour Windows.' -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# Preparation du rapport en memoire
# -----------------------------------------------------------------------------
$script:Report = New-Object 'System.Collections.Generic.List[string]'

function Add-Line {
    param([AllowNull()][object]$Text)
    if ($null -eq $Text) {
        [void]$script:Report.Add('')
    }
    else {
        [void]$script:Report.Add([string]$Text)
    }
}

function Add-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    Add-Line ''
    Add-Line ''
    Add-Line ('=' * 76)
    Add-Line ('  ' + $Title)
    Add-Line ('=' * 76)
}

function Add-Subsection {
    param([Parameter(Mandatory = $true)][string]$Title)
    Add-Line ''
    Add-Line ('--- ' + $Title + ' ---')
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Add-Subsection $Label
    try {
        $rendered = (& $Action 2>&1 | Out-String -Width 220).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($rendered)) {
            Add-Line '[Aucune donnee retournee]'
        }
        else {
            foreach ($line in ($rendered -split '\r?\n')) {
                Add-Line $line
            }
        }
    }
    catch {
        Add-Line ('[ERREUR DE COLLECTE] ' + $_.Exception.Message)
    }
}

# -----------------------------------------------------------------------------
# 0. Identification et contexte
# -----------------------------------------------------------------------------
Add-Section '0 - IDENTIFICATION ET CONTEXTE'
Add-Line ('Date de collecte : ' + (Get-Date).ToString('o'))
Add-Line ('Nom de la machine : ' + $env:COMPUTERNAME)
Add-Line 'Utilisateur courant : non collecte'
Add-Line 'Elevation administrateur : non demandee / non utilisee'
Add-Line ('Version PowerShell : ' + $PSVersionTable.PSVersion.ToString())

Add-Result 'Systeme d''exploitation' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    [pscustomobject]@{
        Systeme = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        Installation = $os.InstallDate
        DernierDemarrage = $os.LastBootUpTime
        Fabricant = $os.Manufacturer
    } | Format-List | Out-String -Width 220
}

Add-Result 'Contexte de session et demarrage' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $boot = $os.LastBootUpTime
    $uptime = if ($boot) { (Get-Date) - $boot } else { $null }
    [pscustomobject]@{
        FuseauHoraire = (Get-TimeZone).Id
        Culture = (Get-Culture).Name
        Demarrage = $boot
        DureeDepuisDemarrage = if ($uptime) { '{0}j {1}h {2}m' -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes } else { 'Indisponible' }
        TypeSysteme = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).SystemType
    } | Format-List | Out-String -Width 220
}

# -----------------------------------------------------------------------------
# 1. Identite materielle (sans numeros de serie ni UUID)
# -----------------------------------------------------------------------------
Add-Section '1 - IDENTITE MATERIELLE'

Add-Result 'Ordinateur et carte mere' {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    [pscustomobject]@{
        FabricantSysteme = $cs.Manufacturer
        ModeleSysteme = $cs.Model
        TypeSysteme = $cs.SystemType
        FabricantCarteMere = $bb.Manufacturer
        ModeleCarteMere = $bb.Product
        VersionCarteMere = $bb.Version
        FabricantBIOS = $bios.Manufacturer
        VersionBIOS = $bios.SMBIOSBIOSVersion
        DateBIOS = $bios.ReleaseDate
    } | Format-List | Out-String -Width 220
}

Add-Result 'Peripheriques principaux presents' {
    if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        'Get-PnpDevice indisponible sur cette installation.'
    }
    else {
        Get-PnpDevice -PresentOnly -ErrorAction Stop |
            Where-Object { $_.Class -in @('Display', 'Net', 'SCSIAdapter', 'HDC', 'USB', 'Media', 'System') } |
            Select-Object Class, FriendlyName, Status |
            Sort-Object Class, FriendlyName |
            Format-Table -AutoSize | Out-String -Width 220
    }
}

Add-Result 'Peripheriques USB presents' {
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        Get-PnpDevice -PresentOnly -Class USB -ErrorAction Stop |
            Select-Object FriendlyName, Status |
            Sort-Object FriendlyName |
            Format-Table -AutoSize | Out-String -Width 220
    }
    else {
        'Get-PnpDevice indisponible.'
    }
}

# -----------------------------------------------------------------------------
# 2. Processeur
# -----------------------------------------------------------------------------
Add-Section '2 - PROCESSEUR'

Add-Result 'Caracteristiques CPU' {
    Get-CimInstance Win32_Processor -ErrorAction Stop |
        Select-Object Name, Manufacturer, AddressWidth, DataWidth,
            NumberOfCores, NumberOfLogicalProcessors,
            CurrentClockSpeed, MaxClockSpeed,
            VirtualizationFirmwareEnabled,
            SecondLevelAddressTranslationExtensions,
            VMMonitorModeExtensions |
        Format-List | Out-String -Width 220
}

Add-Result 'Charge CPU au moment de la collecte' {
    Get-CimInstance Win32_Processor -ErrorAction Stop |
        Measure-Object -Property LoadPercentage -Average |
        Select-Object @{N = 'ChargeCPU_Moyenne_pct'; E = { $_.Average }} |
        Format-List | Out-String -Width 220
}

Add-Line 'Note : les extensions CPU detaillees (AVX, AVX2, AVX-512, AES-NI, etc.) ne sont pas certifiees par cet inventaire WMI initial.'

# -----------------------------------------------------------------------------
# 3. Memoire vive et memoire virtuelle
# -----------------------------------------------------------------------------
Add-Section '3 - MEMOIRE RAM ET MEMOIRE VIRTUELLE'

Add-Result 'Memoire reconnue par Windows' {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    [pscustomobject]@{
        RAMVisible_Go = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        RAMLibre_Go = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        RAMUtilisee_Go = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        MemoireVirtuelleTotale_Ko = $os.TotalVirtualMemorySize
        MemoireVirtuelleLibre_Ko = $os.FreeVirtualMemory
    } | Format-List | Out-String -Width 220
}

Add-Result 'Barrettes memoire (sans numero de serie)' {
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
        Select-Object DeviceLocator,
            @{N = 'Capacite_Go'; E = { [math]::Round($_.Capacity / 1GB, 2) } },
            Speed, ConfiguredClockSpeed, Manufacturer, PartNumber,
            FormFactor, MemoryType, SMBIOSMemoryType, DataWidth, TotalWidth |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Fichiers de pagination' {
    Get-CimInstance Win32_PageFileUsage -ErrorAction Stop |
        Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage |
        Format-Table -AutoSize | Out-String -Width 220
}

# -----------------------------------------------------------------------------
# 4. GPU et accelerateurs
# -----------------------------------------------------------------------------
Add-Section '4 - GPU ET ACCELERATEURS'

Add-Result 'Cartes graphiques reconnues par Windows' {
    Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Select-Object Name, VideoProcessor, DriverVersion, DriverDate,
            @{N = 'MemoireVideoRapportee_Go'; E = {
                if ($null -ne $_.AdapterRAM -and [double]$_.AdapterRAM -gt 0) {
                    [math]::Round(([double]$_.AdapterRAM / 1GB), 2)
                }
                else { 'Non rapportee' }
            }}, CurrentHorizontalResolution, CurrentVerticalResolution |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'NVIDIA - informations fournies par le pilote (si disponible)' {
    $nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvsmi) {
        # Ne pas utiliser -L ni la sortie complete : elles peuvent exposer des UUID.
        & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1
    }
    else {
        'nvidia-smi absent ou pilote NVIDIA non disponible.'
    }
}

Add-Result 'Pilotes graphiques signes' {
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -eq 'DISPLAY' } |
        Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Line 'Note : la valeur VRAM issue de Win32_VideoController peut etre absente ou inexacte. Pour AMD/Intel, elle n''est pas consideree comme une mesure garantie.'

# -----------------------------------------------------------------------------
# 5. Stockage
# -----------------------------------------------------------------------------
Add-Section '5 - STOCKAGE'

Add-Result 'Disques physiques (sans numero de serie ni UniqueId)' {
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        Get-PhysicalDisk -ErrorAction Stop |
            Select-Object DeviceId, FriendlyName, MediaType, BusType,
                @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } },
                HealthStatus, OperationalStatus, SpindleSpeed |
            Format-Table -AutoSize | Out-String -Width 220
    }
    else {
        Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
            Select-Object Model, InterfaceType, MediaType,
                @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } }, Status |
            Format-Table -AutoSize | Out-String -Width 220
    }
}

Add-Result 'Disques Windows et caracteristiques' {
    Get-Disk -ErrorAction Stop |
        Select-Object Number, FriendlyName, BusType, PartitionStyle,
            @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } },
            OperationalStatus, HealthStatus, IsBoot, IsSystem, IsReadOnly |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Partitions (correspondance disque / partition)' {
    Get-Partition -ErrorAction Stop |
        Select-Object DiskNumber, PartitionNumber, DriveLetter, Type,
            @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } }, IsBoot, IsSystem |
        Sort-Object DiskNumber, PartitionNumber |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Volumes et occupation' {
    Get-Volume -ErrorAction Stop |
        Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType,
            @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } },
            @{N = 'Libre_Go'; E = { if ($_.Size -gt 0) { [math]::Round($_.SizeRemaining / 1GB, 2) } }},
            @{N = 'Utilise_pct'; E = {
                if ($_.Size -gt 0) { [math]::Round((1 - ($_.SizeRemaining / $_.Size)) * 100, 1) }
            }}, HealthStatus |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Storage Spaces / pools (si disponibles)' {
    if (Get-Command Get-StoragePool -ErrorAction SilentlyContinue) {
        Get-StoragePool -ErrorAction Stop |
            Select-Object FriendlyName, OperationalStatus, HealthStatus,
                @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } } |
            Format-Table -AutoSize | Out-String -Width 220
    }
    else { 'Commandes Storage Spaces indisponibles.' }
}

Add-Result 'BitLocker (aucune cle de recuperation collectee)' {
    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        return 'Get-BitLockerVolume indisponible (edition ou module Windows).'
    }
    try {
        Get-BitLockerVolume -ErrorAction Stop |
            Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionPercentage |
            Format-Table -AutoSize | Out-String -Width 220
    }
    catch {
        '[BitLocker : acces refuse — normal sans elevation administrateur]'
    }
}

Add-Line 'Note : HealthStatus est une information exposee par le fournisseur Windows / constructeur ; elle ne remplace pas un diagnostic SMART approfondi.'

# -----------------------------------------------------------------------------
# 6. Reseau
# -----------------------------------------------------------------------------
Add-Section '6 - RESEAU'
Add-Line 'Attention : cette section contient des adresses IP locales, DNS, SSID et ports en ecoute.'

Add-Result 'Interfaces reseau (adresses MAC exclues)' {
    Get-NetAdapter -ErrorAction Stop |
        Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState, InterfaceIndex |
        Sort-Object InterfaceIndex |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Adresses IP' {
    Get-NetIPAddress -ErrorAction Stop |
        Where-Object { $_.AddressState -ne 'Invalid' } |
        Select-Object InterfaceAlias, AddressFamily, IPAddress, PrefixLength, PrefixOrigin, AddressState |
        Sort-Object InterfaceAlias, AddressFamily |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Routes IPv4' {
    Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
        Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric |
        Sort-Object InterfaceAlias, RouteMetric |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Routes IPv6' {
    Get-NetRoute -AddressFamily IPv6 -ErrorAction Stop |
        Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric |
        Sort-Object InterfaceAlias, RouteMetric |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Serveurs DNS' {
    Get-DnsClientServerAddress -ErrorAction Stop |
        Where-Object { $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceAlias, AddressFamily,
            @{N = 'ServeursDNS'; E = { $_.ServerAddresses -join ', ' }} |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Connexion Wi-Fi (BSSID et adresse physique exclus)' {
    $netsh = Get-Command netsh.exe -ErrorAction SilentlyContinue
    if ($netsh) {
        $wifi = & netsh.exe wlan show interfaces 2>&1
        $wifi | Where-Object {
            $_ -notmatch '(?i)BSSID' -and
            $_ -notmatch ':\s*[0-9A-Fa-f]{2}([:\-][0-9A-Fa-f]{2}){5}\s*$'
        }
    }
    else { 'netsh indisponible.' }
}

Add-Result 'Sockets TCP en ecoute (adresse, port et nom du processus)' {
    $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop
    $rows = foreach ($connection in $connections) {
        $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { 'Inconnu / acces limite' }
        [pscustomobject]@{
            AdresseLocale = $connection.LocalAddress
            PortLocal = $connection.LocalPort
            Processus = $processName
        }
    }
    $rows | Sort-Object PortLocal | Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Sockets UDP (adresse, port et nom du processus)' {
    $endpoints = Get-NetUDPEndpoint -ErrorAction Stop
    $rows = foreach ($endpoint in $endpoints) {
        $process = Get-Process -Id $endpoint.OwningProcess -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { 'Inconnu / acces limite' }
        [pscustomobject]@{
            AdresseLocale = $endpoint.LocalAddress
            PortLocal = $endpoint.LocalPort
            Processus = $processName
        }
    }
    $rows | Sort-Object PortLocal | Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Profils du pare-feu Windows' {
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        Get-NetFirewallProfile -ErrorAction Stop |
            Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            Format-Table -AutoSize | Out-String -Width 220
    }
    else { 'Get-NetFirewallProfile indisponible.' }
}

# -----------------------------------------------------------------------------
# 7. Systeme et services
# -----------------------------------------------------------------------------
Add-Section '7 - SYSTEME ET SERVICES'

Add-Result 'Services en cours (Win32_Service)' {
    Get-CimInstance Win32_Service -ErrorAction Stop |
        Where-Object { $_.State -eq 'Running' } |
        Select-Object Name, DisplayName, State, StartMode |
        Sort-Object Name |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Services automatiques arretes (Win32_Service)' {
    Get-CimInstance Win32_Service -ErrorAction Stop |
        Where-Object { $_.State -eq 'Stopped' -and $_.StartMode -eq 'Auto' } |
        Select-Object Name, DisplayName, State, StartMode |
        Sort-Object Name |
        Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Docker (conteneurs actifs uniquement)' {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        & docker --version 2>&1
        & docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1
    }
    else { 'Docker absent du PATH.' }
}

Add-Result 'Podman (conteneurs actifs uniquement)' {
    $podman = Get-Command podman -ErrorAction SilentlyContinue
    if ($podman) {
        & podman --version 2>&1
        & podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1
    }
    else { 'Podman absent du PATH.' }
}

Add-Result 'Machines virtuelles Hyper-V (si disponible)' {
    if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
        Get-VM -ErrorAction Stop |
            Select-Object Name, State, Generation, Version,
                @{N = 'MemoireAffectee_Go'; E = { [math]::Round($_.MemoryAssigned / 1GB, 2) }} |
            Format-Table -AutoSize | Out-String -Width 220
    }
    else { 'Module Hyper-V / Get-VM indisponible.' }
}

Add-Result 'Distributions WSL' {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { return 'WSL absent du PATH.' }
    $oldEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    try { & wsl.exe --list --verbose 2>&1 }
    finally { [Console]::OutputEncoding = $oldEnc }
}

# -----------------------------------------------------------------------------
# 8. Outils et technologies disponibles
# -----------------------------------------------------------------------------
Add-Section '8 - OUTILS ET TECHNOLOGIES DISPONIBLES'

Add-Result 'Presence des outils (chemins executables non collectes)' {
    $tools = @(
        'winget', 'choco', 'scoop', 'nix',
        'docker', 'podman', 'wsl', 'vagrant', 'VBoxManage', 'vmrun',
        'tailscale', 'wg', 'git', 'python', 'python3', 'py', 'node', 'npm',
        'gcc', 'cl', 'make', 'nmake', 'ssh', 'rsync', 'borg', 'restic'
    )
    $rows = foreach ($tool in $tools) {
        $available = [bool](Get-Command -Name $tool -ErrorAction SilentlyContinue)
        [pscustomobject]@{ Outil = $tool; Disponible = $available }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 220
}

Add-Result 'Versions de quelques outils' {
    $versionCommands = @(
        @{ Name = 'git'; Args = @('--version') },
        @{ Name = 'python'; Args = @('--version') },
        @{ Name = 'python3'; Args = @('--version') },
        @{ Name = 'node'; Args = @('--version') },
        @{ Name = 'docker'; Args = @('--version') },
        @{ Name = 'podman'; Args = @('--version') },
        @{ Name = 'winget'; Args = @('--version') }
    )
    foreach ($entry in $versionCommands) {
        $cmd = Get-Command -Name $entry.Name -ErrorAction SilentlyContinue
        if ($cmd) {
            '--- ' + $entry.Name + ' ---'
            $commandArgs = $entry.Args
            & $entry.Name @commandArgs 2>&1 | Select-Object -First 2
        }
    }
}

# -----------------------------------------------------------------------------
# 9. Indicateurs generaux
# -----------------------------------------------------------------------------
Add-Section '9 - INDICATEURS GENERAUX'

Add-Result 'Charge, processeurs logiques et uptime' {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $load = ($cpu | Measure-Object -Property LoadPercentage -Average).Average
    $uptime = (Get-Date) - $os.LastBootUpTime
    [pscustomobject]@{
        ChargeCPU_Moyenne_pct = $load
        ProcesseursLogiques = $env:NUMBER_OF_PROCESSORS
        DernierDemarrage = $os.LastBootUpTime
        Uptime = '{0}j {1}h {2}m' -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
    } | Format-List | Out-String -Width 220
}

Add-Result 'Occupation du volume systeme' {
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    Get-Volume -DriveLetter $driveLetter -ErrorAction Stop |
        Select-Object DriveLetter, FileSystem, FileSystemLabel,
            @{N = 'Taille_Go'; E = { [math]::Round($_.Size / 1GB, 2) } },
            @{N = 'Libre_Go'; E = { [math]::Round($_.SizeRemaining / 1GB, 2) } } |
        Format-List | Out-String -Width 220
}

# -----------------------------------------------------------------------------
# 10. Limites connues de cette collecte
# -----------------------------------------------------------------------------
Add-Section '10 - LIMITES ET INTERPRETATION'
Add-Line '- Inventaire en lecture seule : aucune installation ni modification volontaire de configuration.'
Add-Line "- Aucune elevation administrateur n'est demandee."
Add-Line '- Numeros de serie, UUID, identifiants de volumes, cles BitLocker, mots de passe et adresses MAC/BSSID ne sont pas collectes volontairement.'
Add-Line '- Le rapport contient neanmoins le nom du PC, des adresses IP locales, DNS, SSID Wi-Fi, ports, services et noms de conteneurs : traiter le fichier comme sensible.'
Add-Line '- Certaines informations peuvent etre absentes sans elevation ou si le module / pilote correspondant est indisponible.'
Add-Line '- Les caracteristiques CPU avancees, les mesures completes de VRAM AMD/Intel, les temperatures et le diagnostic SMART detaille seront approfondis selon le materiel detecte.'
Add-Line '- HealthStatus et les informations WMI sont des indications exposees par Windows / le fournisseur materiel, pas une certification independante.'

Add-Section 'FIN DE L INVENTAIRE'
Add-Line ('Fin de collecte : ' + (Get-Date).ToString('o'))
Add-Line 'Fin du rapport.'

# -----------------------------------------------------------------------------
# Creation du fichier sans ecrasement, puis ACL privee avant ecriture du rapport
# -----------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path ('inventaire_initial_windows_{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
}

try {
    $fullPath = [System.IO.Path]::GetFullPath($OutputPath)
    $parentPath = Split-Path -Parent $fullPath

    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "Le dossier parent n'existe pas : $parentPath"
    }

    # CreateNew garantit qu'un fichier existant ne sera jamais ecrase.
    $stream = [System.IO.File]::Open(
        $fullPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    $stream.Dispose()

    try {
        $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = Get-Acl -LiteralPath $fullPath -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            [void]$acl.RemoveAccessRule($rule)
        }
        $privateRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $currentSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($privateRule)
        Set-Acl -LiteralPath $fullPath -AclObject $acl -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        throw ('Impossible de garantir les permissions privees du rapport : ' + $_.Exception.Message)
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($fullPath, [string[]]$script:Report.ToArray(), $encoding)

    Write-Host ''
    Write-Host ('Rapport cree : ' + $fullPath) -ForegroundColor Green
    Write-Host 'Permissions : acces complet accorde au compte Windows courant uniquement.' -ForegroundColor Green
    Write-Host 'Aucune modification systeme volontaire effectuee.'
}
catch {
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    exit 2
}

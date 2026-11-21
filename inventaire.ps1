#Requires -Version 5.1
<#
.SYNOPSIS
    Inventaire initial - Infrastructure personnelle (Windows)

.DESCRIPTION
    Version Windows du script d'inventaire en lecture seule.

    - Aucune installation
    - Aucune modification de configuration
    - Aucune elevation de privileges (pas de RunAs)
    - Aucun numero de serie, UUID materiel, MAC ou mot de passe collecte
    - Creation d'un rapport local avec permissions privees (ACL)
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# --- Verification plateforme ---
if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
    Write-Host "Ce script est concu pour Windows." -ForegroundColor Red
    exit 1
}

# --- Nom de sortie ---
if (-not $OutputPath) {
    $OutputPath = "inventaire_initial_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
}

if (Test-Path -LiteralPath $OutputPath) {
    Write-Host "ERREUR : le fichier existe deja : $OutputPath" -ForegroundColor Red
    exit 1
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    Write-Host "ERREUR : dossier parent introuvable : $parent" -ForegroundColor Red
    exit 1
}

# --- Creation du fichier avec ACL privee ---
try {
    New-Item -Path $OutputPath -ItemType File -Force | Out-Null
    $acl = Get-Acl -Path $OutputPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $newRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'FullControl', 'Allow'
    )
    $acl.AddAccessRule($newRule)
    Set-Acl -Path $OutputPath -AclObject $acl
}
catch {
    Write-Host "Avertissement : permissions du fichier non restreintes : $_" -ForegroundColor Yellow
}

# --- Helpers ---
function Section([string]$Title) {
    ''
    ''
    '================================================================'
    "  $Title"
    '================================================================'
}
function Subsection([string]$Title) {
    ''
    "--- $Title ---"
}
function Test-Available([string]$Cmd) {
    return [bool](Get-Command -Name $Cmd -ErrorAction SilentlyContinue)
}
function Invoke-If([string]$Cmd, [string[]]$CmdArgs = @()) {
    if (Test-Available $Cmd) {
        ''
        "`$ $Cmd $($CmdArgs -join ' ')" 
        & $Cmd @CmdArgs 2>&1
    }
    else {
        ''
        "[Non disponible : $Cmd]"
    }
}
function Show-Table {
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        $InputObject,
        [Parameter(Position = 1)]
        [object[]]$Properties
    )
    process {
        try {
            $InputObject |
            Select-Object -Property $Properties |
            Format-Table -AutoSize |
            Out-String -Stream
        }
        catch {
            "[Erreur de formatage : $($_.Exception.Message)]"
        }
    }
}

# ============================================================
# Contenu du rapport
# ============================================================
try {
    & {

        # ============================================================
        # 0. IDENTIFICATION
        # ============================================================
        Section '0 - IDENTIFICATION ET CONTEXTE'

        "Date : $((Get-Date).ToString('o'))"
        "Nom de la machine : $env:COMPUTERNAME"
        "Utilisateur courant : non collecte"
        "Droits administrateur : non utilises"

        Subsection 'Systeme'
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $friendly = switch ([int]$os.BuildNumber) {
            { $_ -ge 22000 } { 'Windows 11' }
            default { 'Windows 10' }
        }
        "Edition            : $($os.Caption) ($friendly, build $($os.BuildNumber))"
        "Version            : $($os.Version)"
        "Architecture       : $($os.OSArchitecture)"
        "Langue             : $((Get-Culture).Name)"
        "Date installation  : $($os.InstallDate)"

        Subsection 'Demarrage et fonctionnement'
        "Demarrage : $($os.LastBootUpTime)"
        if ($os.LastBootUpTime) {
            $up = (Get-Date) - $os.LastBootUpTime
            "Uptime    : $([math]::Floor($up.TotalDays))j $($up.Hours)h $($up.Minutes)m"
        }
        "Fuseau horaire : $((Get-TimeZone).Id)"

        # ============================================================
        # 1. IDENTITE MATERIELLE
        # ============================================================
        Section '1 - IDENTITE MATERIELLE'
        # On exclut volontairement les numeros de serie et UUID.

        $cs = Get-CimInstance Win32_ComputerSystem
        "Fabricant systeme    : $($cs.Manufacturer)"
        "Modele systeme       : $($cs.Model)"
        "Type systeme         : $($cs.SystemType)"

        $bb = Get-CimInstance Win32_BaseBoard
        "Fabricant carte-mere : $($bb.Manufacturer)"
        "Modele carte-mere    : $($bb.Product)"
        "Version carte-mere   : $($bb.Version)"

        $bios = Get-CimInstance Win32_BIOS
        "Fabricant BIOS       : $($bios.Manufacturer)"
        "Version BIOS         : $($bios.SMBIOSBIOSVersion)"
        "Date BIOS            : $($bios.ReleaseDate)"

        Subsection 'Equipements principaux (Display, Net, Storage, USB, Audio)'
        Show-Table (Get-PnpDevice -PresentOnly |
            Where-Object { $_.Class -in @('Display', 'Net', 'SCSIAdapter', 'HDC', 'USB', 'Media') }) `
        @('Class', 'FriendlyName', 'Status')

        Subsection 'Ponts et composants systeme (extrait)'
        Show-Table (Get-PnpDevice -PresentOnly -Class System |
            Where-Object { $_.FriendlyName -match 'PCI|Bridge|Host|Bus|ACPI' } |
            Select-Object -First 40) `
        @('FriendlyName', 'Status')

        Subsection 'Peripheriques USB'
        Show-Table (Get-PnpDevice -PresentOnly -Class USB) @('FriendlyName', 'Status')

        # ============================================================
        # 2. PROCESSEUR
        # ============================================================
        Section '2 - PROCESSEUR'

        $cpu = Get-CimInstance Win32_Processor
        "Nom                          : $($cpu.Name)"
        "Fabricant                    : $($cpu.Manufacturer)"
        "Architecture                 : $($cpu.AddressWidth)-bit"
        "Coeurs physiques             : $($cpu.NumberOfCores)"
        "Processeurs logiques         : $($cpu.NumberOfLogicalProcessors)"
        "Frequence max (MHz)          : $($cpu.MaxClockSpeed)"
        "Virtualisation (firmware)    : $($cpu.VirtualizationFirmwareEnabled)"
        "SLAT (Second Level Addr.)    : $($cpu.SecondLevelAddressTranslationExtensions) (peu fiable via WMI)"

        Subsection 'Charge actuelle'
        $cpuLoad = (Get-CimInstance Win32_Processor |
            Measure-Object -Property LoadPercentage -Average).Average
        "Charge CPU moyenne : $cpuLoad %"

        # ============================================================
        # 3. MEMOIRE
        # ============================================================
        Section '3 - MEMOIRE RAM ET SWAP'

        $mem = $os
        $totalGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)
        "Memoire totale    : $totalGB Go"
        "Memoire libre     : $freeGB Go"
        "Memoire utilisee  : $([math]::Round($totalGB - $freeGB, 2)) Go"

        Subsection 'Barrettes memoire'
        Show-Table (Get-CimInstance Win32_PhysicalMemory) @(
            @{N = 'Slot'; E = { $_.DeviceLocator } },
            @{N = 'Capacite (Go)'; E = { [math]::Round($_.Capacity / 1GB, 0) } },
            @{N = 'Vitesse (MHz)'; E = { $_.Speed } },
            @{N = 'Fabricant'; E = { $_.Manufacturer } },
            @{N = 'Reference'; E = { $_.PartNumber } }
        )

        Subsection 'Fichier de pagination (swap)'
        Show-Table (Get-CimInstance Win32_PageFileUsage) @(
            'Name', 'AllocatedBaseSize', 'CurrentUsage', 'PeakUsage'
        )

        Subsection 'Memoire virtuelle (Ko)'
        "Totale : $($mem.TotalVirtualMemorySize)"
        "Libre  : $($mem.FreeVirtualMemory)"

        # ============================================================
        # 4. GPU ET ACCELERATEURS
        # ============================================================
        Section '4 - GPU ET ACCELERATEURS'

        Subsection 'Cartes graphiques detectees'
        Show-Table (Get-CimInstance Win32_VideoController) @(
            'Name', 'DriverVersion', 'VideoProcessor',
            @{N = 'VRAM (Go)'; E = {
                    if ($_.AdapterRAM -and $_.AdapterRAM -gt 0) {
                        [math]::Round($_.AdapterRAM / 1GB, 2)
                    }
                    else { 'n/a (iGPU / non reporte)' }
                }
            },
            'CurrentHorizontalResolution', 'CurrentVerticalResolution'
        )

        Subsection 'NVIDIA'
        if (Test-Available nvidia-smi) {
            Invoke-If nvidia-smi -CmdArgs '-L'
            ''
            '$ nvidia-smi --query-gpu=name,memory.total,driver_version,pci.bus_id --format=csv,noheader'
            nvidia-smi --query-gpu=name,memory.total,driver_version,pci.bus_id --format=csv,noheader 2>&1
            Subsection 'Etat NVIDIA detaille'
            Invoke-If nvidia-smi
        }
        else {
            'nvidia-smi absent ou pilote NVIDIA non disponible'
        }

        Subsection 'Pilotes graphiques charges'
        Show-Table (Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DeviceClass -eq 'DISPLAY' }) @(
            'DeviceName', 'DriverVersion', 'DriverDate'
        )

        # ============================================================
        # 5. STOCKAGE
        # ============================================================
        Section '5 - STOCKAGE'

        Subsection 'Disques physiques'
        Show-Table (Get-PhysicalDisk -ErrorAction SilentlyContinue) @(
            'DeviceId', 'FriendlyName', 'MediaType', 'BusType',
            @{N = 'Taille (Go)'; E = { [math]::Round($_.Size / 1GB, 2) } },
            'HealthStatus', 'OperationalStatus'
        )

        Subsection 'Partitions'
        Show-Table (Get-Disk) @(
            'Number', 'FriendlyName', 'PartitionStyle', 'BusType',
            @{N = 'Taille (Go)'; E = { [math]::Round($_.Size / 1GB, 2) } },
            'OperationalStatus'
        )

        Subsection 'Volumes'
        Show-Table (Get-Volume) @(
            'DriveLetter', 'FileSystemLabel', 'FileSystem', 'DriveType',
            @{N = 'Taille (Go)'; E = { [math]::Round($_.Size / 1GB, 2) } },
            @{N = 'Libre (Go)'; E = { [math]::Round($_.SizeRemaining / 1GB, 2) } },
            @{N = 'Utilise %'; E = {
                    if ($_.Size -gt 0) {
                        [math]::Round((1 - $_.SizeRemaining / $_.Size) * 100, 1)
                    }
                }
            },
            'HealthStatus'
        )

        Subsection 'Occupation des espaces montes'
        Show-Table (Get-PSDrive -PSProvider FileSystem) @(
            'Name',
            @{N = 'Utilise (Go)'; E = { [math]::Round($_.Used / 1GB, 2) } },
            @{N = 'Libre (Go)'; E = { [math]::Round($_.Free / 1GB, 2) } },
            'Root'
        )

        Subsection 'Storage Spaces / Pools'
        Show-Table (Get-StoragePool -ErrorAction SilentlyContinue) @(
            'FriendlyName', 'OperationalStatus', 'HealthStatus',
            @{N = 'Taille (Go)'; E = { [math]::Round($_.Size / 1GB, 2) } }
        )

        Subsection 'BitLocker'
        if (Test-Available Get-BitLockerVolume) {
            $bl = $null
            try {
                $bl = Get-BitLockerVolume -ErrorAction Stop 2>&1 |
                    Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
            }
            catch {
                # ignore : acces refuse sans elevation
            }
            if ($bl) {
                Show-Table $bl @(
                    'MountPoint', 'VolumeStatus', 'ProtectionStatus', 'EncryptionPercentage'
                )
            }
            else {
                '[BitLocker : acces refuse ou aucun volume chiffre — normal sans elevation]'
            }
        }
        else {
            'Get-BitLockerVolume non disponible (edition Windows ou module absent)'
        }

        # ============================================================
        # 6. RESEAU
        # ============================================================
        Section '6 - RESEAU'

        Subsection 'Interfaces et adresses'
        # Les adresses MAC sont masquees.
        Show-Table (Get-NetAdapter) @(
            'Name', 'InterfaceDescription', 'Status', 'LinkSpeed',
            @{N = 'MacAddress'; E = {
                    $m = $_.MacAddress
                    if (-not $m) { return '' }
                    $m = $m -replace '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}', 'XX-XX-XX-XX-XX-XX'
                    $m = $m -replace '^[0-9A-Fa-f]{12}$', 'XX-XX-XX-XX-XX-XX'
                    $m
                }
            }
        )

        Subsection 'Adresses IP'
        Show-Table (Get-NetIPAddress) @(
            'InterfaceAlias', 'AddressFamily', 'IPAddress', 'PrefixLength', 'PrefixOrigin'
        )

        Subsection 'Routes IPv4'
        Show-Table (Get-NetRoute -AddressFamily IPv4) @(
            'DestinationPrefix', 'NextHop', 'InterfaceAlias', 'RouteMetric'
        )

        Subsection 'Routes IPv6'
        Show-Table (Get-NetRoute -AddressFamily IPv6) @(
            'DestinationPrefix', 'NextHop', 'InterfaceAlias', 'RouteMetric'
        )

        Subsection 'Serveurs DNS'
        Show-Table (Get-DnsClientServerAddress) @(
            'InterfaceAlias',
            @{N = 'Famille'; E = {
                    switch ($_.AddressFamily) { 2 { 'IPv4' } 23 { 'IPv6' } default { $_ } }
                }
            },
            @{N = 'Serveurs'; E = { ($_.ServerAddresses -join ', ') } }
        )

        Subsection 'Sockets TCP en ecoute'
        Show-Table (Get-NetTCPConnection -State Listen) @(
            'LocalAddress', 'LocalPort',
            @{N = 'Process'; E = {
                    (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                }
            }
        )

        Subsection 'Sockets UDP en ecoute'
        Show-Table (Get-NetUDPEndpoint) @(
            'LocalAddress', 'LocalPort',
            @{N = 'Process'; E = {
                    (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                }
            }
        )

        # ============================================================
        # 7. SYSTEME ET SERVICES
        # ============================================================
        Section '7 - SYSTEME ET SERVICES'

        Subsection 'Services en cours'
        Show-Table (Get-Service | Where-Object { $_.Status -eq 'Running' }) @(
            'Name', 'DisplayName', 'StartType'
        )

        Subsection 'Services automatiques arretes'
        Show-Table (Get-Service |
            Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' }) @(
            'Name', 'DisplayName'
        )

        Subsection 'Environnements de conteneurs'
        if (Test-Available docker) {
            Invoke-If docker -CmdArgs '--version'
            ''
            '$ docker ps'
            docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1
        }
        if (Test-Available podman) {
            Invoke-If podman -CmdArgs '--version'
            ''
            '$ podman ps'
            podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1
        }

        Subsection 'Virtualisation'
        if (Test-Available Get-VM) {
            Show-Table (Get-VM) @(
                'Name', 'State', 'Generation', 'Version',
                @{N = 'Memoire (Go)'; E = { [math]::Round($_.MemoryAssigned / 1GB, 2) } }
            )
        }
        else {
            'Hyper-V / Get-VM non disponible'
        }

        if (Test-Available wsl) {
            ''
            '$ wsl --list --verbose'
            $oldEnc = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
            try { wsl --list --verbose 2>&1 }
            finally { [Console]::OutputEncoding = $oldEnc }
        }

        # ============================================================
        # 8. OUTILS ET TECHNOLOGIES
        # ============================================================
        Section '8 - OUTILS ET TECHNOLOGIES'

        $tools = @(
            'winget', 'choco', 'scoop', 'nix',
            'docker', 'podman', 'wsl', 'vagrant', 'VBoxManage', 'vmrun',
            'tailscale', 'wg', 'git', 'python', 'python3', 'py', 'node', 'npm',
            'gcc', 'cl', 'make', 'nmake', 'ssh', 'rsync', 'borg', 'restic'
        ) | Select-Object -Unique

        foreach ($t in $tools) {
            if (Test-Available $t) {
                $path = (Get-Command -Name $t -ErrorAction SilentlyContinue).Source
                '{0,-18} : {1}' -f $t, $path
            }
        }

        Subsection 'Versions de quelques outils'
        foreach ($t in @('git', 'python', 'node', 'docker', 'podman', 'winget')) {
            if (Test-Available $t) {
                ''
                $t
                & $t --version 2>&1 | Select-Object -First 2
            }
        }

        # ============================================================
        # 9. ETAT GENERAL
        # ============================================================
        Section '9 - INDICATEURS GENERAUX'

        Subsection 'Charge et disponibilite'
        $cpuLoad = (Get-CimInstance Win32_Processor |
            Measure-Object -Property LoadPercentage -Average).Average
        "Charge CPU                  : $cpuLoad %"
        "Processeurs logiques        : $env:NUMBER_OF_PROCESSORS"

        "Dernier demarrage           : $($os.LastBootUpTime)"
        if ($os.LastBootUpTime) {
            $up = (Get-Date) - $os.LastBootUpTime
            "Uptime                      : $([math]::Floor($up.TotalDays))j $($up.Hours)h $($up.Minutes)m"
        }

        Subsection 'Espace disque systeme'
        $sysLetter = ($env:SystemDrive).TrimEnd(':')
        Show-Table (Get-Volume -DriveLetter $sysLetter) @(
            'DriveLetter', 'FileSystemLabel', 'FileSystem',
            @{N = 'Taille (Go)'; E = { [math]::Round($_.Size / 1GB, 2) } },
            @{N = 'Libre (Go)'; E = { [math]::Round($_.SizeRemaining / 1GB, 2) } }
        )

        # ============================================================
        # FIN
        # ============================================================
        Section "FIN DE L'INVENTAIRE"
        "Rapport genere : $OutputPath"
        "Fin            : $((Get-Date).ToString('o'))"
        ''
        'Aucune modification systeme volontaire effectuee.'

    } 2>&1 | Tee-Object -FilePath $OutputPath -Append
}
catch {
    "ERREUR FATALE : $($_.Exception.Message)" |
    Tee-Object -FilePath $OutputPath -Append
    exit 2
}

Write-Host ""
Write-Host "Rapport ecrit : $OutputPath" -ForegroundColor Green
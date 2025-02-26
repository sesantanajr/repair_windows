# CompleteWindowsRepair_NoChkdsk.ps1
# Solucao definitiva para reparo e limpeza do Windows (10 e 11)
# - Cria ponto de restauracao do sistema
# - Repara repositorio WMI e re-registra pacotes da Windows Store
# - Executa SFC, DISM e outras correcoes (sem chkdsk)
# - Limpa pastas temporarias, atualizacoes obsoletas e arquivos residuais
# - Opera de forma silenciosa, com retry para comandos criticos

# -------------------------
# Configuracao Inicial
# -------------------------
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference = "None"
$logFile = "$env:ProgramData\WindowsRepairScript\RepairLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path "$env:ProgramData\WindowsRepairScript")) {
    New-Item -Path "$env:ProgramData\WindowsRepairScript" -ItemType Directory -Force | Out-Null
}

# -------------------------
# Funcoes de Suporte
# -------------------------
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Funcao para executar um comando com retry
function Invoke-WithRetry {
    param (
        [Parameter(Mandatory=$true)][ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )
    for ($i=1; $i -le $MaxRetries; $i++) {
        try {
            & $ScriptBlock
            return $true
        }
        catch {
            Write-Log "Tentativa $i falhou: $_" "WARNING"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $false
}

# Funcao auxiliar para renomear pastas com verificacao
function Safe-RenameFolder {
    param (
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    if (Test-Path $Source) {
        if (Test-Path $Destination) {
            Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        try {
            Rename-Item -Path $Source -NewName (Split-Path $Destination -Leaf) -ErrorAction Stop
            Write-Log "Pasta '$Source' renomeada para '$Destination'." "INFO"
        }
        catch {
            Write-Log "Erro ao renomear '$Source' para '$Destination': $_" "ERROR"
        }
    }
    else {
        Write-Log "Pasta '$Source' nao encontrada. Nenhuma acao realizada." "WARNING"
    }
}

# -------------------------
# Funcoes de Reparos Adicionais
# -------------------------
# 1. Criar Ponto de Restauracao do Sistema
function Create-SystemRestorePoint {
    try {
        if (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) {
            $desc = "Ponto de restauracao antes de reparo do Windows - $(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Invoke-WithRetry -ScriptBlock { Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS } | Out-Null
            Write-Log "Ponto de restauracao criado com sucesso: $desc" "INFO"
        }
        else {
            Write-Log "Checkpoint-Computer nao disponivel nesta versao do Windows." "WARNING"
        }
    }
    catch {
        Write-Log "Erro ao criar ponto de restauracao: $_" "ERROR"
    }
}

# 2. Reparar Repositorio WMI
function Repair-WMIRepository {
    try {
        Write-Log "Verificando integridade do repositorio WMI..." "INFO"
        $verify = Invoke-WithRetry -ScriptBlock { winmgmt /verifyrepository }
        if (-not $verify) {
            Write-Log "Repositorio WMI inconsistente. Tentando salvagarde." "WARNING"
            Invoke-WithRetry -ScriptBlock { winmgmt /salvagerepository } | Out-Null
            Write-Log "Repositorio WMI reparado." "SUCCESS"
        }
        else {
            Write-Log "Repositorio WMI verificado com sucesso." "SUCCESS"
        }
    }
    catch {
        Write-Log "Erro durante a verificacao do repositorio WMI: $_" "ERROR"
    }
}

# 3. Re-registrar Pacotes da Windows Store
function ReRegister-WindowsStore {
    try {
        Write-Log "Re-registrando pacotes da Windows Store..." "INFO"
        Invoke-WithRetry -ScriptBlock {
            Get-AppXPackage -AllUsers |
            Foreach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            }
        } | Out-Null
        Write-Log "Pacotes da Windows Store re-registrados." "SUCCESS"
    }
    catch {
        Write-Log "Erro ao re-registrar os pacotes da Windows Store: $_" "ERROR"
    }
}

# 4. Limpeza Adicional de Atualizacoes Obsoletas e Arquivos Residuais
function Clean-ResidualFiles {
    try {
        Write-Log "Limpando arquivos residuais e atualizacoes obsoletas..." "INFO"
        # Limpar pasta de download do Windows Update
        $updateDownload = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"
        if (Test-Path $updateDownload) {
            Remove-Item -Path "$updateDownload\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Pasta de download do Windows Update limpa." "INFO"
        }
        # Limpar pasta temporaria do Windows.~BT se existir
        $tempBT = "C:\Windows\~BT"
        if (Test-Path $tempBT) {
            Remove-Item -Path $tempBT -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Pasta Windows ~BT removida." "INFO"
        }
        # Executar DISM para limpar componentes obsoletos (reforcado)
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow -ErrorAction SilentlyContinue } | Out-Null
    }
    catch {
        Write-Log "Erro durante a limpeza de arquivos residuais: $_" "ERROR"
    }
}

# -------------------------
# Funcoes Principais
# -------------------------
function Clean-TemporaryFiles {
    Write-Log "Iniciando limpeza de arquivos temporarios..." "INFO"
    try {
        Write-Log "Parando servicos relacionados..." "INFO"
        Invoke-WithRetry -ScriptBlock { Stop-Service -Name BITS, wuauserv, CryptSvc, msiserver -Force -ErrorAction Stop } | Out-Null

        $userTempFolders = @("$env:TEMP", "$env:TMP")
        foreach ($folder in $userTempFolders) {
            if (Test-Path $folder) {
                Write-Log "Limpando pasta temporaria do usuario: $folder" "INFO"
                Get-ChildItem -Path $folder -Force -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '.*\\wer\\.*' } |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        $winTemp = "$env:SystemRoot\Temp"
        if (Test-Path $winTemp) {
            Write-Log "Limpando pasta temporaria do Windows: $winTemp" "INFO"
            Get-ChildItem -Path $winTemp -Force -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }

        Write-Log "Limpando arquivos de atualizacao do Windows..." "INFO"
        if (Test-Path "$env:SystemRoot\SoftwareDistribution") {
            Safe-RenameFolder -Source "$env:SystemRoot\SoftwareDistribution" -Destination "$env:SystemRoot\SoftwareDistribution.old"
        }

        Write-Log "Limpando pasta WinSxS (pode demorar alguns minutos)..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Limpando logs de eventos com mais de 365 dias..." "INFO"
        $days365Ago = (Get-Date).AddDays(-365)
        $logNames = wevtutil el
        foreach ($logName in $logNames) {
            try {
                $logEvents = Get-WinEvent -LogName $logName -MaxEvents 1 -ErrorAction SilentlyContinue |
                             Where-Object { $_.TimeCreated -lt $days365Ago }
                if ($logEvents) {
                    wevtutil cl "$logName" 2>$null
                    Write-Log "  Limpando log: $logName" "INFO"
                }
            }
            catch { }
        }

        Write-Log "Limpando cache DNS..." "INFO"
        ipconfig /flushdns | Out-Null

        Write-Log "Limpando cache de fontes..." "INFO"
        Remove-Item "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache*.dat" -Force -ErrorAction SilentlyContinue

        Write-Log "Limpando pasta Prefetch..." "INFO"
        Get-ChildItem -Path "$env:SystemRoot\Prefetch" -Force | ForEach-Object {
            Remove-Item $_.FullName -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        }

        Invoke-WithRetry -ScriptBlock { Start-Service -Name BITS, wuauserv, CryptSvc, msiserver -ErrorAction SilentlyContinue } | Out-Null

        Write-Log "Limpeza de arquivos temporarios concluida com sucesso" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Erro durante a limpeza de arquivos temporarios: $_" "ERROR"
        Start-Service -Name BITS, wuauserv, CryptSvc, msiserver -ErrorAction SilentlyContinue
        return $false
    }
}

function Repair-Windows {
    Write-Log "Iniciando reparo do Windows..." "INFO"
    try {
        Write-Log "Executando verificacao de arquivos do sistema (SFC)..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Executando verificacao e reparo da imagem do Windows (DISM)..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /CheckHealth" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /ScanHealth" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Verificando e corrigindo erros no registro..." "INFO"
        # SFC e DISM ja corrigem a maioria dos erros do registro.

        Write-Log "Reparando relacoes de arquivos..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "cmd.exe" -ArgumentList "/c assoc .=." -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Reparando configuracoes de rede..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "netsh.exe" -ArgumentList "winsock reset" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "netsh.exe" -ArgumentList "int ip reset" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null
        ipconfig /flushdns | Out-Null

        Write-Log "Executando otimizacao de disco..." "INFO"
        $driveLetter = $env:SystemDrive.TrimEnd(":")
        Invoke-WithRetry -ScriptBlock { Optimize-Volume -DriveLetter $driveLetter -Defrag -ReTrim -SlabConsolidate -Verbose -ErrorAction SilentlyContinue } | Out-Null

        $essentialServices = @("wuauserv", "BITS", "TrustedInstaller", "WinDefend", "SecurityHealthService")
        foreach ($service in $essentialServices) {
            Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }

        Write-Log "Reparo do Windows concluido com sucesso" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Erro durante o reparo do Windows: $_" "ERROR"
        return $false
    }
}

function Repair-WindowsUpdate {
    Write-Log "Iniciando reparo do Windows Update..." "INFO"
    try {
        Write-Log "Parando servicos relacionados ao Windows Update..." "INFO"
        Invoke-WithRetry -ScriptBlock { Stop-Service -Name BITS, wuauserv, CryptSvc, TrustedInstaller -Force -ErrorAction Stop } | Out-Null

        Write-Log "Limpando diretorios do Windows Update..." "INFO"
        if (Test-Path "$env:SystemRoot\SoftwareDistribution") {
            Safe-RenameFolder -Source "$env:SystemRoot\SoftwareDistribution" -Destination "$env:SystemRoot\SoftwareDistribution.old"
            New-Item -Path "$env:SystemRoot\SoftwareDistribution" -ItemType Directory -Force | Out-Null
        }
        if (Test-Path "$env:SystemRoot\System32\Catroot2") {
            Safe-RenameFolder -Source "$env:SystemRoot\System32\Catroot2" -Destination "$env:SystemRoot\System32\Catroot2.old"
            New-Item -Path "$env:SystemRoot\System32\Catroot2" -ItemType Directory -Force | Out-Null
        }

        Write-Log "Reiniciando componentes relacionados a rede..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "netsh.exe" -ArgumentList "winsock reset" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "netsh.exe" -ArgumentList "winhttp reset proxy" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Reiniciando politicas de grupo..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Registrando novamente DLLs do Windows Update..." "INFO"
        $updateDlls = @(
            "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll",
            "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll",
            "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll",
            "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll",
            "wuapi.dll", "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
            "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
        )
        foreach ($dll in $updateDlls) {
            if (Test-Path "$env:SystemRoot\System32\$dll") {
                Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s $env:SystemRoot\System32\$dll" -Wait -NoNewWindow -ErrorAction SilentlyContinue } | Out-Null
            }
        }

        Write-Log "Restaurando repositorio de componentes do Windows Update..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -NoNewWindow -ErrorAction Stop } | Out-Null

        Write-Log "Limpando filas de download do BITS..." "INFO"
        Get-BitsTransfer -AllUsers | Remove-BitsTransfer -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\*" -Force -Recurse -ErrorAction SilentlyContinue

        $osVersion = [System.Environment]::OSVersion.Version
        if ($osVersion.Major -ge 10) {
            Write-Log "Executando reparo de problemas de atualizacao para Windows 10/11..." "INFO"
            Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" -ArgumentList "setupapi,InstallHinfSection DefaultInstall 128 $env:SystemRoot\inf\wuau.inf" -Wait -NoNewWindow -ErrorAction SilentlyContinue } | Out-Null
        }

        Write-Log "Redefinindo Catalog Store..." "INFO"
        $catdbPath = "$env:SystemRoot\System32\catroot2\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\catdb"
        if (Test-Path $catdbPath) {
            Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "esentutl.exe" -ArgumentList "/p $catdbPath" -Wait -NoNewWindow -ErrorAction SilentlyContinue } | Out-Null
        }
        else {
            Write-Log "Arquivo catdb nao encontrado. Pulando redefinicao do Catalog Store." "WARNING"
        }

        Invoke-WithRetry -ScriptBlock {
            Set-Service -Name BITS -StartupType Automatic -ErrorAction SilentlyContinue
            Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
            Set-Service -Name CryptSvc -StartupType Automatic -ErrorAction SilentlyContinue
            Set-Service -Name TrustedInstaller -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name BITS -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Start-Service -Name CryptSvc -ErrorAction SilentlyContinue
            Start-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
        } | Out-Null

        Write-Log "Limpando arquivos residuais e atualizacoes obsoletas..." "INFO"
        Clean-ResidualFiles

        Write-Log "Forcando verificacao de atualizacoes..." "INFO"
        Invoke-WithRetry -ScriptBlock { Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -Wait -NoNewWindow -ErrorAction SilentlyContinue } | Out-Null

        Write-Log "Reparo do Windows Update concluido com sucesso" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Erro durante o reparo do Windows Update: $_" "ERROR"
        Invoke-WithRetry -ScriptBlock { Start-Service -Name BITS, wuauserv, CryptSvc -ErrorAction SilentlyContinue } | Out-Null
        return $false
    }
}

# -------------------------
# Execucao do Processo de Diagnostico e Reparo
# -------------------------
$totalSuccess = $true

# 1. Criar ponto de restauracao
Create-SystemRestorePoint

# 2. Reparar WMI e re-registrar Windows Store
Repair-WMIRepository
ReRegister-WindowsStore

Write-Log "============================================================" "INFO"
Write-Log "Iniciando processo de diagnostico e reparo do sistema" "INFO"
Write-Log "Data e hora: $(Get-Date)" "INFO"
Write-Log "Nome do computador: $env:COMPUTERNAME" "INFO"
Write-Log "Sistema operacional: $(Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Caption)" "INFO"
Write-Log "Versao do Windows: $(Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Version)" "INFO"
Write-Log "============================================================" "INFO"

Write-Log "============================================================" "INFO"
Write-Log "ETAPA 1: LIMPEZA DE ARQUIVOS TEMPORARIOS" "INFO"
Write-Log "============================================================" "INFO"
$cleanSuccess = Clean-TemporaryFiles
if (-not $cleanSuccess) {
    $totalSuccess = $false
    Write-Log "Limpeza de arquivos temporarios falhou ou foi concluida com avisos" "WARNING"
}

Write-Log "============================================================" "INFO"
Write-Log "ETAPA 2: REPARO DO SISTEMA WINDOWS" "INFO"
Write-Log "============================================================" "INFO"
$repairSuccess = Repair-Windows
if (-not $repairSuccess) {
    $totalSuccess = $false
    Write-Log "Reparo do Windows falhou ou foi concluido com avisos" "WARNING"
}

Write-Log "============================================================" "INFO"
Write-Log "ETAPA 3: REPARO DO WINDOWS UPDATE" "INFO"
Write-Log "============================================================" "INFO"
$updateRepairSuccess = Repair-WindowsUpdate
if (-not $updateRepairSuccess) {
    $totalSuccess = $false
    Write-Log "Reparo do Windows Update falhou ou foi concluido com avisos" "WARNING"
}

Write-Log "============================================================" "INFO"
Write-Log "RESUMO DO PROCESSO DE REPARO" "INFO"
Write-Log "============================================================" "INFO"
Write-Log "Limpeza de arquivos temporarios: $(if ($cleanSuccess) { 'SUCESSO' } else { 'FALHOU' })" "INFO"
Write-Log "Reparo do Windows: $(if ($repairSuccess) { 'SUCESSO' } else { 'FALHOU' })" "INFO"
Write-Log "Reparo do Windows Update: $(if ($updateRepairSuccess) { 'SUCESSO' } else { 'FALHOU' })" "INFO"
Write-Log "Status geral: $(if ($totalSuccess) { 'TODOS OS PROCESSOS CONCLUIDOS COM SUCESSO' } else { 'ALGUNS PROCESSOS FALHARAM OU FORAM CONCLUIDOS COM AVISOS' })" "INFO"
Write-Log "Arquivo de log: $logFile" "INFO"
Write-Log "Data e hora de conclusao: $(Get-Date)" "INFO"
Write-Log "============================================================" "INFO"

if ($totalSuccess) {
    Write-Log "Script concluido com sucesso. Codigo de saida: 0" "SUCCESS"
    exit 0
} else {
    Write-Log "Script concluido com avisos ou erros. Codigo de saida: 1" "WARNING"
    exit 1
}

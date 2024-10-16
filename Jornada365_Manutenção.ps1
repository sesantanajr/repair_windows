<#
.SYNOPSIS
    Jornada 365 | Manutenção Windows - Versão Aprimorada para Execução Direta e via Intune MDM
    Sua jornada começa aqui.
    https://jornada365.cloud

.DESCRIPTION
    Este script é projetado para ser executado diretamente ou distribuído via Microsoft Intune MDM.
    Ele cria uma cópia de si mesmo em uma localização segura, agenda uma tarefa de manutenção mensal
    e realiza a manutenção do sistema Windows, incluindo verificação do sistema, limpeza de arquivos
    temporários e reinicialização do serviço Windows Update.

.NOTES
    Versão: 3.2
    Autor: Jornada 365
    Data de Última Modificação: 15/10/2024
#>

# Configurações iniciais
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"
$ScriptName = "Jornada365_Manutencao.ps1"
$SecureFolder = "$env:ProgramData\Jornada365"
$LogPath = Join-Path $SecureFolder "Manutencao_Windows.log"
$ScriptPath = Join-Path $SecureFolder $ScriptName
$TaskName = "Jornada365_Manutencao"

# Função para registrar logs
function Write-Log {
    param ([string]$Message)
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$Timestamp - $Message"
    Write-Verbose $LogMessage
    try {
        Add-Content -Path $LogPath -Value $LogMessage -Encoding UTF8 -Force
    } catch {
        Write-Error "Erro ao gravar no log: $($_.Exception.Message)"
    }
}

# Função para criar diretório se ele não existir
function Ensure-Directory {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        try {
            New-Item -ItemType Directory -Force -Path $Path | Out-Null
            Write-Log "Diretório criado: $Path"
        } catch {
            Write-Log "Erro ao criar diretório ${Path}: $($_.Exception.Message)"
            throw
        }
    }
}

# Função para obter o caminho do script atual
function Get-ScriptPath {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    elseif ($psISE) {
        return Split-Path -Parent $psISE.CurrentFile.FullPath
    }
    elseif ($MyInvocation.MyCommand.Path) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    else {
        Write-Log "Não foi possível determinar o caminho do script."
        throw "Caminho do script não encontrado"
    }
}

# Função para copiar o script para a localização segura
function Copy-ScriptToSecureLocation {
    try {
        $SourceDir = Get-ScriptPath
        $SourceFile = Get-ChildItem -Path $SourceDir -Filter "Jornada365_*.ps1" | Select-Object -First 1
        
        if (-not $SourceFile) {
            throw "Arquivo do script não encontrado no diretório: $SourceDir"
        }

        $SourcePath = $SourceFile.FullName
        Write-Log "Arquivo de origem encontrado: $SourcePath"

        Ensure-Directory -Path $SecureFolder
        Copy-Item -Path $SourcePath -Destination $ScriptPath -Force
        Write-Log "Script copiado para localização segura: $ScriptPath"
    } catch {
        Write-Log "Erro ao copiar o script: $($_.Exception.Message)"
        throw
    }
}

# Função para agendar a tarefa de manutenção
function Schedule-MaintenanceTask {
    try {
        $RandomDay = Get-Random -Minimum 20 -Maximum 29
        $ActionArgument = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -ExecuteMaintenance"
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $ActionArgument
        
        Write-Log "Comando de execução da tarefa: PowerShell.exe $ActionArgument"

        $Trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek (Get-Date -Day $RandomDay).DayOfWeek -At "12:00PM"
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -WakeToRun
        $Principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Manutenção mensal do sistema pelo Jornada 365" -Force

        Write-Log "Tarefa de manutenção mensal agendada com sucesso para o dia $RandomDay às 12:00."
    } catch {
        Write-Log "Erro ao agendar a tarefa de manutenção mensal: $($_.Exception.Message)"
        throw
    }
}

# Função para executar a manutenção
function Perform-Maintenance {
    Write-Log "Iniciando processo de manutenção"

    # Verificação de integridade do sistema (SFC e DISM)
    Write-Log "Iniciando: SFC scan"
    Start-Process "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait
    Write-Log "SFC scan concluído"

    Write-Log "Iniciando: DISM"
    Start-Process "DISM.exe" -ArgumentList "/Online", "/Cleanup-Image", "/RestoreHealth" -NoNewWindow -Wait
    Write-Log "DISM concluído"

    # Lista de pastas para limpeza
    $TempFolders = @(
        "$env:TEMP",
        "$env:SystemRoot\Temp",
        "$env:SystemRoot\Prefetch",
        "$env:SystemRoot\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER"
    )

    # Limpeza de arquivos temporários
    foreach ($folder in $TempFolders) {
        Write-Log "Limpando pasta: $folder"
        Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | 
        Where-Object { -not $_.PSIsContainer } | 
        ForEach-Object {
            try {
                $_ | Remove-Item -Force -ErrorAction Stop
                Write-Log "Arquivo removido: $($_.FullName)"
            } catch {
                Write-Log "Não foi possível remover: $($_.FullName). Erro: $($_.Exception.Message)"
            }
        }
    }

    # Verificar e reiniciar o serviço Windows Update
    $ServiceName = "wuauserv"
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($Service) {
        if ($Service.Status -ne 'Running') {
            Write-Log "Reiniciando o serviço Windows Update"
            Restart-Service -Name $ServiceName -Force
        } else {
            Write-Log "Serviço Windows Update já está em execução"
        }
    } else {
        Write-Log "Serviço Windows Update não encontrado"
    }

    Write-Log "Processo de manutenção concluído"
}

# Função principal
function Main {
    Write-Log "Iniciando script de manutenção"
    
    if ($args -contains "-ExecuteMaintenance") {
        Write-Log "Executando manutenção"
        Perform-Maintenance
    } else {
        Write-Log "Preparando ambiente para distribuição via Intune ou execução direta"
        Copy-ScriptToSecureLocation
        Schedule-MaintenanceTask
        Write-Log "Configuração inicial concluída. A primeira manutenção será executada conforme agendado."
    }
    
    Write-Log "Script de manutenção concluído"
}

# Executar a função principal
Main $args

# Fim do script

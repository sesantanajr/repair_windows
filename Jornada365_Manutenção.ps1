<#
.SYNOPSIS
    Jornada 365 | Manutenção Windows
    Sua jornada começa aqui.
    https://jornada365.cloud

.DESCRIPTION
    Este script realiza a manutenção do sistema Windows, executando comandos de verificação do sistema,
    limpeza de arquivos temporários e reinicialização do serviço Windows Update.
    É projetado para funcionar tanto localmente quanto em dispositivos gerenciados pelo Microsoft Intune.

.SUPPORTED OS
    Windows 10, Windows 11
#>

# Configurações iniciais
$ErrorActionPreference = "Stop"   # Parar o script em caso de erro
$VerbosePreference = "SilentlyContinue"   # Não mostrar mensagens detalhadas para o usuário
$LogDir = "$env:ProgramData\Jornada365"   # Diretório de logs
$LogPath = Join-Path $LogDir "Manutencao_Windows.log"   # Caminho completo do arquivo de log

# Função para registrar logs
function Write-Log {
    param (
        [string]$Message
    )
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$Timestamp - $Message"
    Add-Content -Path $LogPath -Value $LogMessage -Encoding UTF8
}

# Função para criar diretório se ele não existir
function Ensure-Directory {
    param (
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        try {
            New-Item -ItemType Directory -Force -Path $Path | Out-Null
            Write-Log "Diretório criado: $Path"
        }
        catch {
            Write-Log "Erro ao criar diretório ${Path}: $($_.Exception.Message)"
            throw
        }
    }
}

# Função para executar comandos com tratamento de erros
function Execute-Command {
    param (
        [string]$Command,
        [string]$Arguments,
        [string]$Description
    )
    try {
        Write-Log "Iniciando: $Description"
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "Comando não encontrado: $Command"
        }
        $process = Start-Process -FilePath $Command -ArgumentList $Arguments -Wait -WindowStyle Hidden -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Comando falhou com código de saída: $($process.ExitCode)"
        }
        Write-Log "Concluído com sucesso: $Description"
    }
    catch {
        Write-Log "Erro em $Description. Mensagem: $($_.Exception.Message)"
        throw
    }
}

# Função para limpar arquivos temporários
function Clear-TempFolder {
    try {
        Write-Log "Iniciando limpeza da pasta %temp%"
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
            }
            catch {
                Write-Log "Erro ao remover item $_.FullName: $($_.Exception.Message)"
            }
        }
        Write-Log "Limpeza da pasta %temp% concluída"
    }
    catch {
        Write-Log "Erro ao limpar pasta %temp%: $($_.Exception.Message)"
    }
}

# Função para reiniciar o serviço Windows Update
function Restart-WindowsUpdateService {
    try {
        $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Log "Reiniciando o serviço Windows Update"
            Restart-Service -Name wuauserv -Force
            Write-Log "Serviço Windows Update reiniciado com sucesso"
        } elseif ($service) {
            Write-Log "Serviço Windows Update não está em execução, não é necessário reiniciar."
        } else {
            Write-Log "Serviço Windows Update não encontrado."
        }
    }
    catch {
        Write-Log "Erro ao reiniciar o serviço Windows Update: $($_.Exception.Message)"
    }
}

# Função para criar componentes da tarefa agendada
function Create-ScheduledTaskComponents {
    param (
        [string]$Command,
        [string]$Arguments,
        [int]$DayOfMonth
    )
    $action = New-ScheduledTaskAction -Execute $Command -Argument $Arguments
    $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth $DayOfMonth -At "03:00AM"
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden

    return [PSCustomObject]@{
        Action    = $action
        Trigger   = $trigger
        Principal = $principal
        Settings  = $settings
    }
}

# Função para criar ou atualizar tarefa agendada
function Set-ScheduledTask {
    param (
        [string]$TaskName,
        [string]$Description,
        [PSCustomObject]$TaskComponents
    )
    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Tarefa agendada existente removida: $TaskName"
        }
        Register-ScheduledTask -TaskName $TaskName -Description $Description -Action $TaskComponents.Action -Trigger $TaskComponents.Trigger -Principal $TaskComponents.Principal -Settings $TaskComponents.Settings
        Write-Log "Nova tarefa agendada criada: $TaskName"
    }
    catch {
        Write-Log "Erro ao configurar tarefa agendada ${TaskName}: $($_.Exception.Message)"
        throw
    }
}

# Função principal para realizar a manutenção
function Perform-Maintenance {
    try {
        # Garantir que o diretório de logs exista
        Ensure-Directory $LogDir

        # Executar comandos de verificação do sistema
        Execute-Command -Command "sfc.exe" -Arguments "/scannow" -Description "SFC scan"
        Execute-Command -Command "DISM.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth" -Description "DISM"
        
        # Limpeza e reinicialização
        Clear-TempFolder
        Restart-WindowsUpdateService

        # Definir dias aleatórios para agendamento
        $randomDay1 = Get-Random -Minimum 1 -Maximum 29
        $randomDay2 = Get-Random -Minimum 1 -Maximum 29
        while ($randomDay2 -eq $randomDay1) { $randomDay2 = Get-Random -Minimum 1 -Maximum 29 }

        # Criar componentes de tarefas agendadas
        $task1Components = Create-ScheduledTaskComponents -Command "powershell.exe" -Arguments "-ExecutionPolicy Bypass -Command `'Start-Process 'sfc.exe' -ArgumentList '/scannow' -Wait -WindowStyle Hidden`'" -DayOfMonth $randomDay1
        Set-ScheduledTask -TaskName "Jornada 365 - SFC Scan" -Description "Executa SFC scan mensalmente" -TaskComponents $task1Components

        $task2Components = Create-ScheduledTaskComponents -Command "powershell.exe" -Arguments "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -WindowStyle Hidden" -DayOfMonth $randomDay2
        Set-ScheduledTask -TaskName "Jornada 365 - Manutenção Windows" -Description "Executa manutenção do Windows mensalmente" -TaskComponents $task2Components

        Write-Log "Manutenção concluída com sucesso. SFC agendado para dia $randomDay1, manutenção completa para dia $randomDay2 de cada mês."
    }
    catch {
        Write-Log "Erro durante a execução da manutenção: $($_.Exception.Message)"
        exit 1
    }
}

# Execução principal
Perform-Maintenance
exit 0
<#
.SYNOPSIS
    Jornada 365 | Manutenção Windows - Versão Refatorada e Otimizada
    Sua jornada começa aqui.
    https://jornada365.cloud

.DESCRIPTION
    Este script realiza a manutenção do sistema Windows, agendando a tarefa de manutenção e depois executando comandos de verificação do sistema,
    limpeza de arquivos temporários e reinicialização do serviço Windows Update.
    É projetado para funcionar tanto localmente quanto em dispositivos gerenciados pelo Microsoft Intune.

.SUPPORTED OS
    Windows 10, Windows 11
#>

# Configurações iniciais
$ErrorActionPreference = "Stop"   # Parar o script em caso de erro crítico
$VerbosePreference = "SilentlyContinue"   # Não mostrar mensagens detalhadas ao usuário
$LogDir = "$env:ProgramData\Jornada365"   # Diretório de logs
$LogPath = Join-Path $LogDir "Manutencao_Windows.log"   # Caminho completo do arquivo de log

# Função para registrar logs
function Write-Log {
    param (
        [string]$Message
    )
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$Timestamp - $Message"
    try {
        Add-Content -Path $LogPath -Value $LogMessage -Encoding UTF8
    } catch {
        Write-Error "Erro ao gravar no log: $($_.Exception.Message)"
    }
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
        } catch {
            Write-Log "Erro ao criar diretório ${Path}: $($_.Exception.Message)"
            throw
        }
    }
}

# Função para executar comandos com tratamento de erro silencioso
function Execute-Command {
    param (
        [scriptblock]$Command,
        [string]$Description
    )
    try {
        & $Command
        Write-Log "$Description concluído com sucesso."
    } catch {
        Write-Log "Erro durante ${Description}: $($_.Exception.Message)"
    }
}

# Criar o diretório de logs se ele não existir
Ensure-Directory -Path $LogDir

# Agendamento de tarefa de manutenção mensal em dias aleatórios entre 20 e 30, às 12:00
try {
    $RandomDay = Get-Random -Minimum 20 -Maximum 31
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSScriptRoot\Jornada365_Manutencao.ps1`""
    $Trigger = New-ScheduledTaskTrigger -Once -At "12:00PM"
    $Trigger.StartBoundary = (Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day $RandomDay -Hour 12 -Minute 0).ToString("yyyy-MM-ddTHH:mm:ss")
    $Trigger.ExecutionTimeLimit = "PT1H" # Limite de tempo de execução
    $Trigger.Delay = "PT5M" # Atraso de 5 minutos para evitar congestionamento
    $Trigger.Enabled = $true
    $Trigger.RandomDelay = "PT1H" # Atraso aleatório adicional
    $Trigger.StartWhenAvailable = $true # Executar ao ligar o dispositivo, se estiver desligado
    $Principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -TaskName "Jornada365_Manutencao" -Description "Manutenção mensal do sistema pelo Jornada 365" -Force
    Write-Log "Tarefa de manutenção mensal agendada com sucesso para o dia $RandomDay às 12:00."
} catch {
    Write-Log "Erro ao agendar a tarefa de manutenção mensal: $($_.Exception.Message)"
}

# Iniciar verificação de integridade do sistema (SFC e DISM)
Write-Log "Iniciando: SFC scan"
Execute-Command -Command { sfc /scannow } -Description "SFC scan"

Write-Log "Iniciando: DISM"
Execute-Command -Command { DISM /Online /Cleanup-Image /RestoreHealth } -Description "DISM"

# Limpeza de arquivos temporários
Write-Log "Iniciando limpeza da pasta %temp%"
$TempFiles = Get-ChildItem -Path "$env:TEMP" -Recurse -File -ErrorAction SilentlyContinue
foreach ($file in $TempFiles) {
    try {
        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
        Write-Log "Arquivo removido: $($file.FullName)"
    } catch {
        # Apenas registrar que o arquivo está em uso e seguir
        Write-Log "Arquivo em uso e não pôde ser removido: $($file.FullName)"
    }
}
Write-Log "Limpeza da pasta %temp% concluída"

# Verificar e reiniciar o serviço Windows Update, se necessário
$ServiceName = "wuauserv"
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($Service -and $Service.Status -ne 'Running') {
    Write-Log "Serviço Windows Update não está em execução, iniciando o serviço."
    Execute-Command -Command { Start-Service -Name $ServiceName } -Description "Iniciar serviço Windows Update"
} else {
    Write-Log "Serviço Windows Update já está em execução."
}

Write-Log "Execução da manutenção concluída."

# Fim do script

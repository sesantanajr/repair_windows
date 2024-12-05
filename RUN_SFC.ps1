# Nome da tarefa
$taskName = "RunSFC"

# Verifica se o ScheduledTask "RunSFC" já existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    # Se a tarefa já existir, removê-la antes de recriar
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Cria a ação: Executa o cmd.exe com argumento para rodar o SFC silenciosamente
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c sfc /scannow > NUL 2>&1"

# Cria o gatilho:
# - Um gatilho para rodar imediatamente
$triggerImmediate = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

# - Um gatilho semanal: Toda sexta-feira às 08:00 da manhã
$triggerWeekly = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 8:00AM

# Define as configurações da tarefa:
# - Repetir a tarefa caso perca o agendamento
# - A tarefa será repetida a cada 2 horas, por até 1 dia, caso não possa ser executada no horário agendado
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                          -DontStopIfGoingOnBatteries `
                                          -StartWhenAvailable `
                                          -RestartInterval (New-TimeSpan -Hours 2) `
                                          -RestartCount 12 # Tentará reexecutar por até 24 horas

# Cria um principal com privilégios elevados (SYSTEM + Highest)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

# Registra a tarefa agendada com os gatilhos, ação, configurações e principal definidos
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggerImmediate, $triggerWeekly -Settings $settings -Principal $principal

Write-Host "Tarefa '$taskName' criada com sucesso e programada para rodar imediatamente e toda sexta-feira às 08:00."

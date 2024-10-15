# Jornada 365 - Manutenção Windows

## Visão Geral

Este repositório contém um script de manutenção para sistemas Windows, projetado para ser utilizado tanto localmente quanto em dispositivos gerenciados pelo **Microsoft Intune**. O script realiza diversas tarefas de manutenção essenciais, incluindo verificações de integridade do sistema, limpeza de arquivos temporários e a reinicialização do serviço do Windows Update. Com uma execução totalmente silenciosa e foco na eficiência, ele ajuda a manter o Windows em perfeito funcionamento.

## Funcionalidades

- **Verificação de Integridade do Sistema**: Executa o `sfc /scannow` e o `DISM` para detectar e reparar arquivos corrompidos no Windows.
- **Limpeza de Arquivos Temporários**: Remove arquivos temporários da pasta `%temp%` para liberar espaço em disco.
- **Reinicialização do Windows Update**: Reinicia o serviço `wuauserv` caso esteja em execução.
- **Tarefas Agendadas**: Cria tarefas agendadas para realizar manutenções automáticas mensalmente.

## Plataformas Suportadas

- **Windows 10**
- **Windows 11**

## Como Funciona

O script é executado com permissões administrativas e realiza as seguintes etapas principais:

1. **Configuração Inicial**: Cria um diretório de log no sistema e define as preferências de erro e log.
2. **Verificação do Sistema**: Utiliza o `sfc` e `DISM` para verificar e corrigir arquivos corrompidos.
3. **Limpeza de Arquivos Temporários**: Remove arquivos temporários da pasta `%temp%` para melhorar o desempenho.
4. **Reinicialização do Windows Update**: Reinicia o serviço Windows Update para garantir a disponibilidade de atualizações.
5. **Agendamento de Tarefas**: Cria tarefas agendadas para execução mensal da verificação do sistema e da manutenção.

## Como Usar

1. **Clone o Repositório**
   
   ```bash
   git clone https://github.com/seu-usuario/jornada365-manutencao-windows.git
   ```

2. **Execução Manual**

   Abra o PowerShell como administrador e execute o script:
   
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Jornada365_Manutencao.ps1
   ```

3. **Configurar via Microsoft Intune**

   - **Passo 1**: Navegue até o Centro de Administração do Intune.
   - **Passo 2**: Crie uma nova Política de Script PowerShell.
   - **Passo 3**: Carregue o script e atribua-o ao grupo de dispositivos desejado.
   - **Passo 4**: Defina a execução no contexto do **sistema** para garantir permissões administrativas.

## Estrutura do Script

- **Write-Log**: Registra mensagens de log para auditoria.
- **Ensure-Directory**: Garante a existência do diretório de logs.
- **Execute-Command**: Executa comandos como `sfc` e `DISM` com tratamento de erros.
- **Clear-TempFolder**: Limpa a pasta de arquivos temporários.
- **Restart-WindowsUpdateService**: Reinicia o serviço Windows Update.
- **Create-ScheduledTaskComponents**: Cria componentes para tarefas agendadas.
- **Set-ScheduledTask**: Configura tarefas agendadas para a execução mensal.
- **Perform-Maintenance**: Função principal que coordena todas as outras para realizar a manutenção.

## Segurança e Permissões

- O script é executado com **privilégios administrativos**, portanto, certifique-se de que ele esteja em um ambiente seguro.
- As tarefas agendadas são configuradas para rodar no contexto do sistema (“NT AUTHORITY\SYSTEM”), garantindo acesso total para realizar manutenção.

## Notas Importantes

- **Execução Silenciosa**: O script é projetado para ser executado silenciosamente, sem janelas pop-up ou interação do usuário.
- **Logs Detalhados**: Todos os eventos são registrados no arquivo de log localizado em `C:\ProgramData\Jornada365\Manutencao_Windows.log` para facilitar o acompanhamento.

## Exemplos de Uso

1. **Executar Manutenção Imediata**

   Se precisar executar uma manutenção manualmente, basta rodar o script no PowerShell elevado:
   
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Jornada365_Manutencao.ps1
   ```

2. **Verificar Logs**

   Para verificar se a manutenção foi bem-sucedida ou para depurar erros, acesse:
   
   ```
   C:\ProgramData\Jornada365\Manutencao_Windows.log
   ```

## Contato

Se precisar de ajuda ou tiver sugestões de melhorias, sinta-se à vontade para abrir uma **issue** ou entrar em contato:

- **Website**: [Jornada 365](https://jornada365.cloud)

## Contribuições

Contribuições são bem-vindas! Por favor, envie pull requests com melhorias, correções de bugs ou novas funcionalidades.


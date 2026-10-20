# PowerShell Automation Framework

Framework de automação em PowerShell para desenvolvimento, empacotamento e execução de rotinas administrativas e operacionais em ambientes Windows.

O projeto foi estruturado para permitir que diferentes automações compartilhem módulos reutilizáveis, mantenham suas configurações separadas por ambiente e sejam distribuídas como pacotes independentes para implantação em servidores.

## 1. Objetivos do projeto

O framework tem como objetivos:

- **Padronização:** estabelecer uma estrutura comum para os serviços de automação.
- **Reutilização:** centralizar funções compartilhadas em módulos.
- **Configuração por ambiente:** separar as configurações de desenvolvimento, homologação e produção.
- **Empacotamento:** gerar artefatos contendo os arquivos necessários para executar cada serviço.
- **Gerenciamento de dependências:** identificar módulos utilizados direta e indiretamente por um serviço.
- **Operação controlada:** permitir a execução manual ou agendada das automações.
- **Manutenibilidade:** manter o código-fonte organizado e desacoplado dos artefatos de implantação.

## 2. Estrutura de diretórios

A estrutura de referência do projeto é:

```text
PowerShell/
├── Modules/
│   ├── Entity/
│   │   └── Manifest.psm1
│   │   └── Response.psm1
│   └── Core/
│       ├── Configuration/
│       │   └── Configuration.psm1
│       │   └── Manifest.psd1
│       └── Logging/
│           └── Logging.psm1
│           └── Manifest.psd1
├── Services/
│   ├── Workflow-Service/
│   │   ├── Manifest.psd1
│   │   ├── Main.psm1
│   │   ├── Runner.ps1
│   │   ├── Appsettings.Desenvimento.psd1
│   │   ├── Appsettings.Homologacao.psd1
│   │   └── Appsettings.Producao.psd1
│   └── Simple-API/
├── Build/
│   └── Artifacts/
│   └── Build.ps1
└── README.md
```

A estrutura pode ser expandida conforme novos serviços forem adicionados.

### Responsabilidade de cada diretório

| Diretório/arquivo | Responsabilidade |
|---|---|
| `Modules/` | Armazena os módulos compartilhados e suas dependências. |
| `Modules/Core/` | Contém funcionalidades comuns, como configuração e logging. |
| `Modules/Entity/` | Contém classes e definições de entidades utilizadas pelo framework. |
| `Services/` | Armazena as automações independentes. |
| `Manifest.psd1` | Declara os metadados e as dependências do serviço. |
| `Main.psm1` | Contém a implementação principal da automação. |
| `Runner.ps1` | Ponto de entrada responsável por iniciar a execução do serviço. |
| `Appsettings.*.psd1` | Define os parâmetros de configuração específicos de cada ambiente. |
| `Build/` | Contém os scripts responsáveis pelo empacotamento. |
| `Artifacts/` | Armazena os pacotes gerados para distribuição e implantação. |

## 3. Normas gerais de desenvolvimento

Para garantir o funcionamento previsível do framework, as seguintes convenções devem ser respeitadas.

### 3.1. Separação de responsabilidades

Cada arquivo deve possuir uma finalidade clara:

- `Runner.ps1`: inicialização, carregamento de dependências, configuração do ambiente e controle da execução.
- `Main.psm1`: implementação da lógica de negócio da automação.
- `Manifest.psd1`: declaração dos metadados e módulos necessários.
- `Appsettings.<Environment>.psd1`: parâmetros específicos do ambiente.
- `Modules/`: funções e componentes compartilhados.

A lógica principal do serviço não deve ser duplicada no `Runner.ps1`. Isso facilita testes, manutenção e reutilização.

### 3.2. Convenções de nomenclatura

- Cada automação deve possuir seu próprio diretório dentro de `Services/`.
- Os arquivos de entrada devem manter os nomes `Runner.ps1` e `Main.psm1`.
- O manifesto deve ser denominado `Manifest.psd1`.
- Os arquivos de configuração devem seguir o padrão `Appsettings.<Environment>.psd1`.
- Os módulos compartilhados devem permanecer dentro de `Modules/`, respeitando a organização de diretórios utilizada pelo projeto.

### 3.3. Retorno explícito de funções

As funções devem deixar claro qual resultado será retornado. Sempre que aplicável, utilizar `return` explícito para facilitar a leitura e a manutenção.

Exemplo:

```powershell
function Get-ServiceStatus {
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName
    )

    $service = Get-Service -Name $ServiceName -ErrorAction Stop

    return $service.Status
}
```

Evite misturar valores de retorno com mensagens de diagnóstico no fluxo de saída da função. Utilize o mecanismo de logging para registrar informações operacionais.

### 3.4. Tratamento de erros

Operações que possam falhar devem possuir tratamento adequado, principalmente:

- Leitura de arquivos de configuração.
- Carregamento de módulos.
- Acesso a serviços e recursos externos.
- Operações de rede.
- Execução de comandos administrativos.
- Manipulação de arquivos.
- Processos de implantação.

Exemplo:

```powershell
try {
    $configuration = Get-Configuration -Path $ConfigurationPath

    if (-not $configuration.Status) {
        throw "Não foi possível carregar a configuração."
    }

    # Continuar a execução do serviço.
}
catch {
    Write-Error "Falha na execução: $($_.Exception.Message)"
    throw
}
```

A falha não deve ser silenciosamente ignorada. Quando a automação não puder continuar com segurança, ela deverá encerrar com um erro identificável.

## 4. Configuração dos serviços

Cada serviço deve possuir arquivos de configuração independentes para os ambientes suportados.

Os nomes atualmente utilizados pelo projeto são:

| Ambiente | Arquivo |
|---|---|
| Desenvolvimento | `Appsettings.Desenvimento.psd1` |
| Homologação | `Appsettings.Homologacao.psd1` |
| Produção | `Appsettings.Producao.psd1` |

**Importante:** os nomes acima fazem parte do contrato atual do projeto. A grafia `Desenvimento` deve ser mantida enquanto os scripts e os arquivos utilizarem essa convenção.

### 4.1. Exemplo de configuração

O conteúdo deve seguir o formato de tabela de dados do PowerShell (`.psd1`).

Exemplo ilustrativo:

```powershell
@{
    ServiceName = 'Workflow-Service'

    Logging = @{
        Level = 'INFO'
        Path  = '.\Logs'
    }

    Execution = @{
        TimeoutSeconds = 300
    }
}
```

As propriedades desse exemplo são ilustrativas. Cada serviço deve definir e validar as propriedades que realmente utiliza.

### 4.2. Carregamento da configuração

O módulo `Modules/Core/Configuration.psm1` disponibiliza a função `Get-Configuration`.

Exemplo:

```powershell
Import-Module `
    "$HOME_PROJECT\Modules\Core\Configuration.psm1" `
    -Force

$configurationPath = Join-Path `
    $PSScriptRoot `
    'Appsettings.Producao.psd1'

$response = Get-Configuration -Path $configurationPath

if (-not $response.Status) {
    throw "Falha ao carregar configuração: $($response.Messages -join '; ')"
}

$config = $response.Data
```

A função retorna um objeto com três propriedades:

- `Status`: indica se a configuração foi carregada com sucesso.
- `Messages`: contém mensagens relacionadas à operação.
- `Data`: contém os dados carregados, ou `$null` em caso de falha.

### 4.3. Regras para arquivos de configuração

1. Não utilizar configurações de produção durante testes locais sem necessidade.
2. Manter a mesma estrutura lógica entre os ambientes quando o serviço exigir as mesmas propriedades.
3. Validar as propriedades obrigatórias antes de executar operações críticas.
4. Não armazenar senhas, tokens ou outras credenciais diretamente em arquivos versionados.
5. Não incluir configurações desnecessárias no pacote de implantação.
6. Garantir que o serviço utilize o arquivo correspondente ao ambiente selecionado.

## 5. Manifesto do serviço

O arquivo `Manifest.psd1` declara os metadados utilizados pelo processo de build para identificar e empacotar o serviço.

As propriedades aceitas devem corresponder à classe `Manifest`, implementada em `Modules/Entity/Manifest.psm1`.

### Exemplo ilustrativo

```powershell
@{
    RequiredModules = @(
        'Configuration'
        'Logging'
    )
}
```

Esse exemplo representa apenas a declaração das dependências. O manifesto real deve incluir todas as propriedades exigidas pela implementação da classe `Manifest`.

### Regras para dependências

- Declarar os módulos compartilhados dos quais o serviço depende diretamente.
- Manter os nomes compatíveis com a forma como o processo de build resolve os módulos.
- Não declarar dependências inexistentes.
- Garantir que cada dependência esteja disponível no diretório esperado pelo framework.
- Evitar depender de módulos instalados manualmente no servidor de destino sem documentar essa exigência.

O build deve resolver as dependências diretas e indiretas identificáveis no código, incluindo referências estáticas feitas por `Import-Module` e `using module`.

Por exemplo:

```text
Workflow-Service
└── Configuration
    └── Logging
```

Se `Workflow-Service` utilizar `Configuration`, e `Configuration` utilizar `Logging`, o pacote também deverá conter `Logging`, mesmo que o serviço não o importe diretamente.

**Limitação:** referências construídas dinamicamente em tempo de execução não são necessariamente identificadas pela análise estática. Dependências dinâmicas, recursos externos e módulos nativos devem ser documentados e verificados separadamente.

## 6. Desenvolvimento de um novo serviço

Para adicionar uma automação, crie um diretório exclusivo dentro de `Services/`.

Exemplo:

```text
Services/
└── Minha-Automacao/
    ├── Manifest.psd1
    ├── Main.psm1
    ├── Runner.ps1
    ├── Appsettings.Desenvimento.psd1
    ├── Appsettings.Homologacao.psd1
    └── Appsettings.Producao.psd1
```

### Etapa 1 — Criar o `Main.psm1`

Esse arquivo deve conter as funções que implementam a automação.

Exemplo simplificado:

```powershell
function Invoke-MyAutomation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Configuration
    )

    Write-Output 'Executando minha automação.'

    # Implementar a lógica do serviço.

    return $true
}

Export-ModuleMember -Function Invoke-MyAutomation
```

Esse exemplo demonstra a estrutura, não uma implementação completa de negócio. Em um serviço real, prefira registrar mensagens operacionais no módulo de logging em vez de utilizar `Write-Output` para diagnóstico.

### Etapa 2 — Criar o `Runner.ps1`

O `Runner.ps1` é o ponto de entrada da execução. Ele deve orquestrar o carregamento da configuração e da implementação principal, além de propagar falhas.

A assinatura dos parâmetros deve ser compatível com a utilizada pelo framework. No projeto atual, o parâmetro de ambiente é `Enviromnet`.

Exemplo conceitual:

```powershell
param(
    [Parameter(Mandatory)]
    [ValidateSet('Desenvimento', 'Homologacao', 'Producao')]
    [string]$Enviromnet
)

$ErrorActionPreference = 'Stop'

# Carregar a configuração do ambiente.
# Importar o módulo principal.
# Executar a automação.
# Propagar erros para o processo chamador.
```

O código acima é um esqueleto. O `Runner.ps1` definitivo deve implementar o fluxo de inicialização padronizado do projeto.

### Etapa 3 — Criar o `Manifest.psd1`

Declare as dependências diretas do serviço conforme a classe `Manifest` e o mecanismo de resolução implementados no framework.

### Etapa 4 — Criar os arquivos de ambiente

Crie os arquivos exigidos para os ambientes suportados e valide que o serviço não tente carregar um arquivo inexistente.

### Etapa 5 — Testar manualmente

Antes de gerar o pacote, execute o serviço diretamente no PowerShell:

```powershell
$HOME_PROJECT = 'C:\Projetos\PowerShell'

Set-Location "$HOME_PROJECT\Services\Minha-Automacao"

.\Runner.ps1 -Enviromnet Desenvimento
```

Ajuste o caminho conforme o local real do repositório.

## 7. Processo de build

O processo de build é responsável por preparar uma versão distribuível do serviço.

O objetivo é gerar um pacote isolado, sem modificar a estrutura original do código-fonte.

### O que o build deve fazer

1. Localizar o serviço informado.
2. Validar a existência do manifesto e dos arquivos obrigatórios.
3. Carregar e validar os metadados.
4. Resolver as dependências diretas e indiretas identificáveis.
5. Preparar um diretório temporário de staging.
6. Copiar os arquivos necessários para o staging.
7. Preservar a estrutura de diretórios dos módulos.
8. Gerar o arquivo ZIP de distribuição.
9. Calcular o hash SHA-256 do artefato.
10. Limpar os arquivos temporários ao término do processo.

O código-fonte original deve permanecer intacto durante a geração do pacote.

### Exemplo de build

No diretório raiz do projeto:

```powershell
.\Build\Build.ps1 `
    -Service 'Workflow-Service' `
    -Version '1.0.0' `
    -Enviromnet Producao
```

Esse exemplo considera os parâmetros definidos para o script de build atual. A saída esperada é um pacote versionado e seu arquivo de hash, dentro do diretório de artefatos configurado pelo build.

Exemplo de nomenclatura:

```text
Artifacts/
├── Workflow-Service.1.0.0.zip
└── Workflow-Service.1.0.0.zip.sha256
```

O nome e o caminho efetivos dos arquivos dependem da implementação atual do `Build.ps1`.

### Regras de versionamento

- Utilizar uma versão identificável para cada pacote.
- Não sobrescrever silenciosamente um artefato que já foi distribuído, salvo quando esse comportamento for intencional.
- Gerar novamente o artefato após qualquer alteração no código ou nas dependências.
- Armazenar o pacote de distribuição separado do código-fonte.
- Registrar qual versão foi implantada em cada servidor.

### Validação do artefato

Após o build, valide a integridade do pacote:

```powershell
Get-FileHash `
    -Path '.\Artifacts\Workflow-Service.1.0.0.zip' `
    -Algorithm SHA256
```

Compare o valor calculado com o conteúdo do arquivo `.sha256` gerado pelo processo de build.

O hash permite verificar a integridade do arquivo, mas não comprova sozinho sua autenticidade ou procedência.

## 8. Implantação e execução

O pacote gerado deve conter os arquivos necessários para a execução do serviço e suas dependências identificadas.

Uma implantação deve contemplar, no mínimo:

1. Copiar o artefato para o servidor de destino.
2. Validar a integridade do arquivo.
3. Extrair o pacote em um diretório dedicado ao serviço e à versão implantada.
4. Confirmar a disponibilidade do PowerShell exigido pela automação.
5. Verificar permissões de arquivos, diretórios, recursos de rede e serviços utilizados.
6. Validar a configuração do ambiente.
7. Executar o `Runner.ps1` manualmente.
8. Somente após a validação, configurar ou atualizar a execução agendada.

Exemplo de extração:

```powershell
$Artifact = 'C:\Deploy\Workflow-Service.1.0.0.zip'
$Destination = 'C:\Automations\Workflow-Service'

Expand-Archive `
    -LiteralPath $Artifact `
    -DestinationPath $Destination `
    -Force
```

O diretório de destino deve corresponder à estrutura contida no ZIP. Caso o pacote inclua uma pasta raiz adicional, ajuste o caminho de extração ou a estrutura produzida pelo build.

## 9. Execução periódica com Task Scheduler

Para automações que precisam ser executadas em intervalos regulares, o Windows Task Scheduler pode iniciar o `Runner.ps1` sem exigir um processo de serviço permanente.

Exemplo de comando de execução:

```powershell
$RunnerPath = 'C:\Automations\Workflow-Service\Runner.ps1'

& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $RunnerPath `
    -Enviromnet Producao
```

A tarefa deve ser configurada com:

- Um usuário ou uma conta de serviço com as permissões necessárias.
- O caminho correto do executável do PowerShell.
- O diretório de trabalho apropriado.
- O ambiente correspondente ao servidor.
- Um intervalo de execução compatível com a duração da automação.
- Uma política para impedir execuções simultâneas, quando necessário.
- Registro e monitoramento de falhas.

Se a tarefa for executada como `SYSTEM`, lembre-se de que essa conta possui um contexto diferente do usuário interativo. Unidades de rede mapeadas, credenciais armazenadas no perfil de usuário e configurações específicas desse perfil podem não estar disponíveis.

**Importante:** `-ExecutionPolicy Bypass` não concede privilégios administrativos e não substitui as políticas de segurança da organização.

## 10. Logging e diagnóstico

O módulo `Modules/Core/Logging.psm1` centraliza o registro de eventos da automação.

As funções disponibilizadas pelo módulo são:

- `Start-Log`: inicializa o arquivo de log.
- `Write-Log`: registra uma mensagem com nível de severidade.
- `Stop-Log`: encerra o gravador de log.

Exemplo de utilização:

```powershell
Import-Module `
    "$HOME_PROJECT\Modules\Core\Logging.psm1" `
    -Force

Start-Log -Path 'C:\Logs\Workflow-Service.log'

try {
    Write-Log -Level INFO -Message 'Execução iniciada.'

    # Executar a automação.

    Write-Log -Level INFO -Message 'Execução concluída.'
}
catch {
    Write-Log `
        -Level ERROR `
        -Message "Falha na execução: $($_.Exception.Message)"

    throw
}
finally {
    Stop-Log
}
```

A assinatura dos comandos deve permanecer compatível com a implementação efetiva do módulo.

### Recomendações de logging

- Registrar início e término da execução.
- Registrar falhas com contexto suficiente para diagnóstico.
- Utilizar níveis de severidade consistentes.
- Não registrar senhas, tokens ou dados sensíveis.
- Definir uma política de retenção e rotação dos logs.
- Garantir que a conta de execução tenha permissão de escrita no diretório.
- Diferenciar uma falha da automação de uma falha no mecanismo de agendamento.

## 11. Requisitos de ambiente

Antes de executar ou implantar uma automação, verifique:

- Versão do PowerShell compatível com o código.
- Disponibilidade de todos os módulos necessários.
- Existência dos arquivos de configuração do ambiente.
- Permissões de leitura e execução nos diretórios do serviço.
- Permissões de escrita nos diretórios de log e de saída.
- Acesso a serviços, APIs, bancos de dados e recursos externos utilizados.
- Disponibilidade das credenciais necessárias por mecanismos seguros.
- Existência e permissões da conta utilizada pelo Task Scheduler.
- Caminhos absolutos válidos no servidor de destino.

Não presuma que o ambiente de uma sessão interativa será igual ao ambiente de execução agendada.

## 12. Checklist antes de publicar uma versão

### Código e estrutura

- [ ] O serviço possui `Manifest.psd1`, `Main.psm1` e `Runner.ps1`.
- [ ] Os arquivos de configuração exigidos existem.
- [ ] As dependências diretas estão declaradas corretamente.
- [ ] As dependências transitivas identificáveis foram incluídas.
- [ ] Os erros são tratados e propagados corretamente.
- [ ] Os logs não expõem informações sensíveis.

### Build

- [ ] O build termina sem erros.
- [ ] O ZIP contém os arquivos necessários.
- [ ] A estrutura dos módulos foi preservada.
- [ ] O artefato pode ser extraído em um diretório limpo.
- [ ] O hash SHA-256 foi calculado e validado.
- [ ] O código-fonte original não foi alterado pelo processo de build.

### Execução

- [ ] O `Runner.ps1` funciona manualmente no ambiente de destino.
- [ ] O ambiente selecionado é o correto.
- [ ] A conta de execução possui as permissões necessárias.
- [ ] A execução agendada foi testada.
- [ ] O comportamento em caso de falha foi validado.
- [ ] A política para execuções simultâneas foi verificada.

## 13. Resolução de problemas

| Sintoma | Verificações recomendadas |
|---|---|
| Serviço não encontrado no build | Confira o nome do diretório dentro de `Services/`. |
| Manifesto inválido | Verifique a sintaxe do `.psd1` e as propriedades exigidas pela classe `Manifest`. |
| Módulo não encontrado | Confira a localização, o nome e as referências de importação. |
| Configuração não encontrada | Verifique o ambiente informado e o nome exato do arquivo. |
| Funciona manualmente, mas falha no agendamento | Confira a conta de execução, o diretório de trabalho, as permissões e as variáveis de ambiente. |
| Duas execuções simultâneas | Configure a política de instâncias simultâneas no Task Scheduler. |
| Artefato diferente do esperado | Gere novamente o build, valide o conteúdo do ZIP e compare o hash. |
| Falha em recurso de rede | Verifique conectividade, permissões e credenciais da conta de execução. |

## 14. Princípios para evolução do framework

Ao adicionar novas funcionalidades, preserve os seguintes princípios:

1. **Baixo acoplamento:** um serviço não deve depender da implementação interna de outro serviço sem uma necessidade explícita.
2. **Reutilização:** funcionalidades compartilhadas devem ficar em módulos comuns.
3. **Previsibilidade:** cada serviço deve possuir um ponto de entrada e um contrato de configuração claros.
4. **Portabilidade:** os artefatos devem carregar suas dependências locais identificadas, sem depender acidentalmente da estrutura do repositório de desenvolvimento.
5. **Segurança:** credenciais e dados sensíveis não devem ser distribuídos dentro dos pacotes.
6. **Rastreabilidade:** cada artefato deve possuir uma versão e um hash verificável.
7. **Operabilidade:** falhas precisam ser registradas e identificáveis no ambiente de execução.
8. **Compatibilidade:** alterações em nomes de parâmetros, estruturas de configuração ou contratos dos módulos devem ser tratadas como mudanças que podem afetar os serviços existentes.

---

## Resumo do fluxo de trabalho

```text
Desenvolvimento do serviço
          |
          v
Validação do Runner e configuração
          |
          v
Declaração das dependências
          |
          v
Build e resolução de dependências
          |
          v
Geração do ZIP e do SHA-256
          |
          v
Implantação no servidor
          |
          v
Teste manual
          |
          v
Agendamento da execução
          |
          v
Logs e diagnóstico operacional
```

O fluxo recomendado é desenvolver e validar o serviço, gerar um artefato versionado, testar o pacote em um diretório limpo e somente então disponibilizá-lo para execução no servidor de destino.

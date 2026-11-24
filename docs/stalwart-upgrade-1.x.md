# Stalwart 0.16.27 → 1.x: avaliação e plano de migração

Estado: **plano, nada executado** (24/11/2026). Fontes: notas de versão v1.0.0–v1.2.0 em
github.com/stalwartlabs/stalwart, `SECURITY.md` do mesmo repo, README, `SCHEMA_CHANGES.md` e CHANGELOG de
github.com/stalwartlabs/stalwart-migrate (v1.0.8), stalw.art/docs/migration/upgrade-0-16/ (e a subpágina
troubleshooting), notas de versão do Bulwark 1.18–1.21.3.

## 1. Recomendação

**Esperar.** Fazer o ensaio (secção 5) quando houver tempo. A migração real fica para uma janela entre
meados de dezembro de 2026 e março de 2027, quando se cumprirem estas condições:

- o `stalwart-migrate` ≥ 1.0.9 já saiu (a 1.0.9 ainda não foi lançada e corrige amostras de spam expiradas
  que bloqueiam o `run --final`);
- a linha 1.x de destino tem pelo menos um patch e 7 dias sem regressões (a v1.2.0 saiu a 23/11/2026);
- o ensaio passou todos os critérios da secção 5.

Porquê:

| Facto | Implicação |
|---|---|
| A 0.16.x tem correções de segurança até **2027-06-01** (`SECURITY.md`) | Não há urgência de segurança. |
| A 1.0.0 saiu a 26/10/2026, com 7 versões em 4 semanas (1.0.0 → 1.2.0) | A linha ainda é nova e muda depressa. |
| O `stalwart-migrate` teve 9 versões em 16 dias (1.0.0 → 1.0.8) e a 1.0.9 ainda tem uma correção pendente | A ferramenta de migração também está a amadurecer. |
| Não se faz atualização no lugar: muda o layout da BD, o schema das definições e a CLI | É uma migração, não um `pull`. |
| O volume de dados é pequeno (6,8 MB em `stalwart-data`, backup de 1,5 MB) | A cópia em si leva minutos. O risco está na configuração e não no volume. |

Esperar não traz nada de novo para esta instalação: não usamos EWS, IA, OIDC externo, cifra em repouso,
multi-tenant nem passkeys.

## 2. O que existe hoje (levantado na VPS em 24/11/2026, só leitura)

| Item | Valor |
|---|---|
| Diretório e compose | `/opt/mail` (este repo, HEAD `e70e8d2`, árvore limpa), projeto compose `mail` |
| Imagem | `stalwartlabs/stalwart:v0.16.27` (fixada), container `stalwart`, healthy |
| Webmails | `ghcr.io/bulwarkmail/webmail:1.21.3` ×2 (`bulwark`, `bulwark-olhaqueduas`), JMAP via Traefik |
| Armazenamento | **RocksDB**. `/etc/stalwart/config.json` = `{"@type":"RocksDb","path":"/var/lib/stalwart/",…}` (128 bytes). Toda a restante configuração fica no registo, dentro do store. Não há `config.toml`: o formato TOML deixou de existir na 0.16. |
| Volumes | `mail_stalwart-etc`, `mail_stalwart-data` e 12 volumes `mail_bulwark-*` |
| Portas | 25, 465 e 993 publicadas no host. HTTP em `127.0.0.1:8480` → Traefik. 587 e 995 ficam fechadas de propósito. |
| TLS | Sem ACME no Stalwart. Os domínios estão em `certificateManagement: Manual`, os certificados saem do `acme.json` do Traefik pelo `sync-certs.py` (cron 03:17 UTC, faz `docker restart stalwart` se mudou) e o objeto `Certificate` aponta para `/certs/mail.leoschlanger.com/{cert,key}.pem` (mais `mail.olhaqueduas.com` por SNI). |
| Domínios | `leoschlanger.com`, `olhaqueduas.com` e **`astralvita.com`** (3, no `plan.ndjson`). DKIM `Automatic` com Ed25519 + RSA e rotação a 10 anos (desligada na prática). DNS manual. |
| Configuração como código | `stalwart/plan.ndjson` (schema 0.16), aplicado por `configure.sh apply` com `stalwartlabs/cli:1.0.14` |
| Backup | `backup.sh` às 04:45 UTC: para o Stalwart, faz tar de todos os volumes `mail_*` e guarda 7 dias em `/opt/mail/backups` (último: `mail-20261124-044501.tar.gz`, 1,5 MB) |
| Host | 2 vCPU, 7,8 GiB de RAM (4,5 disponíveis), 50 GB livres em `/`, fuso UTC |

## 3. Breaking changes que afetam esta instalação

Esta lista vem do `plan.ndjson`, do `config.json` e do compose. A lista definitiva sai do
`prepare-report.txt` do ensaio, que lê o registo vivo.

| # | Mudança (versão) | Efeito aqui | Ação |
|---|---|---|---|
| 1 | Layout novo da BD (1.0.0). A 1.x não abre um store 0.16. | Obrigatório usar o `stalwart-migrate`, que copia RocksDB → RocksDB para um diretório novo e vazio. O store 0.16 só é lido e fica intacto. | Volumes novos `stalwart-v1-etc`/`stalwart-v1-data` e volume de estado do migrate |
| 2 | A origem tem de ser 0.16.27 | Já cumprido | — |
| 3 | `Http.useXForwarded` → `clientIpSource` + `forwardedHops` (1.0.0). Hoje está `true`. | O `prepare` pergunta. Com a resposta errada, o IP de todos os clientes HTTP passa a ser o do gateway 172.30.50.1, e um auto-ban corta o webmail a todos. | Responder `xForwardedFor` e `forwardedHops = 1` (o Traefik envia `X-Forwarded-For` e não `Forwarded`). Validar no ensaio. |
| 4 | Planos NDJSON com schema 0.16 são recusados pela 1.x | `configure.sh apply` deixa de funcionar com o `plan.ndjson` atual | Converter com `cli-plan/convert_plan.py` do repo do migrate, na tag da versão usada (developer) |
| 5 | `Bootstrap.serverHostname` → `defaultHostname` | Só afeta `configure.sh bootstrap` (instalação do zero) | Corrigir o script (developer) |
| 6 | CLI: a `cli:1.0.14` está fixada como «testada na 0.16» e a `latest` passou à 2.0.0 a 16/11 | Não se sabe se a 1.0.14 fala com a 1.x | Testar no ensaio. Se falhar, fixar `stalwartlabs/cli:2.0.x` e ajustar o `configure.sh`. |
| 7 | A 1.x só serve o WebUI v2 (o migrate troca o URL do bundle oficial). Na 1.2.0: «Upgrade the WebUI to version 2.1.1». | O `/admin` e o `/account` mudam de aspeto. O bundle é descarregado da internet no arranque (houve um bug de 404 na 1.0.0–1.0.1, corrigido na 1.0.2). | Verificar `/admin` e `/account` depois do arranque |
| 8 | Tokens OAuth não são migrados | Toda a gente volta a entrar no webmail e nos clientes OAuth | Correr «Auto-configure OAuth» uma vez nos **dois** Bulwark (Admin → Authentication), como mandam as notas do Bulwark 1.18.0. Avisar as utilizadoras da OQD. |
| 9 | Permissões novas nos papéis por omissão (1.0.3, 1.1.0 passkeys, 1.2.0) | Algumas secções do admin ficam escondidas | Arrancar uma vez com `STALWART_UPDATE_ROLE_PERMISSIONS=true` e depois tirar a variável |
| 10 | Os padrões dos relatórios passaram a `system('report_domain')` (DMARC, TLS-RPT, DSN) | O remetente dos relatórios TLS/DMARC pode mudar (hoje é `noreply-tls@leoschlanger.com`) | Em «Changed defaults», manter os padrões 0.16 (pin) ou confirmar que `report_domain` = `leoschlanger.com` |
| 11 | Tags de spam novas com pontuação de origem (`AI_*`, `DKIM2_*`, `DISPOSABLE_BCC`…), `LLM_*` removidas | O veredito de spam pode mudar um pouco. O redirecionamento para o Gmail filtra por `X-Spam-Status`. | Vigiar o Lixo eletrónico e o Gmail durante a 1.ª semana |
| 12 | O índice full-text não é copiado e é reconstruído no arranque | A pesquisa fica incompleta por alguns minutos | — |
| 13 | `MtaStageAuth.saslMechanisms` perde o ramo OAUTHBEARER/XOAUTH2 fora da porta 25 | Só afeta clientes SMTP com OAuth. Os nossos usam senha na 465. | Confirmar no ensaio que a 465 aceita AUTH PLAIN/LOGIN |
| 14 | 1.2.0: auto-ban por /64 em IPv6, `Return-Path` em todas as mensagens guardadas, timeouts de escrita SMTP/IMAP | Neutro ou positivo | — |
| 15 | Licença e edição: o código continua AGPL-3.0. A imagem oficial é o build com funções Enterprise (SEL), que funciona sem licença. A versão do schema fica ligada à edição. Os testes passaram a privados (governação, não licença). | Nada a pagar, nada muda | Usar a imagem **standard** do migrate, nunca a `-oss` |
| 16 | ACME: mudanças em DNS-01, validação de SAN e renovação (1.0.1, 1.1.0) | **Não se aplicam**: o ACME do Stalwart não está em uso (Manual + ficheiros do Traefik) | — |
| 17 | Telemetria e métricas renumeradas e renomeadas | Não usamos (tracer Stdout) | — |
| 18 | Variáveis de ambiente: `STALWART_RECOVERY_MODE`/`STALWART_RECOVERY_ADMIN` continuam citadas nas notas da 1.1.0 e da 1.2.0 (que acrescenta `STALWART_RECOVERY_MODE_BIND`). `STALWART_PUBLIC_URL` continua a existir (passkeys, 1.1.0). | Devem funcionar | Testar o modo de recuperação no ensaio |

Pontos em aberto, que o ensaio responde:

- **Versão de arranque.** A documentação só fala em «1.0» e o `SCHEMA_CHANGES.md` vai até à 1.0.3. Nada diz
  que um store criado pelo migrate 1.0.8 abre diretamente na 1.1.1 ou na 1.2.x. Portão: arrancar diretamente
  na versão alvo. Se recusar, arrancar na 1.0.3 e depois atualizar no lugar para a alvo (dentro da 1.x, a
  atualização é no lugar).
- **Bulwark com OQD.** O webmail da OQD usa `mail.olhaqueduas.com` e a `STALWART_PUBLIC_URL` é
  `mail.leoschlanger.com`. Testar o login e o «Auto-configure OAuth» nos dois.
- **Issues públicos.** A pesquisa no GitHub (24/11) não devolveu issues sobre a migração, mas o repo do
  migrate não mostra issues pela API. Fica **não verificado**, não «sem problemas conhecidos».

## 4. Backup (antes do ensaio e antes da janela)

1. `/opt/mail/scripts/backup.sh` manual. Copiar `mail-<ts>.tar.gz` e `env-<ts>` para
   `/root/pre-stalwart-v1-<AAAAMMDD>/`, **fora** de `/opt/mail/backups` (a rotação apaga aos 7 dias), e uma
   cópia para fora da VPS (máquina do Leo ou destino restic). Guardar o `sha256sum` dos dois ficheiros.
2. `docker image save stalwartlabs/stalwart:v0.16.27 | gzip > /root/pre-stalwart-v1-<data>/stalwart-v0.16.27.tar.gz`,
   para o rollback não depender do Docker Hub.
3. Configuração: `configure.sh cli snapshot > snapshot-0.16.ndjson` (plano do registo vivo, segredos
   mascarados). Fica no mesmo diretório e **nunca** no git.
4. DNS e DKIM de referência, por domínio (`leoschlanger.com`, `olhaqueduas.com`, `astralvita.com`):
   `configure.sh dns <dom> > dns-<dom>-0.16.txt` e
   `dig +short MX/TXT <dom>`, `_dmarc.<dom>`, `_smtp._tls.<dom>` e cada `<seletor>._domainkey.<dom>`
   (os seletores aparecem no `dns-*.txt`).
5. Contagens de referência: `IMAP STATUS` (MESSAGES, UIDVALIDITY, UIDNEXT) das caixas principais de cada conta
   e `configure.sh cli query QueuedMessage` (de preferência vazia).

Retenção: os volumes 0.16 (`mail_stalwart-etc`/`-data`), o volume de estado do migrate e o diretório
`/root/pre-stalwart-v1-*` ficam **pelo menos 30 dias** depois da migração e até a 0.16 ser dada como retirada.
O rollback precisa do estado (`--forward-state`).

## 5. Ensaio num container paralelo (sem tocar em produção)

Objetivo: ensaiar a migração inteira sobre uma cópia, sem nenhuma entrega real. Duração: ~2 h, com o ensaio
do rollback incluído. Nomes no host: `/root/ensaio-stalwart-v1-<AAAAMMDD>/`, volumes `ensaio_*`, rede
`ensaio-net`. Tudo é apagado no fim.

**Isolamento** (o v1 de ensaio não pode entregar correio nem relatórios em duplicado):
- origem = o tarball da noite restaurado em volumes novos `ensaio_v016-etc`/`ensaio_v016-data` (nunca os
  volumes de produção);
- `run --final … --exclude queue,tasks` (sem fila de saída nem tarefas agendadas, logo sem relatórios
  DMARC/TLS);
- rede `docker network create --internal ensaio-net`, sem portas publicadas (a 25, 465 e 993 de produção
  continuam do 0.16);
- estado próprio em `ensaio_state`. Do ensaio para a produção só se reaproveita o `answers.toml`.

Passos:

1. Restaurar `stalwart-etc` e `stalwart-data` do tarball para os volumes de ensaio (alpine:3.22, `tar x` só
   dessas duas pastas). Criar `ensaio_v1-etc` com `config.json` = `{"@type":"RocksDb","path":"/var/lib/stalwart-v1/"}`
   e `ensaio_v1-data` vazio. Assim não é preciso `--target-path-map`, porque o v1 monta o volume novo em
   `/var/lib/stalwart-v1`.
2. `prepare` (interativo, `docker run --rm -it --ulimit nofile=65536:65536 --network ensaio-net`, com os
   volumes montados como no README do migrate, imagem `stalwartlabs/stalwart-migrate:<última 1.0.x>`).
   Respostas: client IP = `xForwardedFor`, hops = 1. «Changed defaults» = seguir a recomendação, exceto os
   padrões dos relatórios (#10). Guardar `answers.toml` e `prepare-report.txt` e lê-los à procura de
   `dropped`/`error`.
3. `run --final --yes --exclude queue,tasks --owner 2000:2000 --verify-full`. Critério: termina sem erros e
   com `verify: … 0 mismatches`. Rever `final-report.txt`.
4. Arrancar o v1 de ensaio: `stalwartlabs/stalwart:<alvo>` na `ensaio-net`, com `ensaio_v1-etc` em
   `/etc/stalwart`, `ensaio_v1-data` em `/var/lib/stalwart-v1` e `/opt/mail/certs:/certs:ro`, as mesmas
   variáveis do compose e `STALWART_UPDATE_ROLE_PERMISSIONS=true`. Se a versão alvo recusar o store, repetir
   com a 1.0.3 e depois a alvo (ver o portão na secção 3).
5. Testes a partir de um container auxiliar na mesma rede:
   - logs sem `ERROR` no arranque; health `/healthz/live` = 200;
   - IMAP 993 (`openssl s_client -servername mail.leoschlanger.com` e também `mail.olhaqueduas.com`): o
     certificado certo por SNI, login, `STATUS` igual às contagens de referência (UIDVALIDITY incluído);
   - SMTP 465: TLS e `AUTH PLAIN` aceites. **Não** enviar nada para fora (a rede interna não deixa);
   - `configure.sh dns <dom>` contra o ensaio, nos 3 domínios: `diff` com `dns-<dom>-0.16.txt`, com os
     seletores e chaves DKIM iguais;
   - `NetworkListener`: sem `pop3s`, com o listener `http` em 8080;
   - CLI: `cli:1.0.14` faz `query Domain` e `apply --dry-run` do plano convertido. Se falhar, repetir com
     `cli:2.0.x`;
   - modo de recuperação: `STALWART_RECOVERY_MODE=1` + admin temporário, com o login a funcionar no 8080;
   - IP do cliente: um pedido HTTP com `X-Forwarded-For: 203.0.113.7` aparece com esse IP nos logs do
     v1. O IP tem de aparecer certo.
6. WebUI (opcional, precisa de saída para a internet): reiniciar o v1 de ensaio numa rede **não** interna,
   ainda sem portas publicadas (a fila e as tarefas não foram copiadas, por isso não há nada a enviar).
   Critério: `/admin` e `/account` devolvem 200 e o bundle v2 carrega.
7. Ensaio do rollback: parar o v1 de ensaio e correr `stalwart-migrate rollback --source <v1> --target <novo
   0.16 vazio> --state ensaio_rollback-state --forward-state ensaio_state`. Arrancar a 0.16.27 sobre esse
   store. Critério: as mesmas contagens IMAP e os mesmos DKIM.
8. Limpeza: `docker rm -f` dos containers de ensaio, `docker volume rm ensaio_*`,
   `docker network rm ensaio-net`, apagar `/root/ensaio-stalwart-v1-*` (guardar antes o `answers.toml` e os
   relatórios no diretório `pre-stalwart-v1`).

## 6. Migração real (janela)

**Janela:** ~90 min, das quais 15–30 min com SMTP e IMAP em baixo. Os remetentes voltam a tentar (fila de
dias), por isso não se perde correio. Fora das 03:17 e das 04:45 UTC, porque os dois crons reiniciam o
container `stalwart`. Sugestão: dia útil entre as 20:00 e as 22:00 UTC, com o Leo disponível e as
utilizadoras da OQD avisadas do novo login no webmail.

**Antes da janela** (com a 0.16 a servir):
- o developer prepara um ramo com o compose v1 (secção 8), sem deploy;
- `prepare` sobre a produção (lê o registo vivo, `--source` = volume real `:ro`), com o `answers.toml` do
  ensaio como ponto de partida;
- um `run` incremental com a 0.16 ligada (permitido pela ferramenta; adianta a cópia).

**Na janela:**
1. Comentar as duas linhas do Stalwart em `/etc/cron.d/mail-stack` (sync-certs e backup).
2. Fazer o backup da secção 4 (passos 1–5).
3. `docker compose stop stalwart` (os webmails ficam a mostrar erro de ligação).
4. `docker compose run --rm migrate run --final --yes --owner 2000:2000 --verify-full`, **com** fila e
   tarefas. Critério: 0 erros e 0 mismatches. Rever `final-report.txt`.
5. Mudar para o ramo v1 e correr `docker compose up -d stalwart` com `STALWART_UPDATE_ROLE_PERMISSIONS=true`.
   Depois tirar a variável e correr outra vez `docker compose up -d stalwart`.
6. Verificação (secção 7). **Ponto de não retorno:** o primeiro correio recebido ou escrito pelo IMAP/JMAP
   no v1. Até lá vale o rollback A (secção 9).
7. «Auto-configure OAuth» nos dois Bulwark.
8. Descomentar os crons. Correr `sync-certs.py --no-restart`, que tem de dizer «sem mudanças», e um
   `backup.sh` manual, que tem de incluir os volumes v1.

## 7. Verificação (critérios de aceite)

- [ ] `docker compose ps`: `stalwart` healthy na versão alvo; logs sem `ERROR` no arranque.
- [ ] Portas abertas a partir de fora: `openssl s_client -connect mail.leoschlanger.com:465`, `:993` e
      `-starttls smtp :25`. Certificados com SAN e validade iguais aos do Traefik, e `mail.olhaqueduas.com`
      certo por SNI. A 587 continua fechada.
- [ ] HTTPS: `/admin` (WebUI v2, login do admin permanente), `/account`, `/.well-known/jmap` e o XML de
      autoconfig dos 3 domínios (só IMAP 993 e SMTP 465).
- [ ] Receção: Gmail → `leo@leoschlanger.com` e Gmail → uma conta da OQD chegam. A regra Sieve de
      redirecionamento continua a reencaminhar, e o spam e os relatórios não são reencaminhados.
- [ ] Envio pelo webmail e por um cliente IMAP para o Gmail. Em «Mostrar original»: SPF, DKIM e DMARC `pass`
      para `leoschlanger.com` e `olhaqueduas.com`. O mail-tester.com dá pelo menos a mesma nota de antes.
- [ ] DKIM: `configure.sh dns <dom>` dos 3 domínios igual à referência; `dig` dos seletores bate com as
      chaves.
- [ ] IMAP: os clientes (telemóvel, Thunderbird) não voltam a descarregar tudo (UIDVALIDITY igual) e as
      contagens batem com a referência.
- [ ] Fila: o correio da janela foi entregue e `cli query QueuedMessage` fica vazia.
- [ ] IP do cliente: um login falhado a partir de fora aparece com o IP real nos logs (não 172.30.50.1).
- [ ] Os dois webmails fazem login depois do «Auto-configure OAuth».
- [ ] No dia seguinte: `logs/sync-certs.log` e `logs/backup.log` sem erros, relatórios TLS-RPT/DMARC
      enviados (`noreply-tls@…` nos logs) e os redirecionamentos para o Gmail sem `421 4.7.28`.

## 8. Trabalho para o developer (antes da janela, num ramo)

- `docker-compose.yml`: imagem `stalwartlabs/stalwart:<alvo>`, volumes novos `stalwart-v1-etc` (em
  `/etc/stalwart`) e `stalwart-v1-data` (em `/var/lib/stalwart-v1`), serviço `migrate` com
  `profiles: [migrate]` (imagem do migrate fixada, `ulimits nofile 65536`, volumes 0.16 `:ro` + v1 +
  `migrate-state`). Os volumes 0.16 continuam declarados, sem uso, até serem retirados.
- `stalwart/plan.ndjson` → `plan-v1.ndjson` com `convert_plan.py` (`prepare`, `convert`, `validate`) e
  `apply --dry-run` no ensaio.
- `configure.sh`: o pin da CLI segundo o resultado do ensaio e `Bootstrap.defaultHostname`.
- `backup.sh`/`restore.sh` não precisam de mudanças (encontram os volumes pelo label do projeto), mas o
  backup passa a levar os volumes 0.16 e v1 até a 0.16 sair.
- README (tabela «Atualizar»), CLAUDE.md local (achado datado) e este documento passado a «executado».

## 9. Rollback

- **A, antes do ponto de não retorno** (o v1 ainda não recebeu nem escreveu nada): `docker compose stop
  stalwart`, voltar o compose ao `v0.16.27` com os volumes antigos (intactos: o migrate só os leu) e correr
  `docker compose up -d stalwart`. Leva ~5 min. Se a imagem não estiver no host: `docker load` do tarball
  da secção 4.
- **B, depois de o v1 servir:** deixar esvaziar a fila do v1, parar o v1 e correr `stalwart-migrate rollback
  --source <v1> --target <store 0.16 novo e vazio> --state <estado novo> --forward-state <estado da
  migração>`. Depois arrancar a 0.16.27 sobre o store novo. A fila, as tarefas e a telemetria ficam no v1,
  e uma submissão pendente volta como «enviada». Ensaiado no passo 7 da secção 5. Leva ~30 min.
- **Último recurso:** `restore.sh` do snapshot `pre-stalwart-v1`, com perda do correio recebido depois da
  migração.

## 10. Riscos principais

1. **IP do cliente atrás do Traefik (#3).** Com a resposta errada no `prepare`, o auto-ban pode bloquear o
   gateway e cortar o webmail a todos. Mitigação: o teste do passo 5 e o critério da secção 7.
2. **Ferramenta e linha 1.x novas.** Há correções pendentes no migrate (1.0.9), a 1.2.0 tem um dia e não
   está documentado se um store migrado abre diretamente na 1.1+. Mitigação: esperar e fazer o portão de
   versão no ensaio.
3. **Duplicação de entregas no ensaio.** Mitigação: rede interna e `--exclude queue,tasks`.
4. **Configuração como código parte:** o `plan.ndjson` 0.16 e possivelmente a `cli:1.0.14`. Mitigação:
   conversão e testes antes da janela.
5. **Novo login para toda a gente** (tokens OAuth não migram) e o «Auto-configure OAuth» nos dois Bulwark.
6. **Mudanças de spam e relatórios** (#10, #11). Mitigação: vigiar na 1.ª semana.

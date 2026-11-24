# Leo Mail: servidor de email próprio

Stalwart + Bulwark em Docker, para domínios personalizados sem depender de planos pagos.

| Peça | O que é | Onde |
|---|---|---|
| [Stalwart](https://stalw.art) v0.16.27 | Servidor de email (SMTP, IMAP, JMAP, antispam, DKIM/SPF/DMARC, Sieve) | `https://mail.leoschlanger.com/admin` |
| [Bulwark](https://bulwarkmail.org) 1.21.3 | Webmail moderno (estilo Gmail, tema escuro, calendário, contatos, PWA) | `https://webmail.leoschlanger.com` |
| Traefik (já existente no host) | HTTPS e certificados Let's Encrypt | configurado via `.env` |

```
Internet ──25/465/587/993──▶ stalwart (container)          ◀── certs/ (exportado do Traefik)
Internet ──443──▶ Traefik ──▶ 127.0.0.1:8480 stalwart (admin, JMAP)
                          └─▶ 127.0.0.1:8481 bulwark  (webmail) ──JMAP──▶ mail.leoschlanger.com
```

## Instalação do zero

Pré-requisito: um Traefik já rodando no host, com o *file provider* e um resolver Let's Encrypt.

1. DNS da seção 1 de [DNS.md](DNS.md) + PTR no painel da hospedagem.
2. No VPS:
   ```bash
   git clone <este-repo> /opt/mail
   /opt/mail/scripts/install.sh              # 1ª vez: cria o .env com segredos e para
   nano /opt/mail/.env                       # preencher TRAEFIK_DYNAMIC_DIR, TRAEFIK_ACME_JSON, TRAEFIK_CERT_RESOLVER
   /opt/mail/scripts/install.sh              # rota no Traefik, certificado, containers, cron
   /opt/mail/scripts/configure.sh bootstrap  # hostname, domínio e chaves DKIM
   /opt/mail/scripts/configure.sh apply      # listener HTTP, certificado, CORS
   /opt/mail/scripts/configure.sh user leo   # cria leo@leoschlanger.com
   /opt/mail/scripts/configure.sh dns        # registros MX/SPF/DKIM/DMARC para publicar
   ```
3. DNS da seção 2 de [DNS.md](DNS.md).
4. Teste em https://www.mail-tester.com.

**Restaurar um backup** em servidor novo: passos 1 e 2 até `install.sh`, depois
`/opt/mail/scripts/restore.sh <arquivo.tar.gz>` (os arquivos `env-*` do backup têm o `.env` original).

## Uso no dia a dia

### Ler emails
- **Navegador:** `https://webmail.leoschlanger.com`. No celular, "Adicionar à tela inicial" instala como app.
- **Apps (Thunderbird, Apple Mail, K-9/FairEmail, Outlook):** só email e senha; a configuração é automática (autoconfig).
  Manual: IMAP `mail.leoschlanger.com:993` SSL/TLS · SMTP `mail.leoschlanger.com:465` SSL/TLS (a porta 587 não é usada).
- **Dentro do Gmail:** use o redirecionamento (abaixo) para receber. Para responder com o seu domínio ainda
  existe Gmail → Configurações → *Contas e importação* → "Enviar email como" → SMTP `mail.leoschlanger.com`,
  porta 465, SSL, mas o Google remove o "Enviar como" de contas de terceiros, o Gmailify e a busca por POP
  ("Verificar o email de outras contas") em **janeiro de 2027**
  ([anúncio do Google](https://support.google.com/mail/answer/17101213)). Depois disso: responda pelo webmail ou
  por um app com IMAP/SMTP (o app Gmail no celular continua a aceitar contas IMAP). Não configure busca por POP.

### Redirecionar para o Gmail (ou qualquer outro provedor)
Webmail → Configurações → **Filtros** → nova regra "Todas as mensagens" → *Redirecionar para* `voce@gmail.com`
(marque "manter uma cópia" se quiser guardar aqui também). É um script Sieve que roda no servidor, então funciona
mesmo com o webmail fechado.

A regra de redirecionamento para o Gmail **não reencaminha** (condições "não contém" na mesma regra):
- spam: cabeçalho `X-Spam-Status` contém `Yes` (o veredito do antispam do Stalwart; o spam fica no Lixo eletrônico daqui);
- relatórios DMARC e TLS-RPT: assunto contém `Report domain:` ou remetente `noreply-dmarc-support@google.com`.

Porquê: em out–nov/2026 o Gmail recusou 53 cópias reencaminhadas com `421 4.7.28` ("unusual rate of
unsolicited mail"); quase todas eram relatórios DMARC do próprio Google enviados ao `postmaster@`. Reencaminhar
spam e relatórios automáticos baixa a reputação do servidor no Gmail e atrasa o correio que interessa.
Os relatórios continuam na caixa daqui (webmail).

Mais observações:
- Num redirecionamento o Stalwart envia com o remetente do envelope = a própria conta (ex.: `leo@leoschlanger.com`),
  por isso o SPF passa no Gmail. Não há SRS: o Stalwart não o implementa (o autor considera-o obsoleto, issue
  [#2143](https://github.com/stalwartlabs/stalwart/issues/2143)). O DMARC do remetente original depende do
  DKIM dele, que sobrevive ao redirecionamento; mensagens sem DKIM podem ir para o spam do Gmail.
- Para receber *qualquer* endereço do domínio (catch-all), veja no admin → Domains → `catchAllAddress`.

### Contas, aliases e domínios
Admin `https://mail.leoschlanger.com/admin` (usuário e senha do admin permanente):
- *Management → Directory → Accounts*: criar contas e aliases (ex.: `contato@`, `financeiro@` → `leo@`).
- *Management → Domains*: novos domínios (veja [DNS.md](DNS.md)).
- Cada usuário também gerencia a própria conta em `https://mail.leoschlanger.com/account` (senha, 2FA, senhas de app).

## Operação

| Tarefa | Comando |
|---|---|
| Logs | `cd /opt/mail && docker compose logs -f stalwart`. O log do container perde-se quando o container é recriado: cópia diária (00:15 UTC, dia anterior) em `/opt/mail/logs/stalwart/stalwart-AAAA-MM-DD.log.gz`, 30 dias (`scripts/export-logs.sh [AAAA-MM-DD]`). Antes de recriar o container, correr `export-logs.sh $(date -u +%F)` para guardar o dia em curso |
| Atualizar | Trocar a versão em `docker-compose.yml` (fixa: `v0.16.x` e `1.21.x`), depois `docker compose pull && docker compose up -d`. **Não** passar o Stalwart para 1.x com um simples pull: exige o `stalwart-migrate` |
| Fila de envio | `configure.sh cli query QueuedMessage` |
| Backup manual | `/opt/mail/scripts/backup.sh` (automático todo dia 04:45, guarda 7 dias em `/opt/mail/backups`; inclui todos os volumes `mail_*`, Stalwart e os dois webmails) |
| Certificado | `/opt/mail/scripts/sync-certs.py` (automático todo dia 03:17; reinicia o Stalwart se mudou) |
| `configure.sh` | Usa o admin permanente (`admin@leoschlanger.com`); pede a senha, ou `STALWART_ADMIN_PASSWORD=… configure.sh …` |
| Travado fora do admin | O admin de emergência (`STALWART_RECOVERY_ADMIN`) fica **comentado** no `.env` desde 21/11/2026. Para usar: descomentar (ou pôr `admin:<senha-nova>`), `STALWART_RECOVERY_MODE=1 docker compose up -d stalwart`, entrar via túnel SSH em `http://localhost:8480/admin`, e no fim comentar de novo e `docker compose up -d stalwart` |

Segredos ficam **só** no `/opt/mail/.env` do servidor (e no backup). Não vão para o git.

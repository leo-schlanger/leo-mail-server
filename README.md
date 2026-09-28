# Leo Mail: servidor de email próprio

Stalwart + Bulwark em Docker, para domínios personalizados sem depender de planos pagos.

| Peça | O que é | Onde |
|---|---|---|
| [Stalwart](https://stalw.art) v0.16 | Servidor de email (SMTP, IMAP, JMAP, antispam, DKIM/SPF/DMARC, Sieve) | `https://mail.leoschlanger.com/admin` |
| [Bulwark](https://bulwarkmail.org) 1.11 | Webmail moderno (estilo Gmail, tema escuro, calendário, contatos, PWA) | `https://webmail.leoschlanger.com` |
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
  Manual: IMAP `mail.leoschlanger.com:993` SSL/TLS · SMTP `mail.leoschlanger.com:465` SSL/TLS.
- **Dentro do Gmail:** use o redirecionamento (abaixo) para receber e, para responder com o seu domínio,
  Gmail → Configurações → *Contas e importação* → "Enviar email como" → SMTP `mail.leoschlanger.com`, porta 465, SSL.

### Redirecionar para o Gmail (ou qualquer outro provedor)
Webmail → Configurações → **Filtros** → nova regra "Todas as mensagens" → *Redirecionar para* `voce@gmail.com`
(marque "manter uma cópia" se quiser guardar aqui também). É um script Sieve que roda no servidor, então funciona
mesmo com o webmail fechado.

Mais observações:
- Mensagens com DKIM válido (quase todas as legítimas) chegam normais no Gmail. As que dependem só de SPF
  podem ir para o spam, porque o Stalwart não reescreve o remetente (SRS).
- Para receber *qualquer* endereço do domínio (catch-all), veja no admin → Domains → `catchAllAddress`.

### Contas, aliases e domínios
Admin `https://mail.leoschlanger.com/admin` (usuário e senha do admin permanente):
- *Management → Directory → Accounts*: criar contas e aliases (ex.: `contato@`, `financeiro@` → `leo@`).
- *Management → Domains*: novos domínios (veja [DNS.md](DNS.md)).
- Cada usuário também gerencia a própria conta em `https://mail.leoschlanger.com/account` (senha, 2FA, senhas de app).

## Operação

| Tarefa | Comando |
|---|---|
| Logs | `cd /opt/mail && docker compose logs -f stalwart` |
| Atualizar | `cd /opt/mail && docker compose pull && docker compose up -d` |
| Fila de envio | `configure.sh cli query QueuedMessage` |
| Backup manual | `/opt/mail/scripts/backup.sh` (automático todo dia 04:45, guarda 7 dias em `/opt/mail/backups`) |
| Certificado | `/opt/mail/scripts/sync-certs.py` (automático todo dia 03:17; reinicia o Stalwart se mudou) |
| Travado fora do admin | `STALWART_RECOVERY_MODE=1 docker compose up -d stalwart` → entre com o `STALWART_RECOVERY_ADMIN` do `.env` via túnel SSH em `http://localhost:8480/admin` |

Segredos ficam **só** no `/opt/mail/.env` do servidor (e no backup). Não vão para o git.

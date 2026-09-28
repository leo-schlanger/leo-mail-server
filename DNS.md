# DNS do email — leoschlanger.com

O DNS do domínio está no **Google Cloud DNS** (nameservers `ns-cloud-d*.googledomains.com`).
IP do VPS: `72.62.235.122`.

## 1. Antes da instalação

| Tipo | Nome | Valor | TTL |
|---|---|---|---|
| A | `mail.leoschlanger.com.` | `72.62.235.122` | 300 |
| A | `webmail.leoschlanger.com.` | `72.62.235.122` | 300 |
| CNAME | `autoconfig.leoschlanger.com.` | `mail.leoschlanger.com.` | 300 |
| CNAME | `autodiscover.leoschlanger.com.` | `mail.leoschlanger.com.` | 300 |

> Não crie registro AAAA (IPv6) para `mail`: o envio sai só por IPv4.

**DNS reverso (PTR):** no hPanel da Hostinger → VPS → *Configurações* → *IP reverso* →
`72.62.235.122` → `mail.leoschlanger.com`. Sem isso, Gmail e Outlook rejeitam ou mandam para spam.

## 2. Depois da instalação (receber e autenticar)

| Tipo | Nome | Valor |
|---|---|---|
| MX | `leoschlanger.com.` | `10 mail.leoschlanger.com.` |
| TXT | `leoschlanger.com.` | `"v=spf1 mx -all"` |
| TXT | `mail.leoschlanger.com.` | `"v=spf1 a -all"` |
| TXT | `_dmarc.leoschlanger.com.` | `"v=DMARC1; p=none; rua=mailto:postmaster@leoschlanger.com; adkim=s; aspf=s"` |
| TXT | `<seletor>._domainkey.leoschlanger.com.` | chave DKIM gerada pelo Stalwart |

As chaves DKIM (e registros opcionais como SRV, MTA-STS e TLS-RPT) saem prontas com:

```bash
/opt/mail/scripts/configure.sh dns
```

Depois de 2 a 4 semanas sem problemas nos relatórios DMARC, troque `p=none` por `p=quarantine`.

## Domínio adicional (ex.: outro-dominio.com)

1. Admin do Stalwart (`https://mail.leoschlanger.com/admin`) → *Management → Domains* → adicionar.
2. No DNS **do novo domínio**: `MX 10 mail.leoschlanger.com.`, `TXT "v=spf1 a:mail.leoschlanger.com -all"`,
   o DKIM mostrado em *View DNS Zone file* e um `_dmarc`.
3. Não precisa de novo certificado: todos os domínios usam `mail.leoschlanger.com` como servidor.

## Checagens

```bash
dig +short MX leoschlanger.com
dig +short TXT leoschlanger.com
dig +short -x 72.62.235.122          # tem que responder mail.leoschlanger.com.
```

Teste completo de entregabilidade: mande um email para o endereço exibido em https://www.mail-tester.com (a meta é 10/10).

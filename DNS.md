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

As chaves DKIM (uma ed25519 e uma RSA) e os registros opcionais saem prontos com:

```bash
/opt/mail/scripts/configure.sh dns
```

Do que esse comando lista, publique também (opcional, ajuda apps a se configurarem sozinhos):
`_imaps._tcp` e `_submissions._tcp` (SRV) e `_smtp._tls` (TLS-RPT).

> ⚠️ **Não publique os registros TLSA.** Eles fixam a chave do certificado, e o Traefik gera uma
> chave nova a cada renovação (~60 dias). Com TLSA publicado, servidores com DANE deixariam de
> entregar email para você depois da renovação.
>
> MTA-STS (`mta-sts`, `_mta-sts`) e `ua-auto-config` ficam de fora por enquanto: o MTA-STS exige
> certificado próprio para `mta-sts.leoschlanger.com`.

Depois de 2 a 4 semanas sem problemas nos relatórios DMARC, troque `p=none` por `p=quarantine`.

## Chaves DKIM não rodam sozinhas

Como o DNS é manual, a rotação automática de DKIM está desligada (`rotateAfter` = 10 anos, em
`stalwart/plan.ndjson`). Se um dia quiser trocar as chaves: gere novas no admin, publique os novos
seletores no DNS e só então remova os antigos.

## Domínio adicional (ex.: outro-dominio.com)

1. Adicione o domínio em `stalwart/plan.ndjson` e rode `configure.sh cli apply --file plan.ndjson`
   (ou pelo admin: *Management → Domains*). Contas: `configure.sh user NOME outro-dominio.com`.
2. No DNS **do novo domínio**: `MX 10 mail.leoschlanger.com.`, `TXT "v=spf1 a:mail.leoschlanger.com -all"`,
   os DKIM de `configure.sh dns outro-dominio.com` e um `_dmarc`.
3. Não precisa de novo certificado: todos os domínios usam `mail.leoschlanger.com` como servidor.

## Checagens

```bash
dig +short MX leoschlanger.com
dig +short TXT leoschlanger.com
dig +short -x 72.62.235.122          # tem que responder mail.leoschlanger.com.
```

Teste completo de entregabilidade: mande um email para o endereço exibido em https://www.mail-tester.com (a meta é 10/10).

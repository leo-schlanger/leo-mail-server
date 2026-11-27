# Treino do classificador de spam (Stalwart 1.2) — plano

Estado: **proposta, à espera do sim do Leo**. Nada foi treinado, movido nem apagado.

## Situação a 2026-11-27 (só leitura)

- Stalwart `v1.2.0` em produção (imagem `stalwartlabs/stalwart:v1.2.0`, `stalwart --version` = 1.2.0).
- `SpamClassifier`: modelo `FtrlFh`, `minHamSamples=100`, `minSpamSamples=100`, `trainInterval=12h`,
  `holdSamplesFor=180 dias`, `reservoirCapacity=1024`, auto-aprendizagem ligada (contactos, respostas,
  ≥ 2 hits RBL, spam traps).
- Amostras de treino (`SpamTrainingSample`): **1 ham, 0 spam**. Por isso o log diz
  `spam.model-not-ready … details = [1, 0], limit = [100, 100]` 12 h depois de cada arranque e
  `spam.model-not-found` a cada arranque (o `backup.sh` reinicia o Stalwart às 04:45 UTC).
- Correio existente nas 9 contas (Mailbox/get, totais): Inbox 121 (102 numa só conta), Junk 1,
  Enviados 2, Lixo 2, outras pastas 0.
- Volume recente: ~2 mensagens recebidas por dia, 0 classificadas como spam.

**O correio que já está nas pastas não conta.** O limite de 100 + 100 é sobre `SpamTrainingSample`,
não sobre pastas. Uma amostra nasce quando alguém move uma mensagem para Junk (spam) ou para fora de
Junk (ham), marca junk / not junk por IMAP ou JMAP, ou pela auto-aprendizagem. Também se pode criar
pela API. Mensagens que já estavam na Inbox não criam nada (documentação do Stalwart,
`spamfilter/classifier/training`).

**Conclusão: não chega para treinar.** Há ham suficiente em potência (121 na Inbox, mas cada mensagem
teria de ser confirmada como legítima e virar amostra). Spam não há: 1 mensagem em Junk em todo o
servidor. Ao ritmo atual, o spam orgânico não chega às 100 amostras em tempo útil.

## Opções (escolha do Leo)

| | Spam (faltam 100) | Ham (faltam 99) | Custo / risco |
|---|---|---|---|
| A. Orgânico | marcar como spam no webmail o que chegar | «não é spam» / mover de Junk | zero; meses ou nunca |
| B. Correio próprio | ~100 spams recentes exportados do Gmail (pasta Spam) em `.eml` | mensagens legítimas da Inbox confirmadas pelo Leo | 1 sessão; spam real e atual |
| C. Corpus público | SpamAssassin public corpus (spam antigo, 2002–2005) | como em B | rápido; spam antigo, modelo pior |
| D. Baixar `minSpamSamples` | — | — | não recomendado: modelo com poucos exemplos marca correio bom como spam |

Recomendação: **B**. Usa spam atual e é o que o filtro vai ver.

## Procedimento (B ou C) — não ensaiado

Antes: confirmar que o backup das 04:45 desse dia correu (`/opt/mail/logs/backup.log`, «backup done»).

1. Spam: enviar cada `.eml` como blob, por JMAP `POST /jmap/upload/<accountId>/` (admin, no host,
   `127.0.0.1:8480`), e criar a amostra global:
   `configure.sh cli create SpamTrainingSample --field blobId=<blob> --field isSpam=true`.
2. Ham: para cada mensagem aprovada, ler o `blobId` (`Email/get`) e criar
   `SpamTrainingSample` com `blobId`, `isSpam=false` e `accountId` da conta. A mensagem não é
   movida nem alterada.
3. Contar: `configure.sh cli query SpamTrainingSample --fields id,isSpam --json` → ≥ 100 de cada.
4. Treinar já, sem esperar as 12 h:
   `configure.sh cli create Task/SpamFilterMaintenance --field maintenanceType=train`.
5. Verificar: `docker logs stalwart | grep -E 'spam.train-(started|completed)|spam.model-loaded'`. Depois
   o check diário do correio (n8n M1) envia «RECUPERADO» para `mail:spam-model`.

Desfazer: `Task/SpamFilterMaintenance` com `maintenanceType=reset` (apaga o modelo), e apagar as
amostras criadas (`cli delete SpamTrainingSample --ids …`). O correio não é tocado em nenhum passo.

Pontos por confirmar no ensaio:
- se o admin pode criar amostras com blobs de outra conta;
- a sintaxe exata da variante `Task/SpamFilterMaintenance` no CLI 1.0.14 (é a mesma forma de
  `Account/User` usada no `configure.sh`).

## Aviso enquanto não houver modelo

O check M1 do n8n (repo `n8n-workflows`) verifica todos os dias. Enquanto não houver modelo, avisa
**1 vez por semana**, e o aviso de recuperação sai no próprio dia em que o modelo aparecer
(`spam.model-loaded` ou `spam.train-completed` no log).

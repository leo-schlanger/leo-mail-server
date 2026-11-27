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
- Correio existente: poucas contas e volume baixo. A Inbox tem ham que chegaria em potência;
  em Junk quase nada; nada recebido foi classificado como spam.

**O correio que já está nas pastas não conta.** O limite de 100 + 100 é sobre `SpamTrainingSample`,
não sobre pastas. Uma amostra nasce quando alguém move uma mensagem para Junk (spam) ou para fora de
Junk (ham), marca junk / not junk por IMAP ou JMAP, ou pela auto-aprendizagem. Também se pode criar
pela API. Mensagens que já estavam na Inbox não criam nada (documentação do Stalwart,
`spamfilter/classifier/training`).

**Conclusão: não chega para treinar.** Há ham suficiente em potência na Inbox, mas cada mensagem
teria de ser confirmada como legítima e virar amostra. Spam quase não há. Ao ritmo atual, o spam
orgânico não chega às 100 amostras em tempo útil.

## Opções (escolha do Leo)

| | Spam (faltam 100) | Ham (faltam 99) | Custo / risco |
|---|---|---|---|
| A. Orgânico | marcar como spam no webmail o que chegar | «não é spam» / mover de Junk | zero; meses ou nunca |
| B. Correio próprio | ~100 spams recentes exportados do Gmail (pasta Spam) em `.eml` | mensagens legítimas da Inbox confirmadas pelo Leo | 1 sessão; spam real e atual |
| C. Corpus público | SpamAssassin public corpus (spam antigo, 2002–2005) | como em B | rápido; spam antigo, modelo pior |
| D. Baixar `minSpamSamples` | — | — | não recomendado: modelo com poucos exemplos marca correio bom como spam |

Recomendação: **B**. Usa spam atual e é o que o filtro vai ver.

## Procedimento (B ou C) — não ensaiado

Antes:
- confirmar que o backup das 04:45 desse dia correu (`/opt/mail/logs/backup.log`, «backup done»);
- guardar as amostras que já existem:
  `configure.sh cli query SpamTrainingSample --fields id,isSpam --json > samples-antes.ndjson`;
- confirmar que os eventos do treino chegam ao log: `configure.sh cli query Tracer --json` deve dar
  `"level":"info"` sem lista `events` a filtrar. Na 1.2.0, `spam.model-loaded`, `spam.train-started`
  e `spam.train-completed` são de nível info (`crates/trc/src/event/enums_impl.rs`, `fn level`).

`configure.sh cli` corre o CLI num contentor `stalwartlabs/cli:1.0.14`; o Docker faz pull dessa
imagem se não estiver no host.

1. Spam: enviar cada `.eml` como blob, por JMAP `POST /jmap/upload/<accountId>/` (admin, a partir
   do próprio host), e criar a amostra global:
   `configure.sh cli create SpamTrainingSample --field blobId=<blob> --field isSpam=true`.
2. Ham: para cada mensagem aprovada, ler o `blobId` (`Email/get`) e criar
   `SpamTrainingSample` com `blobId`, `isSpam=false` e `accountId` da conta. A mensagem não é
   movida nem alterada.
3. Contar e guardar: `configure.sh cli query SpamTrainingSample --fields id,isSpam --json > samples-depois.ndjson`
   → ≥ 100 de cada.
4. Treinar já, sem esperar as 12 h:
   `configure.sh cli create Task/SpamFilterMaintenance --field maintenanceType=train`.
5. Verificar: `docker logs stalwart | grep -E 'spam.train-(started|completed)|spam.model-loaded'`. Se
   nada aparecer: rever o nível do `Tracer` (passo «Antes»). Depois o check diário do correio deixa de
   avisar e envia um aviso de recuperação. Salvaguarda, caso os eventos não cheguem ao log: o
   `model-not-found` sai a cada arranque, por isso um arranque nas 24 h sem esse evento também conta
   como modelo presente.

Desfazer:
1. `Task/SpamFilterMaintenance` com `maintenanceType=reset` (apaga o modelo).
2. Apagar só as amostras novas: os ids que estão em `samples-depois.ndjson` e não estão em
   `samples-antes.ndjson` (`configure.sh cli delete SpamTrainingSample --ids <ids novos>`).

O treino não toca no correio. Mas o correio que o modelo já tiver posto em Junk fica lá depois do
reset: tem de ser revisto e movido à mão (e mover para fora de Junk cria amostras ham).

Pontos por confirmar no ensaio:
- se o admin pode criar amostras com blobs de outra conta;
- a sintaxe exata da variante `Task/SpamFilterMaintenance` no CLI 1.0.14 (é a mesma forma de
  `Account/User` usada no `configure.sh`);
- os valores `train` e `reset` de `maintenanceType`: o `describe TaskSpamFilterMaintenanceType` lista-os,
  mas o efeito de cada um não foi testado;
- os eventos `spam.model-loaded` e `spam.train-completed` ainda não foram vistos no log desta
  instalação (só no código e no binário).

## Aviso enquanto não houver modelo

O check diário do correio corre todos os dias. Enquanto não houver modelo, avisa **1 vez por
semana**, e o aviso de recuperação sai no próprio dia em que o modelo aparece (`spam.model-loaded` ou
`spam.train-completed` no log, ou um arranque sem `spam.model-not-found`).

# Stream do Bedo · Resumo das decisões de projeto

Trabalho final de Projeto de Banco de Dados (UFF, 2026/2), em PostgreSQL 17.
Este arquivo resume as decisões do grupo e **o porquê de cada uma**. Sempre que
possível, a justificativa parte de um dado do mundo real (com a fonte no fim do
arquivo) e de uma conta: quantos registros o cenário prevê e se eles cabem no
tipo escolhido.

- Cada decisão está explicada por extenso, com as alternativas avaliadas, as
  medições e as limitações, em
  [decisoes_detalhamento.md](decisoes_detalhamento.md). As seções dos dois
  arquivos seguem a mesma ordem de assuntos.
- As medições de desempenho estão em [benchmark.md](benchmark.md); a forma de
  executar e a ordem dos arquivos, no [README.md](README.md).

**Limites dos tipos usados nas contas** (o `IDENTITY` começa em 1 e não dá a
volta, então todo o intervalo positivo é utilizável):

| Tipo | Bytes | Maior valor | Em notação científica |
|---|---:|---:|---:|
| `SMALLINT` | 2 | 32.767 | 3,3 × 10^4 |
| `INTEGER` | 4 | 2.147.483.647 | 2,15 × 10^9 |
| `BIGINT` | 8 | 9.223.372.036.854.775.807 | 9,22 × 10^18 |
| `UUID` v4 | 16 | 122 bits aleatórios | 5,3 × 10^36 combinações |

## 1. Mapa: o que o enunciado exige e onde está atendido

| Exigência do enunciado | Como o grupo atendeu | Arquivo | Seção |
|---|---|---|---|
| Especificação 1: visões virtuais e materializadas | 2 virtuais (V1, V2) e 2 materializadas (V3, V4) | `views.sql` | 9 |
| Especificação 2: índices para melhorar buscas | 5 índices de apoio, escolhidos por predicado e medidos a frio | `views.sql`, fim do `functions.sql` | 11 |
| Especificação 3: triggers para a movimentação de dados | T1 a T11; tradeoff do T2 comparado com a recontagem periódica | `triggers.sql` | 8 |
| Especificação 4: rotinas para as consultas | 12 functions parametrizadas | `functions.sql` | 10 |
| "A base de dados não deve conter redundância" e "normalize" | Surrogates no lugar das chaves naturais propagadas; `Doacao` sem o `nick`; únicos atributos redundantes são os derivados exigidos pelo modelo, mantidos por trigger | `ddl.sql` | 3 |
| "Verificar a possibilidade do uso de identificador artificial" (comentário de `Video` no modelo) | `id_video UUID`, decidido pela conta de cardinalidade | `ddl.sql` | 4 e 5 |
| Item mandatório 1: 1.000 a 10.000 tuplas por tabela | ~8,7 milhões de registros; tabelas de referência no tamanho real (autorizado pelo professor) | `seed.sql` | 12 |
| Item mandatório 2: identificadores artificiais, `UNIQUE` e `NOT NULL` criteriosos | 3 surrogates com a chave natural em `UNIQUE NOT NULL`; `UNIQUE`, `NOT NULL` e `CHECK` pelas regras do minimundo | `ddl.sql` | 5 e 6 |
| Item mandatório 3: até 5 visões, cada uma justificada | 4 de 5; a V5 foi medida e descartada | `views.sql` | 9 |
| Item mandatório 4: até 5 índices, overhead de inserção, cada um justificado | 5 de 5, com o ganho e o custo de `INSERT` de cada um | `views.sql`, `functions.sql` | 11 |
| Item mandatório 5: triggers para a consistência (todas as necessárias) | 11 regras derivadas do minimundo, cada uma com a origem | `triggers.sql` | 8 |
| Item mandatório 6: functions parametrizadas para as consultas 1 a 12 | 12 functions, com filtro opcional `DEFAULT NULL` ou `k`; `tests.sql` chama cada uma em vários cenários | `functions.sql`, `tests.sql` | 10 |
| Consulta 12 (desafio/ponto extra) | Interpretação decidida antes do código e validada contra contagem independente | `functions.sql` | 10 |
| `README.md` com o passo a passo | `make setup` e `make tests`, ou os comandos `psql` um a um | `README.md` | — |

## 2. Pontos levantados pelo professor e como foram resolvidos

| O que o professor levantou | O que o grupo decidiu | Seção |
|---|---|---|
| Não fugir do modelo relacional: não criar nem excluir coluna, não tirar atributo derivado | Só chaves foram remodeladas. A coluna `Inscricao.data_inscricao`, de uma versão anterior, saiu. `qtd_users` e `qtd_visualizacoes` ficaram | 3 |
| `id_canal` com a identidade (`nome`, `nro_plataforma`) em `UNIQUE`, e essa chave se propaga | Feito: `id_canal BIGINT` e `UNIQUE (nome, nro_plataforma)` | 5 |
| A chave de `Patrocinio` passa a ser número da empresa e `id_canal` | Feito: `PRIMARY KEY (nro_empresa, id_canal)`; o mesmo em `NivelCanal` e `Inscricao` | 5 |
| Em `Video`, dá para manter `id_canal` + id do vídeo, ou só um id do vídeo, conforme a quantidade de vídeos | Só `id_video`. A composta foi avaliada e descartada (tabela de alternativas) | 5 |
| A tabela de vídeos cresce exponencialmente; a surrogate não gera redundância | `id_canal` aparece só em `Video`, não em `Comentario` nem em `Doacao` | 5 |
| O comentário não deve ter uma chave própria; fica identificado pelo id do vídeo | `Comentario` foi tratado como **entidade fraca** de `Video`: só existe ligado a um vídeo e é identificado pelo vídeo mais um número sequencial que recomeça em cada vídeo ("número sequencial que depende do vídeo", no minimundo). Por isso a chave é `PRIMARY KEY (id_video, seq)`. Um `id_comentario` próprio foi medido e descartado: o par `(id_video, seq)` continuaria precisando ser único, então a tabela teria dois índices em vez de um, ficando 16% maior e 19% mais lenta no `INSERT` | 5 |
| Trazer argumentos de cardinalidade: tipo de vídeo, vídeo a cada 10 min, short a cada 10 s em 60 plataformas | As três contas estão feitas com dados reais | 4 |
| O 1.000 a 10.000 é só referência; não espera 10 mil países | Países, moedas e plataformas no tamanho real | 12 |
| Povoar o máximo, com centenas de milhares de tuplas e distribuição desbalanceada; mais visualizações levam a mais comentários | 8,7 milhões de registros; popularidade lognormal que comanda visualizações, vídeos, comentários e receitas | 12 |
| Por que `Comentario` referencia `nick_usuario` e não um `id_usuario`? | `id_usuario BIGINT`, com `nick` em `UNIQUE NOT NULL` | 5 |
| Olhar a similaridade dos predicados e a distribuição; se o filtro devolve quase tudo ("todos americanos"), o índice não ajuda | Inventário de predicados com `pg_stats`; predicados concentrados não foram indexados | 11 |
| O tipo do índice segue o predicado; tipicamente secundários sobre parte da chave; eventualmente hash | B-tree e hash medidos nos predicados de igualdade; ficou o B-tree | 11 |
| Deixar as consultas o melhor possível antes dos índices | Reescrita medida antes da escolha dos índices | 10 |
| `EXPLAIN ANALYZE` antes e depois, cuidando do cache; está em Docker | Protocolo a frio: reinício do Postgres e `drop_caches` antes de cada medida | 13 |
| Um bloco "cabe coisa para caramba"; com poucos dados o índice não faz diferença | Conta do bloco de 8 KB com os tamanhos reais | 11 e 12 |
| Entrega: DDL, dados reproduzíveis, consultas; triggers em arquivo separado, para não travar a inserção | Triggers por último; o seed obedece às regras e calcula os derivados | 8 e 14 |
| Decisões num documento curto; comentar bem o código | Este resumo; o detalhamento em `decisoes_detalhamento.md`; cada bloco do código diz o quê, por quê e os cuidados | — |
| Converter pela moeda do país do usuário é decisão aceitável; registrar | Doação convertida pela moeda do país de residência de quem comentou | 7 |
| Patrocínio sempre em dólar, porque vem de contrato externo | `Patrocinio.valor` em USD, sem conversão | 7 |
| Doação: converter ao gravar (valor histórico) ou na consulta (valor corrigido); as duas estão certas; para escolher patrocínio, o valor corrigido diz mais | Doação: histórico. Membros: corrigido. O motivo de cada um está na seção 7 | 7 |
| `qtd_visualizacoes` é a soma bruta das visualizações dos vídeos; não estoura com um tipo grande; manter por trigger | `BIGINT`, mantido pelo T1; a conta com o canal mais visto do mundo está na seção 4 | 4 e 8 |
| O mesmo vale para `qtd_users` | `BIGINT`, mantido pelo T2 por comando; o custo de atualizar a plataforma a cada conta nova foi comparado com a recontagem periódica | 4 e 8.1 |

## 3. Regra do trabalho e normalização

**O modelo relacional dado é otimizado, não alterado:**
- **pode:** remodelar chaves (inclusive com surrogate), mudar tipos, criar
  constraints, índices, views, triggers e functions;
- **não pode:** criar tabelas, mudar relacionamentos, criar colunas comuns ou
  remover atributos derivados.

As únicas colunas novas são as chaves artificiais (`id_usuario`, `id_canal`,
`id_video`) e as FKs que apontam para elas. Elas **substituem** colunas de chave
natural que se propagavam; não somam informação.

**Como cada decisão reduz redundância:**

| Situação no modelo dado | Problema | Decisão | Efeito |
|---|---|---|---|
| `nome_canal` + `nro_plataforma` repetidos em 11 tabelas | O texto do nome do canal se repete em cada vídeo, comentário e doação; renomear o canal exigiria atualizar todas as linhas | `id_canal` (8 bytes) | O nome fica guardado uma vez só, em `Canal` |
| `titulo` + `dataH` do vídeo repetidos em 7 tabelas | Chave de ~53 bytes repetida em 5 milhões de comentários | `id_video` (16 bytes) | O índice da PK de `Comentario` caiu 76% (seção 5) |
| `nick` como chave em 6 tabelas | O nick pode mudar; trocar um nick exigiria atualizar milhões de comentários | `id_usuario` (8 bytes) | O nick fica guardado uma vez só, em `Usuario` |
| `Doacao` com `nick_usuario` na chave | O autor já é determinado pelo comentário: `(id_video, seq) → id_usuario`. Com o `nick`, a chave deixa de ser mínima (é superchave) e o autor fica gravado duas vezes, podendo divergir | `Doacao` sem o autor; chave `(id_video, seq_comentario, seq_pg)` | Chave mínima, sem dependência redundante |
| `qtd_visualizacoes` e `qtd_users` | São redundância por definição (derivados), mas o modelo exige mantê-los | Não foram removidos; triggers T1 e T2 os mantêm sempre iguais à soma e à contagem | Redundância controlada, sem divergência |

## 4. Cenário de volumetria com dados reais

O professor deixou o grupo escolher o tipo de vídeo e o volume, desde que o
**mesmo cenário** justifique tudo: tipos de chave, seed e índices.

**Cenário escolhido:** catálogo de streaming de jogos com **vídeo longo e curto**
(lives, VODs, Shorts, TikTok, Reels), em dezenas de plataformas, com horizonte de
**10 anos** e dados coletados por crawlers, como o professor comentou.

### 4.1 Dados de referência

| Dado do mundo real | Valor | Fonte |
|---|---:|---|
| Pessoas usando a internet (2025) | 6,0 × 10^9 | ITU |
| Pico da população mundial (por volta de 2084) | 1,03 × 10^10 | ONU |
| Usuários do YouTube | 2,5 a 2,7 × 10^9 | Statista, Market.us |
| Usuários do TikTok | 1,6 a 1,9 × 10^9 | Statista |
| Canais no YouTube | ~1,14 × 10^8 | Vaizle, DemandSage |
| Streamers distintos por mês na Twitch (2025) | ~7 × 10^6 | TwitchTracker, via DemandSage |
| Vídeos públicos no YouTube (meados de 2024) | 1,48 × 10^10 | UMass Amherst (Zuckerman, McGrady) |
| Vídeos públicos no YouTube (2022) | 9 × 10^9 | idem |
| Vídeos enviados ao TikTok por dia | ~2,3 × 10^7 (16 mil por minuto) | Statista, via agregadores |
| Vídeo mais visto do YouTube ("Baby Shark Dance", fev. 2026) | 1,66 × 10^10 visualizações | Guinness World Records |
| Canal mais visto do YouTube (T-Series, abr. 2025) | 2,92 × 10^11 visualizações | Statista |
| Vídeo mais comentado do YouTube (BTS, "Dynamite") | ~1,58 × 10^7 comentários | Billboard e agregadores |
| Maior pico simultâneo numa live (ISRO, Chandrayaan-3, 2023) | ~8,06 × 10^6 espectadores | YouTube (CEO), imprensa |
| Empresas na base comercial da Dun & Bradstreet (inclui inativas) | ~6 × 10^8 registros | Dun & Bradstreet |

Os números de usuários e uploads vêm de fontes secundárias e variam entre si.
Servem como **ordem de grandeza**, que é o que decide o tipo.

### 4.2 Quantos vídeos o cenário prevê

O ritmo do YouTube sai da própria pesquisa da UMass: de 9 bilhões (2022) para
14,8 bilhões (meados de 2024), cerca de 5,8 bilhões em uns 2 anos, ou **~8
milhões de vídeos por dia**. O TikTok soma ~23 milhões por dia.

| Hipótese | Conta | Total | Cabe em `INTEGER`? | Fração do `BIGINT` |
|---|---|---:|---|---:|
| Hoje, só o YouTube | estoque medido | 1,48 × 10^10 | **não** (6,9 vezes o limite) | 1,6 × 10^-9 |
| Realista: YouTube + TikTok por 10 anos | (8 × 10^6 + 2,3 × 10^7) por dia × 3.650 dias + estoque | ~1,3 × 10^11 | não (60 vezes) | 1,4 × 10^-8 |
| Professor, vídeo longo: todo streamer filmando 24 h, um vídeo a cada 10 min | 7 × 10^6 streamers × 144 vídeos/dia × 3.650 dias | 3,7 × 10^12 | não (1.700 vezes) | 4 × 10^-7 |
| Professor, vídeo curto: um short a cada 10 s, replicado em 60 plataformas | 10^6 criadores × 8.640/dia × 60 × 3.650 dias | 1,9 × 10^15 | não | **0,02%** |

**Conclusões:**
1. **`INTEGER` não serve nem para o YouTube de hoje.** Qualquer cenário com
   vídeo exige pelo menos `BIGINT`.
2. **O `BIGINT` aguenta até o pior caso do professor.** Para estourá-lo no
   cenário de shorts, seriam precisos 9,22 × 10^18 / (8.640 × 60 × 3.650) ≈
   **4,9 bilhões de criadores**, cerca de 80% de toda a internet postando a cada
   10 segundos por 10 anos.
3. **O que o vídeo curto muda não é a capacidade, é a forma de gerar o id.**
   Com dezenas de plataformas coletadas por crawlers, o id precisa nascer no
   coletor, sem consultar uma sequence central. Isso leva ao UUID (seção 5).

### 4.3 Tipo de cada coluna numérica

| Coluna | Maior valor previsto | Conta contra o limite | Tipo | Por quê |
|---|---:|---|---|---|
| `Plataforma.nro` | ~10^3 | 28 plataformas reais no seed | `INTEGER` | `SMALLINT` também caberia; o `INTEGER` não custa espaço extra porque as colunas vizinhas `BIGINT` exigem alinhamento de 8 bytes, e dá folga para escalas sintéticas |
| `Empresa.nro` | ~6 × 10^8 | todas as empresas da base da D&B ocupariam 28% do `INTEGER` | `INTEGER` | Cabe com folga, e `Empresa` não entra nas tabelas grandes |
| `Usuario.id_usuario` | 6,0 × 10^9 hoje; 1,03 × 10^10 no pico populacional | a internet de hoje já é 2,8 vezes o `INTEGER`; o `BIGINT` só estoura com ~9 × 10^8 contas por pessoa | `BIGINT` | `INTEGER` estoura já hoje |
| `Canal.id_canal` | > 2,15 × 10^9 | o YouTube sozinho tem 1,14 × 10^8 canais (5% do `INTEGER`), mas no cenário todo criador de vídeo curto tem canal: só o TikTok tem 1,6 a 1,9 × 10^9 usuários (75% a 88% do `INTEGER`), e somam-se dezenas de plataformas | `BIGINT` | `INTEGER` estoura no cenário |
| `Video.id_video` | 1,9 × 10^15 no pior caso | 0,02% do `BIGINT` | `UUID` | Capacidade sobra; o UUID é pela geração distribuída (seção 5) |
| `Comentario.seq` (por vídeo) | ~1,6 × 10^7 | o recorde mundial ocupa 0,74% do `INTEGER`; o `SMALLINT` estouraria 480 vezes | `INTEGER` | A numeração é por vídeo, então só importa o máximo de um vídeo |
| `Doacao.seq_pg`, `seq_doacao`, `seq_plataforma` | ~10 | poucas doações por comentário | `INTEGER` | Com `UUID` (16) + `INTEGER` (4) + `INTEGER` (4), a chave fecha em 24 bytes, sem bytes perdidos no alinhamento; com `BIGINT` seriam 32 |
| `Video.visu_total` | 1,66 × 10^10 (Baby Shark) | 7,7 vezes o `INTEGER` | `BIGINT` | `INTEGER` já estoura com o vídeo mais visto de hoje |
| `Canal.qtd_visualizacoes` | 2,92 × 10^11 (T-Series) | 136 vezes o `INTEGER`; o `BIGINT` comporta 3 × 10^7 canais iguais à T-Series | `BIGINT` | É a soma bruta pedida pelo professor; "com um valor bem grande não estoura" |
| `Video.visu_simul` | 8,06 × 10^6 (recorde) | 0,38% do `INTEGER` | `BIGINT` | O `INTEGER` bastaria. Ficou `BIGINT` por ser o mesmo domínio de `visu_total`, com quem é comparado no `CHECK (visu_simul <= visu_total)` |
| `Plataforma.qtd_users` | 2,5 a 2,7 × 10^9 (YouTube) | acima do `INTEGER` | `BIGINT` | `INTEGER` estoura com o YouTube de hoje |
| `Patrocinio.valor`, `NivelCanal.valor`, `Doacao.valor` | contratos de dezenas de milhões de USD | `NUMERIC(14, 2)` vai até ~10^12 | `NUMERIC(14, 2)` | Decimal exato: dinheiro não pode ter erro de arredondamento de ponto flutuante |
| `Conversao.fator_conver` | entre ~10^-5 (libra libanesa, rial iraniano) e ~3 (dinar kuwaitiano) | 8 casas guardam a moeda mais fraca com 3 dígitos significativos | `NUMERIC(18, 8)` | Mesmo motivo: conversão exata |

**Colunas de texto com tamanho do mundo real:** `Conversao.moeda VARCHAR(3)`
(código ISO 4217), `BitCoin.TxID VARCHAR(64)` (hash SHA-256 em hexadecimal),
`CartaoCredito.nro VARCHAR(19)` (até 19 dígitos pela ISO/IEC 7812) e
`Pais.ddi VARCHAR(4)`: o DDI não é único no mundo real (Estados Unidos, Canadá e
o Caribe dividem o +1), então o seed usa o prefixo que distingue o país, como
1613 para o Canadá.

## 5. Chaves

### 5.1 Resumo

| Tabela | Chave | Identidade de negócio preservada | Por quê |
|---|---|---|---|
| Usuario | `id_usuario BIGINT IDENTITY` | `nick UNIQUE NOT NULL` | O nick pode mudar (as plataformas permitem renomear) e se repetia como chave em 6 tabelas. Comparar inteiro é mais barato que comparar texto com collation. Foi uma pergunta do professor |
| Canal | `id_canal BIGINT IDENTITY` | `UNIQUE (nome, nro_plataforma)` | A chave de texto se propagava para patrocínio, níveis, inscrições e vídeos. O nome é único **por plataforma**: o mesmo streamer pode ter canais de mesmo nome em plataformas diferentes |
| Patrocinio | `(nro_empresa, id_canal)` | — | A chave do canal propagada, como o professor indicou |
| NivelCanal, Inscricao | `(id_canal, nivel)` e `(id_canal, id_membro)` | — | Idem |
| Video | `id_video UUID` (`gen_random_uuid()`) | `UNIQUE (id_canal, titulo, dataH)`, com `titulo` e `dataH` `NOT NULL` | Seção 5.2 |
| Comentario | `(id_video, seq)` | — | Entidade fraca de `Video`: "número sequencial que depende do vídeo" (minimundo); seção 5.3 |
| Doacao e as 4 formas de pagamento | `(id_video, seq_comentario, seq_pg)` | — | Herda a chave do comentário, sem o autor (seção 3); 24 bytes sem desperdício de alinhamento |
| Conversao | `moeda` (código ISO de 3 letras) | `nome UNIQUE` | Chave natural curta, estável e já usada no mundo real; trocar por surrogate não reduziria nada |

### 5.2 Por que `Video` ganhou uma surrogate, e por que UUID

O professor deu duas opções: manter o canal na chave do vídeo ou criar só
um id do vídeo. O grupo comparou quatro:

| Alternativa | PK de `Video` | O que se repete em `Participa`, `Comentario`, `Doacao` e nas 4 formas | Problemas | Decisão |
|---|---|---|---|---|
| Chave natural do modelo | `(id_canal, titulo, dataH)` | ~53 bytes por linha (8 + título de ~36 caracteres + 8) | Em 5 milhões de comentários, só a chave repetida soma ~265 MB, mais o índice. O título é texto e pode ser editado | Não |
| Composta, como o professor sugeriu | `(id_canal, seq_video)` | 12 bytes, mas o `id_canal` passa a se repetir em todas as descendentes | O `id_canal` volta para as tabelas grandes, o que é a redundância que a surrogate evita. O `seq_video` exige `max + 1` com trava no canal, e um canal de shorts replicado publica sem parar. Mudar o vídeo de canal mudaria a PK e cascatearia em milhões de comentários | Não |
| `BIGINT IDENTITY` | `id_video` | 8 bytes | Capacidade suficiente (seção 4.2), mas depende de uma sequence central: dois crawlers não podem gerar ids sem consultar o banco, e juntar coletas exige renumerar | Avaliada; perdeu pela geração |
| **`UUID`** | `id_video` | 16 bytes | Custo de espaço e de inserção, medidos abaixo | **Sim** |

**Por que UUID:** no cenário, os vídeos chegam de dezenas de plataformas por
crawlers. Com UUID, cada coletor gera o id na hora, sem consultar o
banco, sem colisão prática e sem renumerar ao juntar coletas. A chance de
colisão de um UUID v4 com *n* ids é de cerca de *n*² / 2^123:
- no cenário realista (1,3 × 10^11 vídeos): ~1,5 × 10^-15;
- no pior caso do professor (1,9 × 10^15 vídeos): ~3,4 × 10^-7.

E ainda há o `UNIQUE (id_canal, titulo, dataH)` como segunda barreira. O índice
desse `UNIQUE` começa por `id_canal`, então ele também atende "vídeos de um
canal", a vantagem que a chave composta daria.

**Custo medido** (banco descartável, 1 milhão de linhas):

| Variante | `Video` (tabela + PK) | `INSERT` de 1 milhão | Índice da PK de `Comentario` (1 milhão) |
|---|---:|---:|---:|
| `BIGINT IDENTITY` | 64 MB | 2,8 s | 39 MB |
| UUID v4 (`gen_random_uuid()`) | 88 MB (+37%) | 6,2 s | 50 MB (+28%) |

O grupo aceita esse custo pela geração distribuída. As maiores tabelas pagam
pouco porque `Comentario` e `Doacao` não carregam `id_canal`: chegam ao canal
pelo vídeo.

**UUID v4 nativo, e não v7:** o v4 é aleatório, então cada vídeo novo entra num
ponto qualquer do B-tree da PK, e não no fim, como numa sequence. Isso gera mais
divisões de página. Um UUID v7, ordenado no tempo, evitaria esse custo, mas o
PostgreSQL 17 não tem `uuidv7()` nativo (só o 18). O grupo mediu as duas versões:
mesmo tamanho de tabela e índice, e `INSERT` cerca de 9% mais lento no v4.
Preferiu a função nativa a manter uma function própria. No seed, os sorteios que
dependem da ordem dos vídeos usam uma ordem fixa (data, canal e número do
vídeo), porque o `gen_random_uuid()` não obedece à semente.

### 5.3 Por que o comentário não tem id próprio

O professor confirmou que o comentário fica dependente do vídeo, e o minimundo
diz o mesmo: "um número sequencial que depende do vídeo". Por isso `Comentario`
foi tratado como **entidade fraca** de `Video`:
- **não existe sozinho:** todo comentário pertence a um vídeo, e a FK para
  `Video` faz parte da chave;
- **não tem identificador próprio:** é identificado pelo vídeo (a entidade
  forte) mais um discriminador, o `seq`, que conta 1, 2, 3… e recomeça em cada
  vídeo;
- **a chave é a do dono mais o discriminador:** `PRIMARY KEY (id_video, seq)`.

`Doacao` segue a mesma lógica um nível abaixo: é fraca em relação ao comentário,
com chave `(id_video, seq_comentario, seq_pg)`.

Para confirmar que dar um id próprio ao comentário não compensaria, o grupo
mediu quatro chaves com 1 milhão de comentários:

| Variante | PK | Tabela | Índices | Total | `INSERT` |
|---|---|---:|---:|---:|---:|
| A (modelo dado) | `(nome_canal, nro_plataforma, titulo, dataH, nick, seq)` | 195 MB | 156 MB | 352 MB | 11,2 s |
| B | `(id_video, nick, seq)` | 135 MB | 62 MB | 196 MB | 7,2 s |
| **C (escolhida)** | **`(id_video, seq)`** | 135 MB | **38 MB** | **173 MB** | **5,3 s** |
| D | `id_comentario` + `UNIQUE (id_video, seq)` | 142 MB | 59 MB | 201 MB | 6,3 s |

- **C reduz o índice em 76%** e o tempo de `INSERT` em 52% em relação ao modelo
  dado.
- **D perde para C:** como `seq` depende do vídeo, o par `(id_video, seq)`
  precisa ser único de qualquer jeito. O id próprio só acrescenta uma coluna e um
  segundo índice. Além disso, um contador global somaria todos os comentários do
  mundo num número só, gerado por uma sequence central. Com a chave dependente,
  o limite é por vídeo: 2,15 × 10^9 comentários em cada um, 136 vezes o recorde
  mundial.
- **Se `Comentario` passar de centenas de milhões de linhas,** o próximo passo é
  particionar por `HASH (id_video)`. A PK já contém a coluna de partição, como o
  PostgreSQL exige.

### 5.4 `Usuario`: o custo do `id_usuario`

| Tabela (volume) | Com `nick` (~13 caracteres) | Com `id_usuario BIGINT` |
|---|---|---|
| `Comentario` (1 milhão) | 104 MB + 39 MB de índice | 104 MB + 39 MB |
| `Inscricao` (600 mil) | 34 MB + 36 MB | 30 MB (−12%) + 36 MB |

Em `Comentario` o tamanho não muda: o `BIGINT` ocupa o espaço que o alinhamento
de `dataH` (8 bytes) já desperdiçava. O ganho principal não é espaço, é
estabilidade: renomear um usuário passa a atualizar uma linha, e não milhões.

## 6. Constraints (item mandatório 2)

| Constraint | Regra de negócio | Custo |
|---|---|---|
| `UNIQUE (nick)`, `UNIQUE (nome, nro_plataforma)` em `Canal`, `UNIQUE (id_canal, titulo, dataH)` em `Video` | A chave natural que deixou de ser PK continua identificando a linha | Um índice cada; é o preço da surrogate |
| `UNIQUE (nome, empresa_fund)` em `Plataforma` | Não pode haver duas plataformas com o mesmo nome e a mesma fundadora. A fundadora é um fato histórico; a responsável pode mudar por venda ou fusão | Tabela de 28 linhas |
| `UNIQUE (nome)` em `Empresa`, `Conversao` e `Pais` | Duas linhas com o mesmo nome seriam duplicata | Tabelas pequenas |
| `UNIQUE (email)` e `UNIQUE (telefone)` em `Usuario`, separados | O e-mail identifica a conta; o telefone serve para "validação em duas vias". Um `UNIQUE` composto só barraria o par idêntico | Dois índices em `Usuario` |
| `UNIQUE (nro_plataforma, nro_usuario)` | O número de usuário identifica a conta dentro da plataforma ("pode ser diferente em cada plataforma") | Índice numa tabela de ~10^6 linhas, de escrita rara |
| `UNIQUE (ddi_pais, nro_passaporte)` e `UNIQUE (ddi_pais, id_nacional)` | O passaporte é único no país emissor; o CNPJ, EIN etc., no país | Tabelas pequenas |
| `UNIQUE (TxID)` e `UNIQUE (IdPayPal)` | O TxID é o hash da transação na blockchain e não se repete; o IdPayPal identifica um pagamento. Pagamento duplicado é erro que o banco deve barrar | Um índice cada, nas tabelas de pagamento |
| `NOT NULL` em `pais_residencia`, `data_fund`, `Canal.data`, `NivelCanal.gif` | O minimundo dá "um país de residência", "uma data de fundação", "data de início" e "um arquivo .gif" a todos. O T11 e o T7 dependem dessas colunas | Nenhum |
| `CHECK` de valores | Valores monetários e fatores `> 0`; contadores e derivados `>= 0` (canal novo tem 0 visualizações); sequenciais `> 0`; duração `> 0`; `visu_simul <= visu_total`; domínios de `tipo` e `status` do enunciado | Nenhum índice; só a avaliação da expressão |

**Não criados de propósito:**
- `UNIQUE (nome, nome_fantasia)` em `Empresa` e `UNIQUE (moeda, nome)` em
  `Conversao`: um conjunto que já contém uma coluna única nunca é violado. Só
  gastaria um índice.
- `telefone NOT NULL`: o `UNIQUE` aceita vários nulos, e o grupo não quis
  obrigar o telefone em contas antigas. É uma brecha conhecida.

Os índices de `PRIMARY KEY` e `UNIQUE` são constraints e **não contam** no teto
de 5 índices de apoio (seção 11).

## 7. Moeda

| Receita | Moeda na origem | Quando converte para USD | Valor resultante | Por quê |
|---|---|---|---|---|
| Patrocínio | USD | Não converte | Contratual | Vem de contrato externo, em dólar, como o professor orientou |
| Doação | Moeda do país de residência de quem comentou | No `INSERT`, pelo trigger T11 | **Histórico**: o que o canal recebeu no dia | Ver abaixo |
| Membros | Moeda do país de residência do membro (valor do nível) | Na consulta, pela view V2 | **Corrigido**: quanto vale hoje | Ver abaixo |

O caminho da conversão da doação é `Comentario.id_usuario` →
`Usuario.pais_residencia` → `Pais.moeda` → `Conversao.fator_conver`.

**Por que a doação é histórica, se o professor disse que o corrigido serve
melhor para escolher patrocínio?**
1. **A doação é um evento passado; o membro é uma receita recorrente.** O valor
   corrigido dos membros é uma projeção: com o câmbio de hoje, é quanto o canal
   recebe no próximo mês. É essa a informação que interessa a quem vai
   patrocinar. A doação já aconteceu, e o fato é quanto entrou no dia.
2. **`Conversao` não guarda histórico de câmbio.** Converter a doação na consulta
   reprecificaria doações de anos atrás com o câmbio de hoje, e o valor do dia
   nunca mais poderia ser recuperado.
3. **O mundo real faz assim.** O YouTube converte a receita do criador pelo
   câmbio do período do pagamento (a média diária do mês) e não reavalia os meses
   já pagos.
4. **Custo das consultas.** Os itens 4, 7, 10 e 11 somam o valor direto, sem
   juntar ~100 mil doações com `Usuario`, `Pais` e `Conversao`.

O professor considerou as duas formas corretas. O custo aceito é que o
valor em moeda local se perde, porque não se pode criar coluna (seção 3).

**Critérios das consultas:**
- doação recusada não conta como recebida;
- não há histórico de patrocínio nem de membros, então só os vigentes entram;
- `k` nulo devolve todos os canais.

## 8. Triggers (item mandatório 5)

| ID | Regra | Origem | Como |
|---|---|---|---|
| T1 | `Canal.qtd_visualizacoes` = soma de `visu_total` dos vídeos | Derivado do modelo; soma bruta, como o professor confirmou | Trigger **por comando**, com tabelas de transição: um `INSERT` de mil vídeos do mesmo canal faz um único `UPDATE` no canal |
| T2 | `Plataforma.qtd_users` = número de contas | Derivado do modelo; o professor pediu trigger | Idem. O modelo diz "atualização periódica"; o trigger mantém o valor sempre exato. O tradeoff está na seção 8.1 |
| T3 | `seq` por vídeo | "Depende do vídeo" | Se vier nulo: `max + 1` com `SELECT … FOR UPDATE` no vídeo, para inserções simultâneas não gerarem o mesmo número. O `max` usa o prefixo da PK |
| T4 | `seq_pg` por comentário | "Depende do vídeo, do usuário e do comentário" | Idem, travando o comentário |
| T5 | `seq_plataforma` por usuário e plataforma | "Depende do usuário, do comentário e da plataforma" | Idem, travando a conta; exige conta na plataforma |
| T6 | Doação em exatamente uma das 4 formas | "d" (disjunta) no ER; "pode ser feita de quatro formas" (total) | Rejeita a segunda forma; um trigger de constraint adiado rejeita, no `COMMIT`, doação sem forma |
| T7 | Fundação ≤ canal ≤ vídeo ≤ comentário | Coerência temporal (escolha do grupo) | Não cabe em `CHECK`, porque envolve outra tabela |
| T8 | No máximo 5 níveis por canal | "Existem cinco níveis de membros" | Rejeita o sexto |
| T9 | Dono de canal e participante de vídeo são streamers | Especialização de `Usuario` no ER (streamer tem passaporte) | Exige passaporte; impede apagar o último passaporte de quem tem canal |
| T10 | O dono tem conta na plataforma do canal | Relacionamento "tem conta" do ER | Trigger, e não FK, para não mudar os relacionamentos do modelo |
| T11 | Doação em USD | Seção 7 | Converte pela moeda do país de residência |

- **Não precisam de trigger:** "sem histórico de patrocínios e membros" se
  resolve com `DELETE`.
- **T10 não vale para comentário e inscrição:** conferir a conta a cada
  comentário custaria uma busca a mais na maior tabela.
- **Triggers por último:** como o professor orientou, `triggers.sql`
  roda depois da carga. Por isso o seed obedece às mesmas regras, calcula os
  derivados no próprio `INSERT` e aborta se alguma regra falhar.
- **Testes:** cada trigger foi testado com um caso aceito e um rejeitado, mais a
  conferência dos derivados depois de `INSERT`, `UPDATE` e `DELETE`, numa
  transação desfeita com `ROLLBACK`: 37 casos, todos OK (`testes_triggers.sql`,
  na tag `v1.1.0`). O `tests.sql` da entrega só chama as functions e não altera
  dados.

### 8.1 Tradeoff do T2: atualizar `qtd_users` a cada nova conta

O modelo diz que `qtd_users` "requer atualização periódica", e o professor pediu
trigger para os dois derivados. O grupo escolheu o trigger **sabendo do
custo**: toda conta nova atualiza a linha da plataforma.

**Por que é aceitável no nosso banco: a plataforma quase não muda.**

| Fato | Por que favorece o trigger |
|---|---|
| `Plataforma` tem 28 linhas, e nome, empresas e data de fundação praticamente nunca mudam | O T2 é o único que escreve nessas linhas, então não disputa com outras atualizações da plataforma |
| A tabela cabe numa página de 8 KB | Fica sempre em cache; o `UPDATE` não lê disco |
| `qtd_users` não tem índice | A atualização é HOT: a nova versão fica na mesma página, sem mexer em índice |
| Criar conta é raro para cada usuário: uma vez por plataforma | No seed são 856 mil contas, contra 1,25 milhão de vídeos e 5 milhões de comentários |
| O trigger é por comando | Um crawler que insere 1 milhão de contas num `INSERT` faz no máximo 28 `UPDATE`s, um por plataforma |

**O que acontece com volume real (estimativas, não medidas):**

| Efeito | Conta | Consequência |
|---|---|---|
| Linha quente | Todo cadastro numa plataforma trava a mesma linha até o `COMMIT`. Com commit de 1 a 5 ms, o teto é de ~200 a 1.000 contas por segundo, inseridas uma a uma, por plataforma | Hoje cabe: o TikTok chegou a ~1,6 bilhão de usuários em ~7 anos, ~7 contas por segundo. O Threads teve 100 milhões de cadastros em 5 dias, ~230 por segundo na média, e isso já encosta no teto. No pior caso do cenário (6 bilhões de pessoas em 60 plataformas, em 10 anos), só o YouTube receberia ~320 por segundo |
| Comparação com o T1 | O T1 espalha as escritas por 36 mil canais; o T2 concentra todos os cadastros em 28 linhas | Por escrita, a disputa é muito maior no T2 |
| Inchaço | Cada `UPDATE` cria uma nova versão da linha. Uma transação longa, como o `REFRESH CONCURRENTLY` da V3 (~27 s), impede a limpeza: a 230 cadastros por segundo, são ~6.200 versões mortas da linha do YouTube, numa página que comporta ~100 | `Plataforma` cresce de 1 para dezenas de páginas, e o autovacuum dispara em todo ciclo (limite de ~56 versões mortas) |
| Deadlock | Dentro de um comando, as plataformas são atualizadas em ordem de número | Transações que inserem contas em plataformas diferentes, em comandos separados e em ordens opostas, ainda podem travar uma à outra |
| Leitura | Só o item 12 lê `qtd_users`, e só como contexto, fora do critério de ordenação | Paga-se custo em toda escrita para manter exato um valor pouco lido |

**Alternativas comparadas:**

| Opção | Exatidão | Custo na escrita | Custo de manutenção | Cabe na regra do trabalho? |
|---|---|---|---|---|
| Trigger por linha | Exata | 1 `UPDATE` por conta, mesmo em lote | Nenhum | Sim, mas é a pior |
| **Trigger por comando (adotado)** | Exata | 1 `UPDATE` por plataforma por comando; linha quente em cadastros um a um | Nenhum | Sim |
| Recontagem periódica (procedure agendada) | Defasada até a próxima execução | Zero | Hoje lê ~3.300 páginas da PK, em milissegundos. Em escala real, ~32 bytes por conta × 2,7 bilhões de contas do YouTube ≈ 85 GB, de 1 a 2 minutos por execução: viável uma vez por dia | Sim; é o que o comentário do modelo sugere |
| Contar na consulta, sem guardar | Exata | Zero | `COUNT` a cada leitura | Não: remove o atributo derivado |

**Decisão:** no nosso banco, com carga em lote e pouca escrita em contas, fica o
trigger por comando: o custo se dilui no lote, a plataforma não tem outro
escritor e o valor fica sempre exato. Num sistema real, com cadastros um a um e
transações longas, a recontagem periódica seria melhor: tira toda a disputa da
escrita, e a defasagem não afeta o item 12. A troca vale quando a maior
plataforma chegar a centenas de cadastros por segundo.

## 9. Views (item mandatório 3): 4 de 5

| View | Tipo | Atende | Por quê | Medido |
|---|---|---|---|---|
| V1 `vw_doacao_recebida` | Virtual | Itens 4, 7 e a V4 | Concentra num lugar só a regra de status e o caminho doação → vídeo → canal. Virtual para que o filtro desça até os índices das tabelas base | Mesmo patamar da consulta direta |
| V2 `vw_inscricao_usd` | Virtual | Item 6 e a V4 | Concentra a conversão dos membros | Idem |
| V3 `mv_interacoes_video` | Materializada | Itens 2 e 3 | Contar 5 milhões de comentários dominava o tempo. Contagem de comentários tolera atraso | Item 3 filtrado 7,5 s → 0,22 s (33×) |
| V4 `mv_faturamento_canal` | Materializada | Itens 8 a 11 | O top-k ordena por um valor agregado, e nenhum índice nas tabelas base atende isso. Para escolher patrocínio, atraso de horas é aceitável | Item 10: 0,73 s → 28 ms (26×) |

- **View virtual não acelera por si só:** o planejador a expande dentro da
  consulta. Ela vale pela regra centralizada. O ganho de tempo vem das
  materializadas.
- **Atualização:** periódica, com `CALL sp_refresh_views()`, que faz o
  `REFRESH … CONCURRENTLY` sem bloquear leituras. Não é por trigger: o refresh da
  V3 leva de 12 a 27 s, e recontar a cada comentário custaria mais que a consulta.
- **V5 (item 12) medida e descartada:** cairia de ~70 para ~7 ms numa resposta
  de 28 linhas, mas o item 12 deixaria de ser exato até o próximo refresh.

## 10. Consultas (item mandatório 6)

| Item | Function | Filtro opcional | Lê | Ponto de atenção |
|---|---|---|---|---|
| 1 | `sp_obter_streamers_com_maior_qtd_videos_publicados` | plataforma | `Video`, `Canal` | Índice de cobertura em `Video` no filtro |
| 2 | `sp_obter_videos_mais_comentados` | canal | V3 | Usada com `LIMIT` |
| 3 | `sp_obter_canais_por_qtd_total_interacoes` | streamer | V3 | Dois ramos excludentes, com e sem filtro |
| 4 | `sp_obter_canais_pela_media_doacoes_por_comentario` | plataforma | V1 | Média por comentário com doação, só doações não recusadas |
| 5 | `sp_obter_canais_patrocinados_com_valores_por_empresa` | empresa | `Patrocinio` | Devolve nome e plataforma do canal, porque o nome só é único por plataforma |
| 6 | `sp_obter_qtd_canais_e_gasto_mensal_por_usuario` | usuário | V2 | Índice em `Inscricao (id_membro)` |
| 7 | `sp_obter_canais_com_doacoes_recebidas` | canal | V1 | — |
| 8 a 11 | `sp_obter_top_k_canais_por_*` | `k` | V4 | `k` nulo devolve todos |
| 12 | `sp_obter_top_k_plataformas_por_streamers_e_canais` | `k`, plataforma | `Canal` | Desafio; ver abaixo |

- **Formato:** os itens 1 a 11 são `LANGUAGE sql STABLE`, para o planejador
  expandir a function dentro da consulta (*inline*). Assim, o filtro opcional
  `p IS NULL OR col = p` vira `col = p` e usa índice. O item 12 é `plpgsql`,
  porque a posição global impede o planejador de empurrar o filtro e porque
  valida os parâmetros com mensagem clara.
- **Reescrita antes dos índices,** como o professor orientou: filtrar antes de agregar e
  ler a V3 deixou o item 3 filtrado 33 vezes mais rápido e o item 2 filtrado 6
  vezes. Sem filtro, a reescrita direta piorou (estoura o `work_mem` e ordena em
  disco), e por isso esses casos leem a V3.
- **Item 12: top-k plataformas por streamers E canais.**

| Decisão | Escolhida | Alternativa descartada e por quê |
|---|---|---|
| Quem é "streamer da plataforma" | Quem tem canal nela, contado uma vez | Ter só conta não gera público; contar convidados de `Participa` dobraria as plataformas de live com a mesma audiência |
| O "E" sublinhado | Ordena por streamers e desempata por canais | Somar os dois contaria o mesmo criador duas vezes; exigir os dois (Pareto) não dá ordem total, então não há top-k |
| Empate no corte de `k` | Entram todas as empatadas | Cortar no meio do empate escolheria pelo nome, critério que o enunciado não dá |
| Com filtro | Mostra a posição no ranking geral | "1º de 1" responde errado |
| Validação | Comparada com uma contagem independente | 0 divergências |

## 11. Índices de apoio (item mandatório 4): 5 de 5

| # | Índice | Atende | Efeito medido a frio | Custo de `INSERT` |
|---|---|---|---|---|
| 1 | `ux_mv_interacoes_video (id_canal, id_video)` | V3: itens 2 e 3 | Obrigatório para o `REFRESH CONCURRENTLY`; com `id_canal` na frente, também atende o filtro por canal | 48 MB; só no refresh |
| 2 | `ux_mv_faturamento_canal (id_canal)` | V4: itens 8 a 11 | Obrigatório para o `REFRESH CONCURRENTLY` | 0,5 MB; só no refresh |
| 3 | `idx_inscricao_id_membro` (B-tree) | Item 6 por usuário; FK ao remover usuário | 155 → 4,5 ms; páginas 4.135 → 123 | +63% |
| 4 | `idx_canal_id_streamer` (B-tree) | Item 3 por streamer; T9 e T10 ("tem canal?") | Páginas 1.689 → 1.027; a quente 11 → 1,8 ms | +18% |
| 5 | `idx_video_id_canal_cobertura (id_canal) INCLUDE (visu_total)` | Item 1 por plataforma | 749 → 444 ms; páginas 25.526 → 9.530 | +7% |

**Método, como o professor indicou:**
1. inventário dos predicados das 12 consultas: igualdade, faixa, join,
   `GROUP BY`, `ORDER BY`/`LIMIT`;
2. distribuição de cada coluna (`pg_stats`) e seletividade real;
3. tipo do índice conforme o predicado;
4. medição a frio, com e sem o índice, e do overhead de `INSERT`.

**Por que cada um vale o overhead:**
- **3 e 4 (igualdade muito seletiva):** um membro tem ~1,9 inscrições e um
  streamer ~1,4 canal; o filtro devolve 0,0025% e 0,014% da tabela. A PK de
  `Inscricao` começa por `id_canal` e não serve para buscar por membro. São os
  "índices secundários sobre parte da chave" que o professor descreveu. O de
  `Inscricao` é o mais caro (+63%), mas inscrição é escrita rara e a busca por
  usuário é frequente.
- **5 (cobertura):** os vídeos de um canal ficam espalhados pela tabela (a ordem
  física segue o id, não o canal), e ler pela tabela custa uma página por vídeo.
  Com `visu_total` no `INCLUDE`, o plano lê só o índice (*Index Only Scan*).

**Hash × B-tree:** nos predicados só de igualdade (3 e 4), os dois foram medidos.
O hash leu as mesmas páginas, no mesmo tempo, e ficou maior (10,1 contra 8,4 MB
no lote de `Inscricao`). Na escrita, nenhum venceu sempre: o hash inseriu mais
rápido em `Inscricao` e mais devagar em `Canal`. Ficou o B-tree, que lê o mesmo,
ocupa menos e também entrega em ordem.

**Não indexados de propósito (o caso "todos americanos"):**
- `status <> 'recusado'` devolve 90% das doações;
- os itens sem filtro e o item 1 com o YouTube (28% dos canais) leem quase a
  tabela toda, e a varredura sequencial vence com ou sem índice;
- `Canal (nro_plataforma)`, de uma versão anterior: `Canal` tem 665 páginas e é
  lida em milissegundos; sem ganho medido;
- `Comentario (id_usuario)`: nenhuma consulta filtra por autor, e o índice
  pesaria na maior tabela.

**Os índices das views materializadas contam no teto de 5,** para não deixar
dúvida na avaliação.

**Por que o volume importa para medir índice (alerta do professor).** O
PostgreSQL lê páginas de 8 KB. Pelos tamanhos reais da carga:

| Tabela | Linhas | Páginas | Linhas por página |
|---|---:|---:|---:|
| `Comentario` (tabela) | 5.000.380 | 56.622 | ~88 |
| `comentario_pkey` (índice) | 5.000.380 | 24.781 | ~200 |
| `Video` (tabela) | 1.247.319 | 19.847 | ~63 |

- **Com 10.000 comentários** (o teto do enunciado), a tabela teria ~114 páginas
  (0,9 MB) e o índice, ~50 folhas e uma raiz: altura 2. Tudo caberia folgado no
  `shared_buffers` de 128 MB (16.384 páginas), e varrer a tabela custaria quase o
  mesmo que usar o índice. Seria o "não aconteceu nada" que o professor descreveu.
- **Com 5 milhões,** a tabela tem 464 MB, 3,5 vezes o `shared_buffers`. A
  diferença entre ler 54 e 4.040 páginas do disco aparece no tempo.

## 12. Dados (item mandatório 1)

O professor autorizou ultrapassar a faixa de 1.000 a 10.000 registros: "povoar o
máximo [...] centenas de milhares de tuplas", com distribuição desbalanceada.
A seção 11 mostra por que isso é necessário para o índice fazer
diferença. A carga tem **cerca de 8,7 milhões de registros**:

| Tabela | Registros | Tabela | Registros |
|---|---:|---|---:|
| Conversao | 154 | Inscricao | 598.075 |
| Pais | 199 | Patrocinio | 18.785 |
| Empresa | 3.000 | Video | 1.247.319 |
| EmpresaPais | 3.471 | Participa | 94.416 |
| Plataforma | 28 | Comentario | 5.000.380 |
| Usuario | 500.000 | Doacao | 100.113 |
| PlataformaUsuario | 856.263 | BitCoin | 9.623 |
| StreamerPais | 26.081 | PayPal | 21.730 |
| Canal | 35.906 | CartaoCredito | 23.880 |
| NivelCanal | 98.855 | MecanismoPlat | 44.880 |

A contagem é da carga usada no [benchmark.md](benchmark.md). Os UUIDs dos vídeos
mudam a cada carga (o `gen_random_uuid()` não obedece à semente), e alguns
sorteios dependem deles. Por isso `Comentario`, `Participa`, `Doacao`,
`MecanismoPlat` e as formas de pagamento podem variar algumas centenas de
registros entre cargas; as demais tabelas não mudam.

| Escolha | Por quê |
|---|---|
| Tabelas de referência no tamanho real, abaixo de 1.000: 154 moedas ISO 4217, 199 países, 28 plataformas reais | O professor não espera "10 mil países". Inflar com linhas fictícias deixaria os dados irreais |
| Mesmo cenário da seção 4, em escala reduzida | Plataformas de vídeo curto com mais vídeos por canal; vídeos curtos só com comentários offline e menos comentários por visualização |
| Popularidade de cada canal por lognormal | Poucos canais concentram a audiência, como no mundo real. A popularidade comanda visualizações, quantidade de vídeos, membros e patrocínio |
| Comentários proporcionais às visualizações, com cauda longa | O professor citou a relação: vídeo com muitas visualizações tem muitos comentários |
| Autores de comentário e membros por lei de potência | Poucos usuários muito ativos |
| 5% dos usuários são streamers; 1,9% dos comentários trazem doação | Proporções plausíveis; uma versão anterior tinha 25% e 50%, irreais |
| Doação sorteada em moeda local e convertida como o T11 faria | O T11 não existe durante a carga |
| Semente fixa, banco vazio exigido, uma transação, conferência final das regras dos triggers antes do `COMMIT` | Reprodutível pelo professor. Mudam só os UUIDs dos vídeos (o `gen_random_uuid()` não obedece à semente) e o que deriva deles: TxID, IdPayPal e número do cartão |
| Escala ajustável (`make setup ESCALA=0.1`) | A carga completa leva de 6 a 9 minutos; a escala 0,1 roda em menos de 1 minuto |

## 13. Medição

Cada medida a frio é feita depois de:
1. reiniciar o Postgres, o que esvazia o `shared_buffers`;
2. limpar o cache de páginas da VM do Docker (`drop_caches`), que sobrevive ao
   reinício do container.

São 5 repetições, e o valor usado é a mediana. A medida só vale como fria se o
plano mostrar páginas lidas do disco (`shared read` > 0). A sessão de medida usa
`jit = off` e um único processo, para os tempos serem comparáveis. O cache
esconde o custo: o item 2 filtrado leva 631 ms a frio e 11 ms a quente. O
resultado completo está em [benchmark.md](benchmark.md), e o `EXPLAIN ANALYZE` de
cada medida, em [`bench/planos/`](bench/planos/).

## 14. Entrega

| Arquivo pedido no Classroom | Arquivo do projeto |
|---|---|
| 1. DDL de construção das tabelas | `ddl.sql` |
| 2. PL/pgSQL: functions, triggers, views e outros | `views.sql`, `functions.sql` (com os índices de apoio no fim) e `triggers.sql` |
| 3. Dados para inserção | `seed.sql` (gera os dados; o arquivo é pequeno) |
| 4. Chamadas das consultas e functions para teste | `tests.sql` |
| 5. PDF de decisões | este arquivo (o detalhamento completo em `decisoes_detalhamento.md`) |

Ordem de execução: `ddl` → `seed` → `views` → `functions` → `triggers` →
`tests`, explicada no [README.md](README.md).

## Fontes

- ITU, *Facts and Figures 2025: Internet use*:
  <https://www.itu.int/itu-d/reports/statistics/2025/10/15/ff25-internet-use>
- ONU, *World Population Prospects 2024*:
  <https://www.un.org/sustainabledevelopment/blog/2024/07/press-release-wpp2024/>
- Vídeos no YouTube (UMass Amherst, projeto "Dialing for Videos"): The Atlantic,
  via SSRC, <https://mediawell.ssrc.org/news-items/there-are-14-billion-videos-on-youtube-the-atlantic/>;
  TechSpot, <https://www.techspot.com/news/106791-youtube-numbers-uncovering-youtube-ghost-town-billions-unwatched.html>
- Uploads no TikTok por dia: Printful, <https://printful.com/blog/tiktok-statistics>
- Usuários de redes sociais: Statista,
  <https://www.statista.com/statistics/272014/number-of-us-social-network-users>;
  Market.us, <https://market.us/statistics/youtube>
- Canais no YouTube: Vaizle, <https://insights.vaizle.com/youtube-statistics/>;
  DemandSage, <https://www.demandsage.com/youtube-creator-statistics/>
- Streamers na Twitch: DemandSage, <https://demandsage.com/twitch-users>
- Vídeo mais visto: Guinness World Records,
  <https://www.guinnessworldrecords.com/world-records/95003-most-viewed-video-online>
- Canais mais vistos: Statista,
  <https://statista.com/statistics/373753/most-viewed-youtubers-all-time>
- Vídeo mais comentado: Billboard,
  <https://www.billboard.com/articles/columns/k-town/9444950/bts-record-dynamite-youtube-comments>
- Recorde de audiência simultânea: Business Today,
  <https://businesstoday.in/technology/news/story/youtube-ceo-neal-mohan-congratulates-isro-for-getting-more-than-8-mn-concurrent-viewers-for-chandrayaan-3-landing-398533-2023-09-15>
- Empresas na base da Dun & Bradstreet:
  <https://www.dnb.com/perspectives/master-data/data-cloud-400million.html>;
  <https://www.dnb.co.uk/why-dnb/our-data.html>
- Threads com 100 milhões de cadastros em 5 dias (julho de 2023): Al Jazeera,
  <https://www.aljazeera.com/news/2023/7/10/threads-hits-100-million-users-in-five-days-in-record-surge>
- Câmbio da receita do YouTube (média diária do mês): Google, *Payment Summary
  Report*, <https://support.google.com/youtube/answer/9486878>
- Limites dos tipos numéricos e do UUID: documentação do PostgreSQL 17,
  <https://www.postgresql.org/docs/17/datatype-numeric.html> e
  <https://www.postgresql.org/docs/17/datatype-uuid.html>

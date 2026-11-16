# Stream do Bedo · Detalhamento das decisões de projeto

Trabalho final de Projeto de Banco de Dados (UFF, 2026/2), em PostgreSQL 17.

Este documento explica, uma a uma, as decisões tomadas pelo grupo: o que foi
decidido, qual exigência do trabalho a decisão atende, por que essa opção foi a
escolhida, quais alternativas foram avaliadas e quais limitações ficaram. O
[resumo das decisões](decisoes_resumo.md) (também em PDF) traz as principais
decisões em duas páginas, com a marca [D x.y] apontando a seção deste documento.

As medições de desempenho completas estão em [benchmark.md](benchmark.md). As
fontes dos dados do mundo real estão no fim deste arquivo.

## 1. Como cada decisão está descrita

Cada decisão responde a cinco perguntas:

- **Exigência:** que parte do enunciado, item mandatório ou orientação do
  professor a decisão atende.
- **Decisão:** o que está no código, e em qual arquivo.
- **Por quê:** o argumento, com a conta ou a medição que o sustenta.
- **Alternativas:** o que mais foi considerado e por que ficou de fora.
- **Limitações:** o que a decisão não resolve ou o que ela custa.

As orientações do professor citadas vêm da consulta de 11/11/2026.

## 2. Exigências do enunciado

| Exigência | Onde é tratada |
|---|---|
| "A base de dados não deve conter redundância"; normalizar o modelo | Seção 3 |
| "Verificar a possibilidade do uso de identificador artificial" (comentário de `Video` no modelo) | Seções 4 e 5 |
| **Item mandatório 1:** de 1.000 a 10.000 tuplas por tabela | Seção 12 |
| **Item mandatório 2:** identificadores artificiais, `UNIQUE` e `NOT NULL` usados com critério | Seções 4, 5 e 6 |
| **Item mandatório 3 / Especificação 1:** até 5 visões, virtuais e materializadas, cada uma justificada | Seção 9 |
| **Item mandatório 4 / Especificação 2:** até 5 índices, cada um justificado, considerando o overhead de inserção | Seção 11 |
| **Item mandatório 5 / Especificação 3:** triggers para manter a consistência (todas as necessárias) | Seção 8 |
| **Item mandatório 6 / Especificação 4:** functions parametrizadas para as consultas 1 a 12 | Seções 7 e 10 |
| Consulta 12 (desafio) | Seção 10.4 |
| Entrega: DDL, dados, rotinas, testes e documento de decisões | Seção 14 |

## 3. Regra do trabalho e normalização

### 3.1 O que pode e o que não pode mudar no modelo

**Exigência.** O enunciado entrega um modelo relacional pronto e pede uma base
sem redundância. Na consulta, o professor deixou claro que o trabalho
**otimiza** esse modelo, sem alterá-lo: "não pode criar coluna, não pode excluir
coluna [...], não pode tirar atributo derivado".

**Decisão.** Todas as decisões deste documento seguem esta regra:

| Pode | Não pode |
|---|---|
| Remodelar chaves, inclusive com chave artificial (surrogate) | Criar ou remover tabelas |
| Mudar tipos de coluna | Mudar relacionamentos |
| Criar constraints (`UNIQUE`, `NOT NULL`, `CHECK`, FK) | Criar colunas que não sejam de chave |
| Criar índices, views, triggers e functions | Remover atributos derivados (`qtd_users`, `qtd_visualizacoes`) |

As únicas colunas que não estão no enunciado são as chaves artificiais
`Usuario.id_usuario`, `Canal.id_canal` e `Video.id_video` e as colunas que
apontam para elas (`id_streamer`, `id_membro`, `id_usuario`). Elas **substituem**
as colunas de chave natural que se propagavam pelo modelo (`nick`,
`nome_canal` + `nro_plataforma`, `titulo` + `dataH`); não acrescentam
informação.

### 3.2 Data de inscrição do membro: avaliada e não criada

**Exigência.** As consultas 6, 9 e 11 somam o valor mensal pago pelos membros.

**Decisão.** `Inscricao` não tem data de inscrição. As consultas somam o valor
mensal de todas as inscrições existentes.

**Por quê.** O minimundo diz que "apenas os membros vigentes devem aparecer no
sistema" e que o membro contribui com um valor mensal conforme o nível. Toda
inscrição gravada é, portanto, vigente, e a soma do valor mensal responde às
consultas sem precisar de data. Uma versão anterior chegou a criar a coluna
`data_inscricao` e um parâmetro `p_data_ref` nas functions; os dois saíram
porque a coluna não é de chave e a regra da seção 3.1 não permite criá-la.

**Limitações.** Uma consulta como "membros desde a data X" não é possível. O
enunciado não pede. Pelo mesmo motivo, a data e a hora do pagamento com cartão,
que o minimundo cita mas o modelo relacional não tem, também não foram criadas:
vale a data e a hora do comentário.

### 3.3 Como as chaves artificiais reduzem a redundância

**Exigência.** Base sem redundância.

**Decisão e por quê.**

| Situação no modelo dado | Problema | Decisão | Efeito |
|---|---|---|---|
| `nome_canal` + `nro_plataforma` repetidos em 11 tabelas | O nome do canal se repete em cada vídeo, comentário e doação; renomear o canal exigiria atualizar todas essas linhas | `id_canal` (8 bytes) | O nome fica guardado uma vez só, em `Canal` |
| `titulo` + `dataH` do vídeo repetidos em 7 tabelas | Chave de ~53 bytes repetida em 5 milhões de comentários | `id_video` (16 bytes) | O índice da chave de `Comentario` caiu 76% (seção 5.4) |
| `nick` como chave em 6 tabelas | O nick pode mudar; trocar um nick exigiria atualizar milhões de comentários | `id_usuario` (8 bytes) | O nick fica guardado uma vez só, em `Usuario` |
| `Doacao` com `nick_usuario` na chave | O autor da doação já é determinado pelo comentário: `(id_video, seq) → id_usuario`. Com o nick, a chave deixa de ser mínima e o autor fica gravado duas vezes, podendo divergir | `Doacao` sem o autor; chave `(id_video, seq_comentario, seq_pg)` | Chave mínima, sem dependência redundante |
| `qtd_visualizacoes` e `qtd_users` | São redundantes por definição (atributos derivados), mas o modelo exige mantê-los | Mantidos, com triggers que os deixam sempre iguais à soma e à contagem (seção 8) | Redundância controlada, sem divergência |

## 4. Cenário de volumetria e tipos das colunas

### 4.1 O cenário

**Exigência.** O item mandatório 2 pede identificadores artificiais escolhidos
com critério, e o modelo pede para avaliar um identificador artificial em
`Video`. O professor deixou o grupo escolher o tipo de vídeo e o volume, desde
que o **mesmo cenário** justifique tudo: os tipos das chaves, a carga de dados e
os índices. Ele sugeriu a conta: com todos os streamers filmando 24 horas e um
vídeo a cada 10 minutos, "você não vai conseguir estourar"; mas, se alguém
publica um short a cada 10 segundos replicado em 60 plataformas, "aí não vai ter
como".

**Decisão.** O cenário de referência é um catálogo de streaming de jogos com
**vídeo longo e curto** (lives, VODs, Shorts, TikTok, Reels), em dezenas de
plataformas, com horizonte de **10 anos** e dados coletados por crawlers.

**Por quê.** Só vídeo longo deixaria a escolha dos tipos fácil demais. Com vídeo
curto, o volume de vídeos e de canais passa dos limites do `INTEGER`, e a forma
de gerar o identificador passa a importar. É o cenário que obriga a pensar cada
tipo.

**Limitações.** O cenário não é estatística oficial; é a hipótese que torna as
decisões coerentes entre si. Os números abaixo vêm de fontes secundárias e
variam entre elas: servem como **ordem de grandeza**, que é o que decide o tipo.

### 4.2 Dados do mundo real usados nas contas

| Dado | Valor | Fonte |
|---|---:|---|
| Pessoas usando a internet (2025) | 6,0 × 10^9 | ITU |
| Pico da população mundial (por volta de 2084) | 1,03 × 10^10 | ONU |
| Usuários do YouTube | 2,5 a 2,7 × 10^9 | Statista, Market.us |
| Usuários do TikTok | 1,6 a 1,9 × 10^9 | Statista |
| Canais no YouTube | ~1,14 × 10^8 | Vaizle, DemandSage |
| Streamers distintos por mês na Twitch (2025) | ~7 × 10^6 | TwitchTracker, via DemandSage |
| Vídeos públicos no YouTube (meados de 2024) | 1,48 × 10^10 | UMass Amherst |
| Vídeos públicos no YouTube (2022) | 9 × 10^9 | UMass Amherst |
| Vídeos enviados ao TikTok por dia | ~2,3 × 10^7 | Statista, via agregadores |
| Vídeo mais visto do YouTube ("Baby Shark Dance") | 1,66 × 10^10 visualizações | Guinness World Records |
| Canal mais visto do YouTube (T-Series) | 2,92 × 10^11 visualizações | Statista |
| Vídeo mais comentado do YouTube (BTS, "Dynamite") | ~1,58 × 10^7 comentários | Billboard |
| Maior pico simultâneo numa live (ISRO, Chandrayaan-3) | ~8,06 × 10^6 espectadores | YouTube, imprensa |
| Empresas na base da Dun & Bradstreet (inclui inativas) | ~6 × 10^8 | Dun & Bradstreet |

Limites dos tipos (o `IDENTITY` começa em 1 e não dá a volta, então todo o
intervalo positivo é utilizável):

| Tipo | Bytes | Maior valor |
|---|---:|---:|
| `SMALLINT` | 2 | 32.767 (3,3 × 10^4) |
| `INTEGER` | 4 | 2.147.483.647 (2,15 × 10^9) |
| `BIGINT` | 8 | 9,22 × 10^18 |
| `UUID` v4 | 16 | 122 bits aleatórios (5,3 × 10^36 combinações) |

### 4.3 Quantos vídeos o cenário prevê

O ritmo do YouTube sai da própria pesquisa da UMass: de 9 bilhões (2022) para
14,8 bilhões (meados de 2024), cerca de **8 milhões de vídeos por dia**. O
TikTok soma ~23 milhões por dia.

| Hipótese | Conta | Total | Cabe em `INTEGER`? | Fração do `BIGINT` |
|---|---|---:|---|---:|
| Hoje, só o YouTube | estoque medido | 1,48 × 10^10 | não (6,9 vezes o limite) | 1,6 × 10^-9 |
| Realista: YouTube + TikTok por 10 anos | (8 × 10^6 + 2,3 × 10^7) por dia × 3.650 dias + estoque | ~1,3 × 10^11 | não (60 vezes) | 1,4 × 10^-8 |
| Professor, vídeo longo: todo streamer filmando 24 h, um vídeo a cada 10 min | 7 × 10^6 streamers × 144 vídeos/dia × 3.650 dias | 3,7 × 10^12 | não (1.700 vezes) | 4 × 10^-7 |
| Professor, vídeo curto: um short a cada 10 s, replicado em 60 plataformas | 10^6 criadores × 8.640/dia × 60 × 3.650 dias | 1,9 × 10^15 | não | 0,02% |

Três conclusões guiam as seções seguintes:

1. **`INTEGER` não serve nem para o YouTube de hoje.** Qualquer cenário com
   vídeo exige pelo menos `BIGINT`.
2. **O `BIGINT` aguenta até o pior caso do professor.** Para estourá-lo no
   cenário de shorts seriam precisos ~4,9 bilhões de criadores, cerca de 80% de
   toda a internet, postando a cada 10 segundos por 10 anos.
3. **O que o vídeo curto muda não é a capacidade, é a forma de gerar o id.** Com
   dezenas de plataformas coletadas por crawlers, o id precisa nascer no coletor,
   sem consultar uma sequence central. Isso leva ao UUID (seção 5.3).

### 4.4 Tipo de cada coluna numérica

**Exigência.** Item mandatório 2 e a regra de que o tipo pode mudar (seção 3.1).

**Decisão e por quê.**

| Coluna | Maior valor previsto | Conta | Tipo |
|---|---:|---|---|
| `Plataforma.nro` e `nro_plataforma` | ~10^3 | 28 plataformas reais no seed; dezenas a centenas no mundo | `INTEGER` |
| `Empresa.nro` e as colunas que o referenciam | ~6 × 10^8 | todas as empresas da base da D&B ocupariam 28% do `INTEGER` | `INTEGER` |
| `Usuario.id_usuario` | 6,0 × 10^9 hoje; 1,03 × 10^10 no pico populacional | a internet de hoje já é 2,8 vezes o `INTEGER` | `BIGINT` |
| `Canal.id_canal` | > 2,15 × 10^9 | no cenário todo criador de vídeo curto tem canal; só o TikTok tem 1,6 a 1,9 × 10^9 usuários (75% a 88% do `INTEGER`), e somam-se dezenas de plataformas | `BIGINT` |
| `Video.id_video` | 1,9 × 10^15 no pior caso | 0,02% do `BIGINT` | `UUID` (seção 5.3) |
| `Comentario.seq` (por vídeo) | ~1,6 × 10^7 | o recorde mundial ocupa 0,74% do `INTEGER`; o `SMALLINT` estouraria 480 vezes | `INTEGER` |
| `Doacao.seq_pg`, `seq_doacao`, `seq_plataforma` | ~10 | poucas doações por comentário | `INTEGER` |
| `Video.visu_total` | 1,66 × 10^10 | o vídeo mais visto de hoje já é 7,7 vezes o `INTEGER` | `BIGINT` |
| `Canal.qtd_visualizacoes` | 2,92 × 10^11 | 136 vezes o `INTEGER`; o `BIGINT` comporta 3 × 10^7 canais do tamanho da T-Series | `BIGINT` |
| `Video.visu_simul` | 8,06 × 10^6 | 0,38% do `INTEGER` | `BIGINT` |
| `Plataforma.qtd_users` | 2,5 a 2,7 × 10^9 | acima do `INTEGER` | `BIGINT` |
| `Patrocinio.valor`, `NivelCanal.valor`, `Doacao.valor` | contratos de dezenas de milhões de USD | `NUMERIC(14, 2)` vai até ~10^12 | `NUMERIC(14, 2)` |
| `Conversao.fator_conver` | de ~10^-5 (libra libanesa) a ~3 (dinar kuwaitiano) | 8 casas guardam a moeda mais fraca com 3 dígitos significativos | `NUMERIC(18, 8)` |

Detalhes que a tabela não mostra:

- **Plataforma: por que não `SMALLINT` nem `BIGINT`.** O `SMALLINT` também
  caberia no mundo real, mas deixa pouca margem para escalas sintéticas, e os 2
  bytes economizados se perdem no alinhamento das colunas vizinhas de 8 bytes. O
  `BIGINT` seria folga sem uso: a 10^9 inserções por segundo, levaria ~292 anos
  para esgotar. Com as chaves artificiais, `nro_plataforma` só aparece em
  `Plataforma`, `Canal` e `PlataformaUsuario`, então a escolha vale mais pela
  coerência de critério do que pelo espaço.
- **Empresa.** A folga é menor que a da plataforma, mas ainda grande. Por isso
  também não é `SMALLINT`: 32.767 empresas seriam ultrapassadas numa escala
  sintética. `Empresa` só é referenciada por tabelas pequenas (`Plataforma`,
  `EmpresaPais`, `Patrocinio`).
- **Usuário.** O `BIGINT` só deixaria de atender acima de ~9 × 10^8 contas por
  habitante do planeta. Mesmo no pior caso, com o pico populacional de
  1,03 × 10^10 pessoas, cada uma com conta em 60 plataformas e 10 gerações de
  contas apagadas (o id nunca é reaproveitado), seriam 6,2 × 10^12 ids, cerca de
  7 × 10^-7 do limite. E não custa espaço em `Comentario`: ocupa os bytes que o
  alinhamento de `dataH` já desperdiçava (seção 5.1).
- **Canal.** Os 4 bytes a mais por linha são pagos em `NivelCanal`, `Inscricao`,
  `Patrocinio` e `Video`. `Comentario` e `Doacao` não têm `id_canal` (chegam ao
  canal pelo vídeo), então as maiores tabelas não pagam.
- **Sequenciais.** A numeração do comentário recomeça em cada vídeo, então só
  importa o máximo de **um** vídeo. Nas doações, `UUID` (16) + `INTEGER` (4) +
  `INTEGER` (4) fecham a chave em 24 bytes, sem bytes perdidos no alinhamento;
  com `BIGINT` seriam 32.
- **`visu_simul`.** O `INTEGER` bastaria, mas a coluna é comparada com
  `visu_total` no `CHECK (visu_simul <= visu_total)` e tem o mesmo domínio.
- **Dinheiro.** Decimal exato: valor monetário não pode ter erro de
  arredondamento de ponto flutuante.

**Colunas de texto com tamanho do mundo real.** `Conversao.moeda VARCHAR(3)`
(código ISO 4217), `BitCoin.TxID VARCHAR(64)` (hash SHA-256 em hexadecimal),
`CartaoCredito.nro VARCHAR(19)` (até 19 dígitos pela ISO/IEC 7812) e
`Pais.ddi VARCHAR(4)`. O DDI não é único no mundo real (Estados Unidos, Canadá e
o Caribe dividem o +1; Rússia e Cazaquistão, o +7), então a carga usa o prefixo
que distingue o país: os países do Caribe no +1 usam 1 + código de área (1876
para a Jamaica), o Canadá usa 1613, o Cazaquistão 77 e o Vaticano 379 (código
reservado a ele pela UIT).

**Limitações.** As escolhas pressupõem que o número de plataformas e de empresas
nunca passe de 2,1 bilhões. O ganho de espaço do `INTEGER` em `Plataforma` e
`Empresa` não foi medido; o argumento é o tamanho do tipo.

## 5. Chaves

**Exigência comum a esta seção.** Item mandatório 2 (identificadores
artificiais, com `UNIQUE` e `NOT NULL` criteriosos), o comentário do modelo que
pede para avaliar um identificador artificial em `Video` e a base sem
redundância.

### 5.1 Usuário: `id_usuario` com o nick único

**Decisão.** `id_usuario BIGINT GENERATED ALWAYS AS IDENTITY` é a chave primária.
O `nick` continua obrigatório e único (`UNIQUE NOT NULL`). As seis tabelas que
referenciavam o nick passam a referenciar o id (`id_usuario`, `id_streamer` ou
`id_membro`, conforme o papel).

**Por quê.** Foi uma pergunta do professor: por que o comentário referencia o
nick e não um id do usuário?

1. **Estabilidade.** As plataformas deixam o usuário trocar de nick. Com o nick
   como chave, renomear alguém exigiria atualizar milhões de comentários; com o
   id, atualiza uma linha.
2. **Junção por inteiro.** Comparar `BIGINT` é mais barato que comparar texto
   com regras de idioma (collation).
3. **Tipo.** `BIGINT`, pela conta da seção 4.4.

Medição (banco descartável):

| Tabela (volume) | Com `nick` (~13 caracteres) | Com `id_usuario BIGINT` |
|---|---|---|
| `Comentario` (1 milhão) | 104 MB + 39 MB de índice | 104 MB + 39 MB |
| `Inscricao` (600 mil) | 34 MB + 36 MB | 30 MB (−12%) + 36 MB |

Em `Comentario` o tamanho não muda: o `BIGINT` ocupa o espaço que o alinhamento
de `dataH` já desperdiçava. O ganho principal não é espaço, é estabilidade.

**Limitações.** `Usuario` ganha um índice a mais (o do `UNIQUE (nick)`). As
consultas que filtram por nick (itens 3 e 6) passam por ele e depois seguem pelo
id; as que devolvem o nick juntam `Usuario` só no fim.

### 5.2 Canal: `id_canal` com nome e plataforma únicos

**Decisão.** `id_canal BIGINT GENERATED ALWAYS AS IDENTITY` é a chave primária, e
`UNIQUE (nome, nro_plataforma)` preserva a identidade de negócio. `Patrocinio`,
`NivelCanal`, `Inscricao` e `Video` referenciam `id_canal`. Como o professor
indicou, a chave artificial se propaga: `Patrocinio` tem chave
`(nro_empresa, id_canal)`, `NivelCanal` `(id_canal, nivel)` e `Inscricao`
`(id_canal, id_membro)`.

**Por quê.** A chave `(nome, nro_plataforma)` do modelo é correta, mas larga:
`nome VARCHAR(255)` aparecia em 11 tabelas, na chave e na FK de cada uma, e
portanto em cada linha e em cada índice. O id substitui as duas colunas por 8
bytes, e o `UNIQUE` continua impedindo dois canais com o mesmo nome na mesma
plataforma.

**Alternativas.**

| Alternativa | Por que não |
|---|---|
| Manter `(nome, nro_plataforma)` como chave | Correta, mas repete o nome em todas as tabelas filhas, inclusive nas maiores |
| Chave só no `nome` ("identificado por seu nome único") | O mesmo streamer pode ter canais de mesmo nome em plataformas diferentes ("um ou mais canais [...] em diferentes plataformas"). Seria uma regra que o domínio não garante |
| `id_canal INTEGER` | Estoura no cenário com vídeo curto (seção 4.4) |

**Limitações.** `Canal` ganha um índice a mais (o do `UNIQUE`). As consultas que
devolvem o nome do canal precisam juntar `Canal`; elas agregam pelo id e juntam o
nome no fim, e devolvem também a plataforma, porque o nome só é único por
plataforma.

### 5.3 Vídeo: `id_video` UUID com canal, título e data únicos

**Decisão.** `id_video UUID DEFAULT gen_random_uuid()` é a chave primária, e
`UNIQUE (id_canal, titulo, dataH)`, com `titulo` e `dataH` `NOT NULL`, preserva
a identidade de negócio ("identificado por seu título e data/hora de
postagem"). `Participa`, `Comentario`, `Doacao` e as quatro formas de pagamento
referenciam só `id_video`.

**Por quê uma chave artificial.** O professor deu duas opções: manter o canal na
chave do vídeo ou criar só um id do vídeo, conforme a quantidade de vídeos. Ele
lembrou que a tabela de vídeos cresce muito e que a chave artificial não gera
redundância. O grupo comparou quatro alternativas:

| Alternativa | Chave de `Video` | O que se repete nas tabelas filhas | Problemas | Decisão |
|---|---|---|---|---|
| Chave natural do modelo | `(id_canal, titulo, dataH)` | ~53 bytes por linha | Em 5 milhões de comentários, só a chave repetida soma ~265 MB, mais o índice. O título é texto e pode ser editado | Não |
| Composta, como o professor sugeriu | `(id_canal, seq_video)` | 12 bytes, mas o `id_canal` volta para todas as filhas | É a redundância que a chave artificial evita. O `seq_video` exige `max + 1` com trava no canal, e um canal de shorts publica sem parar. Mudar o vídeo de canal mudaria a chave e cascatearia em milhões de comentários | Não |
| `BIGINT IDENTITY` | `id_video` | 8 bytes | Capacidade suficiente (seção 4.3), mas depende de uma sequence central: dois crawlers não geram ids sem consultar o banco, e juntar coletas exige renumerar | Perdeu pela forma de geração |
| **`UUID`** | `id_video` | 16 bytes | Custo de espaço e de inserção, medido abaixo | **Escolhida** |

**Por que UUID.** No cenário, os vídeos chegam de dezenas de plataformas por
crawlers. Com UUID, cada coletor gera o id na hora, sem consultar o banco, sem
colisão prática e sem renumerar ao juntar coletas. O id também não é
enumerável: com uma sequence, o id revela quantos vídeos existem e permite
percorrer todos somando 1. A chance de colisão de um UUID v4 com *n* ids é de
cerca de *n*² / 2^123:

- no cenário realista (1,3 × 10^11 vídeos): ~1,5 × 10^-15;
- no pior caso do professor (1,9 × 10^15 vídeos): ~3,4 × 10^-7.

O `UNIQUE (id_canal, titulo, dataH)` é a segunda barreira. Como o índice desse
`UNIQUE` começa por `id_canal`, ele também atende a busca "vídeos de um canal",
que era a vantagem da chave composta.

**Custo medido** (banco descartável, 1 milhão de linhas):

| Variante | `Video` (tabela + chave) | `INSERT` de 1 milhão | Índice da chave de `Comentario` |
|---|---:|---:|---:|
| `BIGINT IDENTITY` | 64 MB | 2,8 s | 39 MB |
| UUID v4 (`gen_random_uuid()`) | 88 MB (+37%) | 6,2 s | 50 MB (+28%) |

O grupo aceita esse custo pela geração distribuída. As maiores tabelas pagam
pouco, porque `Comentario` e `Doacao` não carregam `id_canal`.

**UUID v4 nativo, e não v7.** O v4 é aleatório: cada vídeo novo entra num ponto
qualquer da árvore do índice, e não no fim, como numa sequence. Isso gera mais
divisões de página. O UUID v7, ordenado no tempo, evitaria esse custo, mas o
PostgreSQL 17 não tem `uuidv7()` nativo (só a versão 18). O grupo chegou a usar
um v7 gerado por uma function própria e mediu as duas versões: mesmo tamanho de
tabela e de índice, e `INSERT` cerca de 9% mais lento no v4. Preferiu a função
nativa a manter uma function própria.

**Limitações.** 16 bytes repetidos em sete tabelas e `INSERT` mais lento que com
`BIGINT`. O `gen_random_uuid()` não obedece à semente da carga, então os ids dos
vídeos mudam a cada execução (seção 12). Migrar para o PostgreSQL 18 permitiria
trocar para `uuidv7()`.

### 5.4 Comentário: entidade fraca do vídeo

**Decisão.** `Comentario` tem chave `(id_video, seq)`. O autor (`id_usuario`)
fica fora da chave, como coluna `NOT NULL` com FK para `Usuario`. Não há id
próprio do comentário.

**Por quê.** O minimundo diz que cada comentário tem "um número sequencial que
depende do vídeo", e o professor confirmou que o comentário fica identificado
pelo vídeo. Isso é uma **entidade fraca**:

- **não existe sozinha:** todo comentário pertence a um vídeo, e a FK para
  `Video` faz parte da chave;
- **não tem identificador próprio:** é identificada pelo vídeo (a entidade forte)
  mais um número, o `seq`, que conta 1, 2, 3… e recomeça em cada vídeo;
- **a chave é a do dono mais esse número:** `(id_video, seq)`.

O grupo mediu quatro chaves com 1 milhão de comentários (50 mil vídeos × 20,
inserção em ordem aleatória, mesmos dados nas quatro):

| Variante | Chave | Tabela | Índices | Total | `INSERT` |
|---|---|---:|---:|---:|---:|
| A (modelo dado) | `(nome_canal, nro_plataforma, titulo, dataH, nick, seq)` | 195 MB | 156 MB | 352 MB | 11,2 s |
| B | `(id_video, nick, seq)` | 135 MB | 62 MB | 196 MB | 7,2 s |
| **C (escolhida)** | **`(id_video, seq)`** | 135 MB | **38 MB** | **173 MB** | **5,3 s** |
| D | `id_comentario` + `UNIQUE (id_video, seq)` | 142 MB | 59 MB | 201 MB | 6,3 s |

- **C reduz o índice em 76%** e o tempo de `INSERT` em 52% em relação ao modelo
  dado.
- **B** (manter o autor na chave) perde a maior parte do ganho, e o autor não é
  necessário para identificar o comentário.
- **D perde para C.** Como o `seq` depende do vídeo, o par `(id_video, seq)`
  precisa ser único de qualquer jeito; o id próprio só acrescenta uma coluna e um
  segundo índice. Além disso, um contador global somaria todos os comentários do
  mundo num número só, gerado por uma sequence central. Com a chave dependente, o
  limite é por vídeo: 2,15 × 10^9 comentários em cada um, 136 vezes o recorde
  mundial.

**Como o `seq` é gerado.** Uma sequence global não serve, porque numeraria todos
os vídeos juntos. O trigger T3 calcula `max(seq) + 1` do vídeo, com uma trava na
linha do vídeo para que duas inserções simultâneas não gerem o mesmo número
(seção 8).

**Limitações.** A medição usou dados sintéticos, uma execução, tabela sem FKs e
sem concorrência; vale a comparação entre as variantes. Se `Comentario` passar de
centenas de milhões de linhas, o próximo passo é particionar por
`HASH (id_video)`; a chave já contém a coluna de partição, como o PostgreSQL
exige.

### 5.5 Doação e formas de pagamento

**Decisão.** `Doacao` tem chave `(id_video, seq_comentario, seq_pg)` e FK para
`Comentario (id_video, seq)`. As quatro formas de pagamento (`BitCoin`,
`PayPal`, `CartaoCredito`, `MecanismoPlat`) têm chave
`(id_video, seq_comentario, seq_doacao)` e FK para `Doacao`.

**Por quê.** A doação é fraca em relação ao comentário, um nível abaixo da lógica
da seção 5.4. O autor não entra na chave porque já é determinado pelo comentário
(seção 3.3). As colunas sequenciais são `INTEGER`, e a chave fecha em 24 bytes
sem desperdício de alinhamento (seção 4.4).

### 5.6 Moeda: chave natural mantida

**Decisão.** `Conversao` continua com a chave natural `moeda`, o código ISO 4217
de 3 letras.

**Por quê.** É curta, estável, imutável e já é o identificador usado no mundo
real (USD, BRL, EUR). A tabela é pequena; trocar por uma chave artificial não
reduziria nada. Vários países compartilham a mesma moeda (o euro), uma relação
1:N correta: `Pais.moeda` não é único.

## 6. Constraints

**Exigência comum a esta seção.** Item mandatório 2: `UNIQUE` e `NOT NULL`
usados com critério, a partir das regras do minimundo.

### 6.1 Identidade da plataforma: nome e empresa fundadora

**Decisão.** `UNIQUE (nome, empresa_fund)` em `Plataforma`.

**Por quê.** O minimundo identifica a plataforma pelo número e não diz que o nome
é único. Duas linhas com o mesmo nome e a mesma fundadora seriam o mesmo fato
duplicado. A fundadora foi escolhida, e não a responsável, porque é um fato
histórico que não muda; a responsável pode mudar por venda ou fusão, e colocá-la
na constraint faria uma troca de dono parecer outra plataforma. As duas colunas
são `NOT NULL`, então não há a brecha de vários nulos do `UNIQUE`. Como `nome`
vem primeiro, o mesmo índice atende buscas por nome.

**Alternativas.** `UNIQUE (nome)` proibiria homônimos de fundadoras diferentes,
uma regra que o mundo real não garante.

**Limitações.** É mais fraca que `UNIQUE (nome)`: aceita duas plataformas de mesmo
nome com fundadoras diferentes. Diferencia maiúsculas de minúsculas
(`Twitch` ≠ `twitch`).

### 6.2 Empresa e moeda: nome único, sem combinações inúteis

**Decisão.** `UNIQUE (nome)` em `Empresa`, `Conversao` e `Pais`. Não foram
criados `UNIQUE (nome, nome_fantasia)` em `Empresa` nem `UNIQUE (moeda, nome)` em
`Conversao`.

**Por quê.** Duas linhas com o mesmo nome seriam duplicata. As combinações foram
descartadas porque um conjunto de colunas que já contém uma coluna única nunca é
violado: a constraint não protegeria nada e só gastaria um índice. Em `Empresa`,
`nome_fantasia` ainda é nulável, e o par com fantasia nula nunca violaria a
regra.

A identidade real de uma empresa é o identificador nacional no país (CNPJ, EIN
etc.), por isso `EmpresaPais` tem `UNIQUE (ddi_pais, id_nacional)` com
`id_nacional NOT NULL`.

**Alternativas.** Para aceitar razões sociais repetidas com nomes fantasia
diferentes, seria preciso **remover** o `UNIQUE (nome)` e usar o par
`(nome, nome_fantasia)` com `NULLS NOT DISTINCT` (PostgreSQL 15+), para que a
fantasia nula também conte. Não foi feito: a unicidade do nome é a regra mais
simples, e a identidade da empresa já está no identificador nacional.

### 6.3 Usuário: e-mail e telefone únicos, cada um sozinho

**Decisão.** `UNIQUE (email)` e `UNIQUE (telefone)` separados.

**Por quê.** O e-mail identifica a conta na prática. O telefone serve para a
"validação em duas vias" do minimundo, e um telefone ligado a uma só conta é
coerente com essa finalidade. Um `UNIQUE (email, telefone)` composto só barraria
o par idêntico e deixaria o mesmo e-mail com telefones diferentes.

**Limitações.**

- `telefone` continua nulável, e o `UNIQUE` aceita vários nulos: o grupo não quis
  obrigar o telefone em contas antigas. É uma brecha conhecida.
- `UNIQUE (email)` trata `A@x.com` e `a@x.com` como diferentes; a alternativa
  seria um índice único sobre `lower(email)`.
- No mundo real, telefones são compartilhados (família). A unicidade é uma regra
  do grupo, não do domínio.
- São dois índices a mais, atualizados em todo cadastro.

### 6.4 Demais `UNIQUE`

| Constraint | Regra de negócio |
|---|---|
| `UNIQUE (nick)` em `Usuario`, `UNIQUE (nome, nro_plataforma)` em `Canal`, `UNIQUE (id_canal, titulo, dataH)` em `Video` | A chave natural que deixou de ser chave primária continua identificando a linha (seção 5) |
| `UNIQUE (nro_plataforma, nro_usuario)` em `PlataformaUsuario` | O número de usuário identifica a conta dentro da plataforma ("pode ser diferente em cada plataforma") |
| `UNIQUE (ddi_pais, nro_passaporte)` em `StreamerPais` | O número do passaporte é único no país emissor |
| `UNIQUE (TxID)` em `BitCoin` | O TxID é o hash da transação na blockchain e não se repete |
| `UNIQUE (IdPayPal)` em `PayPal` | O IdPayPal identifica um pagamento |

`TxID` e `IdPayPal` custam um índice cada em tabelas que crescem com as doações
(1,9% dos comentários na carga); o grupo aceitou porque pagamento duplicado é um
erro que o banco deve barrar. O índice de `PlataformaUsuario` fica numa tabela
de ~10^6 linhas (856 mil na carga), mas de escrita rara: uma conta por
plataforma por usuário.

### 6.5 `NOT NULL`

| Coluna | Trecho do minimundo | Quem depende |
|---|---|---|
| `Usuario.pais_residencia` | "um país de residência" | Conversão da doação (T11) e dos membros (V2). Com a coluna obrigatória, todo usuário tem moeda, e ninguém precisa ser tratado como USD por falta de país |
| `Plataforma.data_fund` | "uma data de fundação" | Coerência temporal (T7) |
| `Canal.data` | "data de início" | Coerência temporal (T7) |
| `NivelCanal.gif` | "para cada nível existe um arquivo .gif" | — |
| `Video.titulo`, `Video.dataH` | Identificam o vídeo | Deixaram de ser chave primária, que era o que as tornava obrigatórias |
| `EmpresaPais.id_nacional` | Identifica a empresa no país | `UNIQUE (ddi_pais, id_nacional)` |

### 6.6 `CHECK`

**Decisão.**

| Coluna | Regra | Motivo |
|---|---|---|
| `Conversao.fator_conver` | `> 0` | Fator zero ou negativo anula ou inverte a conversão |
| `Patrocinio.valor`, `NivelCanal.valor`, `Doacao.valor` | `> 0` | Não existe patrocínio, nível pago ou doação de valor zero (vale também para doação recusada) |
| `Comentario.seq`, `Doacao.seq_pg`, `Doacao.seq_comentario`, `MecanismoPlat.seq_plataforma` | `> 0` | Numeração a partir de 1 |
| `Video.duracao` | `> INTERVAL '0'` | Vídeo tem duração |
| `Plataforma.qtd_users`, `Canal.qtd_visualizacoes`, `Video.visu_simul`, `Video.visu_total` | `>= 0` | Contadores podem ser zero: canal novo não tem visualizações |
| `Video` | `visu_simul <= visu_total` | O pico simultâneo não passa do total |
| `Canal.tipo`, `Doacao.status` | Domínios do enunciado | Os `CHECK` que o enunciado já trazia, agora com nome explícito |

**Por quê.** `CHECK` não cria índice: custa só a avaliação da expressão na
escrita. Ids `IDENTITY` não precisam de `CHECK`, porque começam em 1. Um `CHECK`
com coluna nula passa (o resultado é desconhecido), então colunas nuláveis como
`duracao` só são validadas quando preenchidas.

### 6.7 Constraints e o teto de índices

Os índices criados por `PRIMARY KEY` e `UNIQUE` são consequência de constraints
de integridade e **não contam** no teto de 5 índices de apoio do item mandatório
4 (seção 11).

## 7. Moeda e receitas

**Exigência.** As consultas 5, 6, 9, 10 e 11 pedem valores em dinheiro, e as
consultas 9 a 11 comparam canais entre si. O minimundo diz que o patrocínio é
"em dólares americanos" e que cada moeda tem um fator "para conversão do valor
da moeda estrangeira para dólares americanos", mas não diz a moeda do nível de
membro nem da doação. O professor orientou: patrocínio sempre em dólar, porque
vem de um contrato externo; doação convertida pela moeda do país de residência
do usuário, e converter na gravação ou na consulta são as duas formas corretas.

### 7.1 Moeda de cada receita

**Decisão.**

| Receita | Moeda na origem | Quando converte para USD | Valor resultante |
|---|---|---|---|
| Patrocínio | USD | Não converte | Contratual |
| Doação | Moeda do país de residência de quem comentou | No `INSERT`, pelo trigger T11 | **Histórico**: o que o canal recebeu no dia |
| Membros | Moeda do país de residência do membro | Na consulta, pela view V2 | **Corrigido**: quanto vale hoje |

O caminho da conversão da doação é `Comentario.id_usuario` →
`Usuario.pais_residencia` → `Pais.moeda` → `Conversao.fator_conver`. O T11
multiplica o valor pelo fator e grava em USD com duas casas.

### 7.2 Por que o valor do membro está na moeda do país do membro

O usuário é a única entidade da inscrição ligada a um país, então o grupo
interpretou que o valor do nível está na moeda do país de residência do membro.
As leituras alternativas seriam o valor já estar em USD (como o patrocínio) ou
na moeda do país do streamer; qualquer uma mudaria a conversão dos itens 6, 9 e
11, que mudam juntos. A conversão é feita **por membro, antes de somar**: somar
primeiro misturaria moedas, e o ranking entre canais deixaria de ser comparável.

### 7.3 Por que a doação é histórica e o membro é corrigido

O professor comentou que o valor corrigido diz mais para escolher que canal
patrocinar, mas que gravar o histórico também está certo e, segundo ele, é o que
a maioria dos grupos faz. A doação ficou com o valor histórico:

1. **A doação é um evento passado; o membro é uma receita recorrente.** O valor
   corrigido dos membros é uma projeção: com o câmbio de hoje, é quanto o canal
   recebe no próximo mês, que é o que interessa a quem vai patrocinar. A doação
   já aconteceu, e o fato é quanto entrou no dia.
2. **`Conversao` não guarda histórico de câmbio.** Converter a doação na consulta
   reprecificaria doações de anos atrás com o câmbio de hoje, e o valor do dia
   nunca mais poderia ser recuperado.
3. **O mundo real faz assim.** O YouTube converte a receita do criador pelo
   câmbio do período do pagamento (a média diária do mês) e não reavalia os meses
   já pagos.
4. **Custo das consultas.** Os itens 4, 7, 10 e 11 somam o valor direto, sem
   juntar as doações com `Usuario`, `Pais` e `Conversao`.

**Limitações.**

- O valor em moeda local se perde: não se pode criar coluna (seção 3.1), e
  `Conversao` não guarda o câmbio do dia para reconstruí-lo.
- Doação e membros ficam em critérios diferentes (histórico e corrigido). Em USD,
  os dois continuam comparáveis; a diferença é o câmbio.
- Uma doação que vire menos de US$ 0,01 é rejeitada pelo T11, porque a coluna tem
  duas casas.
- Como o T11 só existe depois da carga, o seed sorteia o valor em moeda local e
  converte exatamente como o trigger faria.

### 7.4 Critérios comuns das consultas de receita

| Critério | Por quê |
|---|---|
| Doação recusada não conta | O status pode ser `recusado`, `recebido` ou `lido`; doação recusada não foi recebida. Vale para os itens 4, 7, 10 e 11 e está concentrado na view V1 |
| Só patrocínios e inscrições existentes | O minimundo não guarda histórico de patrocínio nem de membros |
| `k` nulo devolve todos os canais | Comportamento do `LIMIT NULL` do PostgreSQL; um top-k sem `k` lista tudo |
| Canal sem receita não aparece | As consultas listam quem recebe |
| Faturamento (item 11) soma as fontes separadas | Cada fonte é agregada sozinha e só depois somada por canal. Juntar as três tabelas num `JOIN` multiplicaria as linhas de uma fonte pelas da outra e inflaria os valores |

Nos dados da carga, o patrocínio domina o faturamento, então o ranking do item
11 fica muito parecido com o do item 8.

## 8. Triggers

**Exigência.** Item mandatório 5 e especificação 3: "triggers para manter a
consistência do BD (todas as necessárias via requisitos)". O professor pediu os
triggers num arquivo separado, executado depois da carga, "para não ter problema
na hora de fazer inserção", e confirmou que `qtd_visualizacoes` é a soma bruta
das visualizações dos vídeos e que `qtd_users` segue o mesmo raciocínio.

### 8.1 Os onze triggers

**Decisão.** Cada trigger nasce de uma regra do minimundo ou do diagrama ER que
não cabe em `PRIMARY KEY`, `UNIQUE`, `FOREIGN KEY` ou `CHECK` (`triggers.sql`).

| ID | Regra | Origem | Tabela e evento | Comportamento |
|---|---|---|---|---|
| T1 | `Canal.qtd_visualizacoes` = soma de `visu_total` dos vídeos | Atributo derivado do modelo | `Video`: `AFTER INSERT`, `UPDATE` e `DELETE`, por comando | Soma a diferença por canal; trocar o vídeo de canal subtrai de um e soma no outro |
| T2 | `Plataforma.qtd_users` = número de contas | Atributo derivado do modelo | `PlataformaUsuario`: `AFTER INSERT`, `UPDATE` e `DELETE`, por comando | +1 ou −1 por conta, por plataforma |
| T3 | `seq` do comentário | "Número sequencial que depende do vídeo" | `Comentario`: `BEFORE INSERT` | Se o `seq` vier nulo, usa `max(seq) + 1` do vídeo |
| T4 | `seq_pg` da doação | "Depende do vídeo, do usuário e do comentário" | `Doacao`: `BEFORE INSERT` | Se vier nulo, usa `max(seq_pg) + 1` do comentário |
| T5 | `seq_plataforma` do mecanismo da plataforma | "Depende do usuário, do comentário e da plataforma" | `MecanismoPlat`: `BEFORE INSERT` | Sequência por usuário e plataforma; exige conta na plataforma |
| T6 | Doação em exatamente uma das quatro formas | Especialização disjunta ("d" no ER) e total ("pode ser feita de quatro formas") | Formas: `BEFORE INSERT/UPDATE` (disjunta); `Doacao` (`AFTER INSERT`) e formas (`AFTER DELETE/UPDATE`): trigger de constraint adiado (total) | Rejeita a segunda forma; no `COMMIT`, rejeita doação sem forma |
| T7 | Fundação ≤ canal ≤ vídeo ≤ comentário | Coerência temporal (regra do grupo) | `Comentario`, `Video` e `Canal`: `BEFORE INSERT/UPDATE` da data ou do pai; `Plataforma`: `BEFORE UPDATE` de `data_fund` | Confere as datas nos dois sentidos: ao inserir o filho e ao alterar o pai |
| T8 | No máximo 5 níveis por canal | "Existem cinco níveis de membros" | `NivelCanal`: `BEFORE INSERT` e `UPDATE` de `id_canal` | Rejeita o sexto nível |
| T9 | Dono de canal e participante de vídeo são streamers | Especialização de `Usuario` no ER (streamer tem passaporte) | `Canal` e `Participa`: `BEFORE INSERT/UPDATE` de `id_streamer`; `StreamerPais`: `AFTER DELETE/UPDATE` | Exige passaporte; impede apagar o último passaporte de quem tem canal |
| T10 | O dono tem conta na plataforma do canal | Relacionamento "tem conta" do ER | `Canal`: `BEFORE INSERT/UPDATE`; `PlataformaUsuario`: `BEFORE DELETE/UPDATE` | Exige a conta; impede apagá-la enquanto houver canal |
| T11 | Doação em USD | Seção 7 | `Doacao`: `BEFORE INSERT` | Converte o valor pela moeda do país de residência |

A regra "sem histórico de patrocínios e membros" não precisa de trigger:
resolve-se apagando a linha (`DELETE`).

### 8.2 Como foram implementados, e por quê

- **T1 e T2 por comando, e não por linha.** Usam tabelas de transição
  (`REFERENCING NEW/OLD TABLE`): um `INSERT` de mil vídeos do mesmo canal faz um
  único `UPDATE` no canal, e não mil. O PostgreSQL não aceita tabela de transição
  com mais de um evento nem com `UPDATE OF`, então são três triggers por
  tabela. As linhas são atualizadas em ordem de id, para que comandos
  simultâneos travem na mesma ordem e não entrem em deadlock.
- **T3, T4 e T5 com trava na linha "pai".** Antes do `max + 1`, o trigger trava o
  vídeo, o comentário ou a conta (`SELECT … FOR UPDATE`). Sem a trava, duas
  inserções simultâneas calculariam o mesmo número, e a segunda falharia pela
  chave. O custo é que inserções no mesmo vídeo entram em fila; em vídeos
  diferentes, não se bloqueiam. O `max` usa o prefixo da chave primária.
- **T6 com trigger de constraint adiado.** "Ao menos uma forma" só pode ser
  conferido no fim da transação, depois de a doação e a forma terem sido
  inseridas.
- **T8 e T9 com travas mais leves** (`FOR NO KEY UPDATE` e `FOR KEY SHARE`), para
  não bloquear as verificações de FK de outras transações.
- **T10 como trigger, e não FK.** Daria para declarar uma FK de `Canal` para
  `PlataformaUsuario`, mas isso mudaria os relacionamentos do modelo dado
  (seção 3.1).
- **T10 não vale para comentário e inscrição.** Conferir a conta a cada
  comentário custaria uma busca a mais na maior tabela.
- **T5 sem índice próprio.** Usuário e plataforma não estão em `MecanismoPlat`:
  o `max` percorre `MecanismoPlat` e confere cada linha pela chave de
  `Comentario` e de `Video`, e o custo cresce com essa tabela. É escrita rara;
  não vale gastar uma das 5 vagas de índice. Num volume real, o próximo passo
  seria um índice de apoio.
- **Mensagens de erro** usam os códigos de violação de integridade (23xxx), para
  que a aplicação as trate como as das constraints. O nome de cada trigger leva o
  número (`trg_t04_…`), o que também fixa a ordem dos triggers da mesma tabela,
  que o PostgreSQL dispara em ordem alfabética (T4 antes de T11 em `Doacao`).

### 8.3 Triggers depois da carga

Como o professor orientou, `triggers.sql` roda depois do `seed.sql`. Os triggers
por linha pesariam milhões de vezes durante a carga. Por isso o seed obedece
sozinho às mesmas regras, calcula os atributos derivados no próprio `INSERT` e
confere tudo no fim: se alguma regra falhar, a carga inteira é desfeita.

### 8.4 Testes

Cada trigger foi testado com um caso aceito e um rejeitado, mais a conferência
dos derivados depois de `INSERT`, `UPDATE` e `DELETE`, numa transação desfeita
com `ROLLBACK`: 37 casos, todos corretos. O script está na tag `v1.1.0`
(`testes_triggers.sql`). O `tests.sql` da entrega só chama as functions e não
altera dados.

### 8.5 Custo do T2: atualizar `qtd_users` a cada conta nova

O modelo diz que `qtd_users` "requer atualização periódica", e o professor pediu
trigger para os dois derivados. O grupo escolheu o trigger **sabendo do custo**:
toda conta nova atualiza a linha da plataforma.

**Por que é aceitável neste banco:**

| Fato | Por que favorece o trigger |
|---|---|
| `Plataforma` tem 28 linhas, e nome, empresas e data quase nunca mudam | O T2 é o único que escreve nessas linhas, sem disputa com outras atualizações |
| A tabela cabe numa página de 8 KB | Fica sempre em cache; o `UPDATE` não lê disco |
| `qtd_users` não tem índice | A atualização é HOT: a nova versão fica na mesma página, sem mexer em índice |
| Criar conta é raro: uma vez por plataforma por usuário | Na carga são 856 mil contas, contra 1,25 milhão de vídeos e 5 milhões de comentários |
| O trigger é por comando | Um crawler que insere 1 milhão de contas num comando faz no máximo 28 `UPDATE`s |

**O que aconteceria com volume real (estimativas, não medidas):**

| Efeito | Conta | Consequência |
|---|---|---|
| Linha disputada | Todo cadastro numa plataforma trava a mesma linha até o `COMMIT`. Com commit de 1 a 5 ms, o teto é de ~200 a 1.000 contas por segundo, inseridas uma a uma, por plataforma | O TikTok chegou a ~1,6 bilhão de usuários em ~7 anos, ~7 contas por segundo. O Threads teve 100 milhões de cadastros em 5 dias, ~230 por segundo, o que já encosta no teto |
| Comparação com o T1 | O T1 espalha as escritas por 36 mil canais; o T2 concentra todos os cadastros em 28 linhas | A disputa é muito maior no T2 |
| Versões mortas | Cada `UPDATE` cria uma nova versão da linha. Uma transação longa, como o refresh da V3 (~27 s), impede a limpeza: a 230 cadastros por segundo, são ~6.200 versões mortas numa página que comporta ~100 | `Plataforma` cresce de 1 para dezenas de páginas, e o autovacuum dispara a todo ciclo |
| Deadlock | Dentro de um comando, as plataformas são atualizadas em ordem | Transações com comandos separados em ordens opostas ainda podem travar uma à outra |
| Leitura | Só o item 12 lê `qtd_users`, e só como contexto | Paga-se custo em toda escrita para manter exato um valor pouco lido |

**Alternativas comparadas:**

| Opção | Exatidão | Custo na escrita | Cabe na regra do trabalho? |
|---|---|---|---|
| Trigger por linha | Exata | 1 `UPDATE` por conta, mesmo em lote | Sim, mas é a pior |
| **Trigger por comando (adotado)** | Exata | 1 `UPDATE` por plataforma por comando | Sim |
| Recontagem periódica (procedure agendada) | Defasada até a próxima execução | Zero. Hoje lê ~3.300 páginas em milissegundos; em escala real, ~85 GB de índice para os 2,7 bilhões de contas do YouTube, de 1 a 2 minutos por execução | Sim; é o que o modelo sugere |
| Contar na consulta, sem guardar | Exata | Zero | Não: remove o atributo derivado |

**Decisão.** Com carga em lote e pouca escrita em contas, fica o trigger por
comando: o custo se dilui no lote, a plataforma não tem outro escritor e o valor
fica sempre exato. Num sistema real, com cadastros um a um e transações longas, a
recontagem periódica seria melhor, e a defasagem não afetaria o item 12. A troca
vale quando a maior plataforma chegar a centenas de cadastros por segundo.

### 8.6 Limitações dos triggers

- A concorrência não foi testada com sessões simultâneas; as travas seguem o
  raciocínio acima.
- O T7 não sabe quando uma plataforma encerrou (o Mixer acabou em 2020): o modelo
  não tem essa coluna.

## 9. Views

**Exigência.** Item mandatório 3 e especificação 1: até 5 visões, virtuais e
materializadas, cada uma justificada.

### 9.1 As quatro views

**Decisão.** Duas virtuais e duas materializadas (`views.sql`).

| View | Tipo | Conteúdo | Atende | Por quê | Medido |
|---|---|---|---|---|---|
| V1 `vw_doacao_recebida` | Virtual | Doações não recusadas, em USD, com canal e plataforma | Itens 4, 7 e a V4 | Concentra num lugar só a regra de status e o caminho doação → vídeo → canal | Mesmo patamar da consulta direta |
| V2 `vw_inscricao_usd` | Virtual | Inscrições com o valor do nível em moeda local e em USD | Item 6 e a V4 | Concentra a conversão dos membros, que se repetia nos itens 6, 9 e 11 | Idem |
| V3 `mv_interacoes_video` | Materializada | Comentários online, offline e total por vídeo | Itens 2 e 3 | `Comentario` é a maior tabela (5 milhões de linhas), e contá-la dominava o tempo. Contagem de comentários tolera atraso | Item 3 com filtro: 7,5 s → 0,22 s (33×) |
| V4 `mv_faturamento_canal` | Materializada | Patrocínio, membros, doações e total em USD por canal | Itens 8 a 11 | O top-k ordena por um valor agregado, e nenhum índice nas tabelas base atende isso. Para escolher patrocínio, atraso de horas é aceitável | Item 10: 0,73 s → 28 ms (26×) |

**Por que as virtuais são virtuais.** Uma view virtual é só uma consulta salva: o
planejador a expande dentro da consulta que a usa. Assim, os filtros por canal ou
plataforma descem até os índices das tabelas base. A view virtual não acelera por
si; vale pela regra centralizada. O ganho de tempo vem das materializadas.

### 9.2 Atualização das materializadas

**Decisão.** Atualização periódica, por um agendador externo (cron ou pg_cron),
com `CALL steam_do_bedo.sp_refresh_views()`, que faz
`REFRESH MATERIALIZED VIEW CONCURRENTLY` nas duas sem bloquear as leituras.

**Por quê.** O refresh da V3 leva 12 s (comum) a 23–29 s (concorrente), e o da
V4, de 1 a 2 s. Recontar a cada comentário, por trigger, custaria mais que a própria
consulta.

**Limitações.** Os itens 2, 3 e 8 a 11 refletem o último refresh; os demais são
exatos.

### 9.3 A quinta view: medida e descartada

Uma V5 com streamers e canais por plataforma (item 12) foi medida. Materializada,
o item 12 cairia de ~70 para ~7 ms numa resposta de 28 linhas, mas deixaria de
ser exato até o próximo refresh e seria mais um refresh agendado. Virtual, não
acelera nada. Ficaram 4 de 5 views (detalhes na seção 10.4).

### 9.4 Índices das materializadas e o teto de 5

O `REFRESH … CONCURRENTLY` exige um índice `UNIQUE` em cada materializada. O
grupo decidiu que **esses dois índices contam no teto de 5 índices de apoio**,
para não deixar dúvida na avaliação (seção 11).

## 10. Consultas

**Exigência.** Item mandatório 6 e especificação 4: functions parametrizadas
para as consultas 1 a 12, com filtro opcional quando o enunciado pede.

### 10.1 Padrão das functions

**Decisão.** Uma function por consulta em `functions.sql`, com o filtro opcional
como parâmetro `DEFAULT NULL` (ou `k` nos top-k). O `tests.sql` chama cada uma
em vários cenários.

| Escolha | Por quê |
|---|---|
| Itens 1 a 11 em `LANGUAGE sql STABLE` | O planejador expande a function dentro da consulta que a chama. Com o parâmetro constante, o filtro opcional `p IS NULL OR col = p` vira `col = p` e pode usar índice |
| Item 12 em `plpgsql` | A posição global obriga a agregar todas as plataformas antes de filtrar, então a expansão não traria ganho; e o plpgsql permite rejeitar parâmetros inválidos com mensagem clara |
| Agregar por id e juntar nomes no fim | As chaves são artificiais (seção 5); o nome e o nick só entram na saída |
| Consultas que listam canais devolvem nome **e** plataforma | O nome do canal só é único por plataforma. Uma versão anterior do item 5 agrupava pelo nome e juntava canais homônimos de plataformas diferentes |
| `DROP FUNCTION` antes de criar | `CREATE OR REPLACE` não troca a lista de parâmetros nem o tipo de retorno |

### 10.2 Premissas de cada consulta

| Item | Function | Filtro opcional | Lê | Premissas |
|---|---|---|---|---|
| 1 | `sp_obter_streamers_com_maior_qtd_videos_publicados` | plataforma | `Video`, `Canal` | Conta os vídeos dos canais do streamer e soma as visualizações |
| 2 | `sp_obter_videos_mais_comentados` | canal | V3 | Vídeos sem comentário aparecem com zero; usada com `LIMIT` |
| 3 | `sp_obter_canais_por_qtd_total_interacoes` | streamer | V3 | Interações = comentários online + offline; canal sem vídeo aparece com zero |
| 4 | `sp_obter_canais_pela_media_doacoes_por_comentario` | plataforma | V1 | Soma as doações de cada comentário (pode haver mais de uma) e tira a média por canal; só doações não recusadas |
| 5 | `sp_obter_canais_patrocinados_com_valores_por_empresa` | empresa | `Patrocinio` | Valor em USD, como no contrato |
| 6 | `sp_obter_qtd_canais_e_gasto_mensal_por_usuario` | usuário | V2 | Valor mensal das inscrições vigentes, em moeda local e em USD |
| 7 | `sp_obter_canais_com_doacoes_recebidas` | canal | V1 | Só doações não recusadas |
| 8 a 11 | `sp_obter_top_k_canais_por_*` | `k` | V4 | `k` nulo devolve todos; critérios da seção 7.4 |
| 12 | `sp_obter_top_k_plataformas_por_streamers_e_canais` | `k`, plataforma | `Canal` | Seção 10.4 |

Cada consulta ordena pelo valor que responde à pergunta, decrescente, e desempata
por um nome, para a saída ser determinística: o item 6 ordena pelo gasto mensal
em USD e desempata pelo nick; os itens 8 a 11 ordenam pelo valor da receita e
desempatam pelo nome do canal.

### 10.3 Consultas reescritas antes dos índices

**Exigência.** O professor orientou deixar as consultas "o melhor que você
conseguir" antes de criar índices.

**Decisão.** Filtrar antes de agregar nas consultas com filtro, e ler a V3 nos
itens 2 e 3.

Medição a frio, mediana de 5, sem índices de apoio (páginas lidas entre
parênteses; os planos estão no [benchmark.md](benchmark.md), seções 2 e 3):

| Consulta | Original (agrega tudo, depois filtra) | Reescrita direta (filtra antes) | Final (sobre a V3) |
|---|---:|---:|---:|
| Item 2, sem filtro | 8.435 ms (138.917) | 17.541 ms (214.491) | 10.242 ms (32.230) |
| Item 2, com filtro por canal | 3.931 ms (114.281) | 1.112 ms (8.217) | 631 ms (5.156) |
| Item 3, sem filtro | 6.784 ms (85.227) | 42.546 ms (85.233) | 1.006 ms (20.470) |
| Item 3, com filtro por streamer | 7.492 ms (114.986) | 997 ms (6.241) | 224 ms (1.689) |

| Consulta (top-k) | Direta nas tabelas | Sobre as views virtuais V1 e V2 | Sobre a V4 |
|---|---:|---:|---:|
| Item 10, k = 10 | 732 ms (171.696) | 756 ms (171.699) | 28 ms (952) |
| Item 11, k = 10 | 3.279 ms (185.222) | 2.712 ms (185.322) | 37 ms (952) |

**Por quê.**

1. **Filtrar antes de agregar** já reduz o item 2 filtrado em 3,5× e o item 3
   filtrado em 7,5×: os comentários passam a ser lidos só dos vídeos do canal, pela
   chave `(id_video, seq)`.
2. **Sem filtro, a reescrita direta piora.** Agrupar 5 milhões de linhas por vídeo
   estoura a memória de trabalho (`work_mem` de 4 MB) e ordena em disco. Por isso
   os itens 2 e 3 leem a V3, que já tem a contagem por vídeo.
3. **O item 2 sem filtro continua caro** (~10 s) em qualquer forma, mesmo lendo
   4 vezes menos páginas na V3: ele devolve e ordena 1,25 milhão de vídeos, e a
   ordenação vai para o disco. Na prática é usado com `LIMIT`, e o planejador
   ordena só as primeiras linhas, em memória.
4. **O item 3 tem dois ramos excludentes** (com e sem filtro). Com o parâmetro
   constante, o planejador descarta o ramo que não serve: sem filtro, agrega a V3
   numa passada (3,0 → 1,5 s a quente); com filtro, usa o índice.
5. **As views virtuais não aceleram por si.** A consulta direta e a virtual têm o
   mesmo plano e leem as mesmas páginas; a diferença de tempo entre elas está
   dentro da variação entre repetições. A V4 é que muda a ordem de grandeza.

### 10.4 Item 12 (desafio): top-k plataformas por streamers E canais

**Exigência.** "Listar as top-k plataformas pela quantidade de streamers **E**
canais. Dar a opção de filtrar por plataforma como parâmetro opcional." O
minimundo existe para responder "questões sobre o alcance de público", e o
professor lembrou que o sistema serve para escolher o que patrocinar. A
interpretação foi decidida antes do código.

**Decisão 1: quem é "streamer da plataforma".** Quem é dono de ao menos um canal
nela, contado uma vez só. Medido na carga:

| Interpretação | YouTube | Twitch | Kick | Efeito |
|---|---:|---:|---:|---|
| **Dono de ao menos um canal na plataforma (escolhida)** | 10.092 | 3.036 | 1.252 | Conta quem publica ali |
| Streamer com conta na plataforma | 11.900 | 3.669 | 1.539 | Conta também quem só tem conta e nunca publicou; o ranking quase não muda (só Kuaishou e Snapchat trocam de posição) |
| Dono ou convidado (`Participa`) | 21.120 | 13.869 | 6.929 | Dobra ou quintuplica as plataformas de live: o convidado de uma colaboração já está no alcance do canal de quem publicou, e pode nem ter conta ali |

Ter só conta não gera público; quem publica é o canal. A contagem usa
`count(DISTINCT id_streamer)`: quem tem dois canais na mesma plataforma conta uma
vez como streamer e duas como canal.

**Decisão 2: o "E" sublinhado.** Ordena por streamers e desempata por canais.

| Alternativa | Por que não |
|---|---|
| Somar streamers e canais (ou ponderar) | Conta o mesmo criador duas vezes, porque todo streamer tem ao menos um canal; o peso seria arbitrário |
| Exigir os dois ao mesmo tempo (dominância de Pareto) | Não dá uma ordem total: se uma plataforma ganha em streamers e outra em canais, elas ficam incomparáveis, e não existe top-k |
| **Streamers, depois canais (escolhida)** | Cada streamer distinto é uma audiência própria; canais a mais do mesmo streamer ampliam pouco e servem para desempatar |

As duas quantidades são devolvidas e as duas entram na ordem: o "E" vale para a
listagem e para o critério.

**Decisão 3: empates no corte de k entram todos.** A posição é calculada com
`rank()`: plataformas iguais dividem a posição, e o corte é `posicao <= k`
(equivale a `FETCH FIRST k ROWS WITH TIES`).
Cortar no meio de um empate escolheria uma plataforma por um critério que o
enunciado não dá (o nome). Dentro do empate, a saída é ordenada pelo nome, para
ser determinística.

**Decisão 4: com filtro, a posição é a do ranking geral.** A posição é calculada
sobre todas as plataformas e só depois a plataforma pedida é selecionada. O Kick
aparece como 6º e o Rooter como 28º, e não como "1º de 1". Uma plataforma fora
do top-k volta mesmo assim, com `no_top_k = false`.

**Decisão 5: casos de borda.**

- Plataforma sem canal: aparece com zero streamers e zero canais, no fim.
- `k` nulo: todas as plataformas, como nos itens 8 a 11. `k < 1`: erro com
  mensagem clara (código 22023), porque um top-0 não é uma pergunta válida.
- Plataforma inexistente no filtro: erro, para não confundir com "plataforma sem
  canais", que devolve uma linha com zeros.
- `qtd_users` conta **contas**, de streamers ou não. É devolvido só como
  contexto, e não entra no critério.
- `qtd_visualizacoes` (soma das visualizações dos canais da plataforma) é
  devolvido como medida auxiliar de alcance.

**Saída.** A function recebe `p_k` e `p_nro_plataforma`, os dois opcionais, e
devolve `posicao`, `nro_plataforma`, `nome_plataforma`, `qtd_streamers`,
`qtd_canais`, `canais_por_streamer`, `qtd_visualizacoes`, `qtd_users` e
`no_top_k`. O `canais_por_streamer` é uma métrica auxiliar que reforça a
interpretação: uma plataforma com muitos canais por streamer tem menos
audiências independentes do que o número de canais sugere, e por isso o
critério principal é o streamer.

**Desempenho** (tempo de execução a frio / a quente, mediana de 5; páginas lidas
entre parênteses):

| Forma | Sem filtro (k = 10) | Filtro Kick | Filtro YouTube |
|---|---|---|---|
| Versão anterior, sem posição global | 55 / 46 ms (675) | 11 / 3,1 ms (672) | 16 / 8,6 ms (672) |
| Final, sem índices de apoio | 97 / 68 ms (1.434) | 72 / 55 ms (1.431) | 72 / 55 ms (1.431) |
| **Final, com os índices entregues** | 84 / 57 ms (1.446) | 111 / 71 ms (1.443) | 82 / 135 ms (1.443) |
| Final + índice de cobertura em `Canal` | 75 / 56 ms (1.464) | 75 / 57 ms (1.461) | 76 / 57 ms (1.461) |
| Sobre uma V5 virtual | 73 / 55 ms (1.381) | 71 / 55 ms (1.377) | 74 / 56 ms (1.377) |
| Sobre uma V5 materializada | 7,1 / 1,1 ms (299) | 7,0 / 1,2 ms (300) | 7,2 / 4,0 ms (300) |

- O custo é ler `Canal` inteira (665 páginas) e ordenar os ~36 mil canais para
  contar os streamers distintos; a posição global obriga a fazer isso com ou sem
  filtro. As outras ~770 páginas do total são do catálogo: compilar a function
  plpgsql e planejar a consulta interna a cada sessão nova. A versão anterior era
  mais barata com filtro porque lia só uma plataforma, mas respondia errado ("1º
  de 1").
- As diferenças entre as linhas "final" (como os 135 ms a quente com o YouTube)
  não vêm de mudança de plano: o plano e as páginas são os mesmos, e é variação
  entre repetições.
- **Índice de cobertura em `Canal`: descartado.** O plano não mudou, as páginas
  não caíram, e seria o sexto índice.
- **V5 materializada: descartada** pelos motivos da seção 9.3.

**Validação.**

| Caso | Resultado |
|---|---|
| Sem filtro, k = 10 | 10 linhas, YouTube em 1º (10.092 streamers), Kuaishou em 10º |
| Filtro numa plataforma grande (YouTube) | 1 linha, posição 1, dentro do top-k |
| Filtro numa plataforma pequena dentro do top-10 (Kick) | Posição 6, a do ranking geral |
| Filtro numa plataforma fora do top-10 (Rooter) | Posição 28, `no_top_k` falso |
| k maior que o total | As 28 plataformas, sem erro |
| Desempate e empate, montados numa transação desfeita | 1 streamer e 2 canais fica à frente de 1 streamer e 1 canal; duas plataformas sem canal empatam, e o corte inclui as duas |
| k = 0 e plataforma inexistente | Erro com mensagem clara |
| Contagem independente, por subconsultas | 28 plataformas, **0 divergências** |

**Limitações.** Na carga, cada streamer tem no máximo um canal por plataforma,
então canais = streamers e `canais_por_streamer` = 1,00 em todas as plataformas,
e o desempate só aparece no caso montado da validação. Gerar canais secundários
na carga (por exemplo, um canal de cortes) exigiria refazer a carga e toda a
medição; ficou como melhoria futura. O critério assume que a audiência vem de
criadores distintos; uma leitura por visualizações daria outra ordem (o TikTok
passaria o YouTube), por isso `qtd_visualizacoes` é devolvido ao lado.

## 11. Índices de apoio

**Exigência.** Item mandatório 4 e especificação 2: até 5 índices, cada um
justificado, considerando o overhead de inserção. O professor orientou escolher
pela similaridade dos predicados e pela distribuição dos dados (se o filtro
devolve quase tudo, como "todos americanos", o índice não ajuda), escolher o tipo
do índice pelo predicado (tipicamente secundários sobre parte da chave,
eventualmente hash) e medir com `EXPLAIN ANALYZE` antes e depois, cuidando do
cache.

### 11.1 O que conta no teto de 5

Os índices criados por `PRIMARY KEY` e `UNIQUE` são constraints e não contam
(seção 6.7). Os índices `UNIQUE` das views materializadas **contam**, por decisão
do grupo (seção 9.4). Sobram três vagas para as tabelas base.

### 11.2 Método

1. Inventário dos predicados das 12 consultas e das views: igualdade, faixa,
   junção, agrupamento, ordenação com `LIMIT`.
2. Distribuição de cada coluna (`pg_stats`) e seletividade real de cada filtro.
3. Tipo do índice conforme o predicado: B-tree em geral; hash testado nos de
   igualdade pura.
4. Medição a frio, com e sem o índice (seção 13), e do overhead de `INSERT`:
   300 mil linhas em ordem aleatória numa cópia da tabela, com e sem o índice,
   mediana de 3.

Os índices de apoio são criados depois da carga, no fim do `functions.sql`:
criar o índice sobre a tabela pronta é mais rápido que mantê-lo linha a linha.

### 11.3 Os cinco índices

| # | Índice | Atende | Ganho medido | Custo |
|---|---|---|---|---|
| 1 | `ux_mv_interacoes_video (id_canal, id_video)` | V3: itens 2 e 3 | Obrigatório para o refresh concorrente; com `id_canal` na frente, também atende o filtro por canal | 48 MB; só no refresh |
| 2 | `ux_mv_faturamento_canal (id_canal)` | V4: itens 8 a 11 | Obrigatório para o refresh concorrente | 0,5 MB; só no refresh |
| 3 | `idx_inscricao_id_membro` (B-tree) | Item 6 com filtro por usuário; FK ao remover usuário | A frio 155 → 4,5 ms (35×); páginas 4.135 → 123 | 10 MB; `INSERT` +63% |
| 4 | `idx_canal_id_streamer` (B-tree) | Item 3 com filtro por streamer; T9 e T10 ("tem canal?") | Páginas 1.689 → 1.027; a quente 11 → 1,8 ms | 0,7 MB; `INSERT` +18% |
| 5 | `idx_video_id_canal_cobertura (id_canal) INCLUDE (visu_total)` | Item 1 com filtro por plataforma | Kick: a frio 749 → 444 ms, a quente 261 → 21 ms; páginas 25.526 → 9.530 | 38 MB; `INSERT` +7% |

**Por que cada um vale o overhead:**

- **3 e 4 (igualdade muito seletiva).** Um membro tem ~1,9 inscrições e um
  streamer ~1,4 canal: o filtro devolve 0,0025% e 0,014% da tabela. A chave de
  `Inscricao` começa por `id_canal` e não serve para buscar por membro, e `Canal`
  não tinha nada em `id_streamer`: os planos varriam a tabela. São os "índices
  secundários sobre parte da chave" que o professor descreveu. O índice de
  `Inscricao` é o mais caro (+63%), mas inscrição é escrita rara e a busca por
  usuário é frequente.
- **5 (cobertura).** O item 1 conta vídeos e soma visualizações por canal. Os
  vídeos de um canal ficam espalhados pela tabela (a ordem física segue o id do
  vídeo, não o canal), e ler pela tabela custa uma página por vídeo. Com
  `visu_total` no `INCLUDE`, o plano lê só o índice (*index-only scan*).

### 11.4 Hash ou B-tree

Nos predicados de igualdade pura (índices 3 e 4), os dois tipos foram medidos. O
hash leu as mesmas páginas, teve o mesmo tempo e ficou **maior** (10,1 MB contra
8,4 MB no lote de `Inscricao`). Na escrita, nenhum venceu sempre: o hash inseriu
mais rápido em `Inscricao` (+27% contra +63%) e mais devagar em `Canal` (659
contra 330 ms), com rodadas muito dispersas. Ficou o B-tree, que lê o mesmo,
ocupa menos e também entrega as linhas em ordem.

### 11.5 Candidatos descartados

| Candidato | O que se mediu | Por que ficou de fora |
|---|---|---|
| `Canal (nro_plataforma)` | Uma primeira medição, com cache quente e dados uniformes, indicava ganho nas plataformas pequenas. Refeita a frio sobre a carga final, não teve ganho | `Canal` tem 665 páginas e é lida em milissegundos; o custo dos itens 1, 4 e 12 estava em `Video`, resolvido pelo índice 5 |
| `Inscricao (nick_membro)` | Era o índice 3 com a chave antiga | Com a chave artificial do usuário, virou `Inscricao (id_membro)` |
| `Comentario (id_video, coment_on)` | Ajudava o item 2 com filtro (−40%) quando a function agregava `Comentario` inteira | A causa era a forma da consulta; a reescrita e a V3 resolveram sem gastar um índice na maior tabela |
| `Doacao (status)` parcial | Não foi usado pelo planejador | `<> 'recusado'` devolve 90% das doações: predicado concentrado |
| `Doacao (id_video) INCLUDE (valor)` | Não foi usado; tempos no ruído | Os itens de doação leem a tabela inteira e agregam |
| `Patrocinio (id_canal)` | Não foi usado | Os itens 8 e 11 agregam a tabela toda; o item 5 com empresa já usa a chave, que começa por `nro_empresa` |
| Índices para o top-k da V4 | Não criados | Ordenar ~23 mil linhas custa milissegundos; seriam quatro índices, um por coluna de valor |
| `Comentario (id_usuario)` | Não criado | Nenhuma consulta filtra comentários por autor, e o índice pesaria na maior tabela |
| Colunas de data em `Comentario` | Não criado | Nenhuma consulta filtra comentários por data |
| `Participa (id_streamer)` | Não criado | Nenhuma consulta lê `Participa`; o item 1 conta só os vídeos dos canais do streamer |
| `Video (visu_total)` para ordenar | Não criado | Nenhuma consulta ordena vídeos por visualizações; elas só somam `visu_total` (por isso a coluna está no `INCLUDE` do índice 5) |
| `Canal (nro_plataforma, id_streamer) INCLUDE (qtd_visualizacoes)` | Não usado pelo planejador no item 12 | Seção 10.4; seria o sexto índice |

### 11.6 Consultas que não mudam com índice

Os itens sem filtro e o item 1 filtrado pelo YouTube (28% dos canais) leem quase
a tabela toda. O planejador mantém a varredura sequencial com ou sem índice: é o
caso "todos americanos" do professor.

### 11.7 Por que o volume importa para medir índice

O professor alertou que um bloco "cabe coisa para caramba" e que, com poucos
dados, o índice não faz diferença. O PostgreSQL lê páginas de 8 KB. Pelos
tamanhos reais da carga:

| Tabela | Linhas | Páginas | Linhas por página |
|---|---:|---:|---:|
| `Comentario` | 5.000.380 | 56.622 | ~88 |
| índice da chave de `Comentario` | 5.000.380 | 24.781 | ~200 |
| `Video` | 1.247.319 | 19.847 | ~63 |

- **Com 10.000 comentários** (o teto do enunciado), a tabela teria ~114 páginas
  (0,9 MB), e o índice, ~50 folhas e uma raiz. Tudo caberia folgado no
  `shared_buffers` de 128 MB, e varrer a tabela custaria quase o mesmo que usar o
  índice.
- **Com 5 milhões,** a tabela tem 464 MB, 3,5 vezes o `shared_buffers`, e a
  diferença entre ler 54 e 4.040 páginas do disco aparece no tempo.

### 11.8 Limitações

- A frio, o tempo de uma mesma consulta varia de 2 a 3 vezes entre repetições,
  com as mesmas páginas lidas; as páginas lidas são a métrica principal.
- O *index-only scan* do índice 5 depende do mapa de visibilidade: com inserção
  contínua em `Video`, o `VACUUM` precisa estar em dia.
- Os números absolutos dependem da máquina (Docker no Mac, SSD); vale a relação
  entre os cenários.

## 12. Dados

**Exigência.** Item mandatório 1: de 1.000 a 10.000 tuplas por tabela. O
professor disse que esse número é "só de referência", que não espera "10 mil
países", e pediu para "povoar o máximo que você conseguir, idealmente com
centenas de milhares de tuplas", com distribuição desbalanceada: canais com muito
mais vídeos que outros e vídeos com muito mais comentários que outros.

### 12.1 Volume

**Decisão.** Cerca de **8,7 milhões de registros** (`seed.sql`, escala 1):

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

**Por quê.** É o máximo viável no Docker local, na proporção do cenário da
seção 4, e é o volume que faz os índices fazerem diferença (seção 11.7). As
tabelas de referência ficaram no tamanho real, abaixo de 1.000: 154 moedas ISO
4217, 199 países e 28 plataformas reais; inflá-las com linhas fictícias deixaria
os dados irreais. `Empresa` tem 3.000 linhas: cerca de 70 empresas reais (donas
de plataformas e marcas que patrocinam streamers) e as demais fictícias.

O Docker local tem 5,8 GB de memória; na escala 1, o schema carregado ocupa
cerca de 1,5 GB.

### 12.2 Distribuições

| Escolha | Por quê |
|---|---|
| Mesmo cenário da seção 4, em escala reduzida | Plataformas de vídeo curto têm mais vídeos por canal; vídeos curtos têm só comentários offline e menos comentários por visualização |
| Popularidade de cada canal por distribuição lognormal (σ = 2,2) | Poucos canais concentram a audiência, como no mundo real. A popularidade comanda visualizações, quantidade de vídeos, membros e patrocínio |
| Comentários proporcionais a `visu_total^0,85`, com ruído (cauda longa) | O professor citou a relação: vídeo com muitas visualizações tem muitos comentários. O expoente menor que 1 faz um vídeo viral ter dezenas de milhares de comentários sem crescer na mesma proporção das visualizações; vídeo curto recebe 30% do peso por visualização |
| Autores de comentário e membros por lei de potência | Poucos usuários muito ativos |
| Países e plataformas com pesos de mercado | O YouTube concentra 28% dos canais |
| 5% dos usuários são streamers; 1,9% dos comentários trazem doação | Proporções plausíveis; uma versão anterior tinha 25% e 50% |
| Doação sorteada em moeda local e convertida como o T11 faria | O T11 não existe durante a carga (seção 7.3) |

### 12.3 Como a carga garante as regras

- **Obedece às regras dos triggers** e calcula os derivados no próprio `INSERT`,
  a partir de tabelas temporárias de preparação, sem `UPDATE` final e sem versões
  mortas de linha.
- **Uma transação só, banco vazio exigido.** Uma conferência no fim desfaz a carga
  inteira se alguma regra falhar.
- **Reprodutível:** semente fixa, sem paralelismo e fuso UTC. Mudam só os UUIDs
  dos vídeos (o `gen_random_uuid()` não obedece à semente) e o que deriva deles
  (TxID, IdPayPal e número do cartão). Os sorteios que dependem da ordem dos
  vídeos usam uma ordem fixa (data, canal e número do vídeo).
- **Escala ajustável** (`make setup ESCALA=0.1`): a carga completa leva de 6 a 9
  minutos; a escala 0,1 roda em menos de 1 minuto.

### 12.4 Cuidados descobertos ao validar a carga

- O autovacuum nunca analisa tabela temporária. Sem `ANALYZE` nelas, o
  planejador escolhia planos ruins nos sorteios e a carga travava; cada tabela
  temporária é analisada logo após a criação.
- O *Memoize* do planejador guardava o resultado de subconsultas com `random()`
  e repetia o mesmo sorteio (só 0,39% dos comentários ficavam com doação, e todos
  os vídeos tinham o mesmo convidado). A carga desliga esse recurso
  (`enable_memoize = off`).
- O sorteio do autor do comentário e do membro usa `LATERAL` pela chave única da
  tabela de contas: com `JOIN` comum, numa das cargas o planejador escolheu um
  plano que levou mais de 14 minutos só em `Comentario`.

### 12.5 Limitações

- O conteúdo é artificial (o professor aceitou). Pesos e taxas são do grupo,
  inspirados em ordens de grandeza reais, não em estatística oficial.
- A contagem da seção 12.1 é da carga usada no [benchmark.md](benchmark.md). Os
  UUIDs dos vídeos mudam a cada carga, e alguns sorteios dependem deles: por isso
  `Comentario`, `Participa`, `Doacao`, `MecanismoPlat` e as formas de pagamento
  podem variar algumas centenas de registros entre cargas. As demais tabelas não
  mudam.

## 13. Medição

**Exigência.** O professor pediu `EXPLAIN ANALYZE` antes e depois de cada
índice, alertando que "o SGBD tem cache": repetir a consulta faz ela vir da
memória e esconde o custo.

**Decisão.** Antes de **cada** medida a frio:

1. o container do Postgres é parado e reiniciado, o que esvazia o
   `shared_buffers`;
2. o cache de páginas da máquina virtual do Docker é limpo (`drop_caches`), porque
   ele sobrevive ao reinício do container;
3. uma única consulta é executada com `EXPLAIN (ANALYZE, BUFFERS)`.

Cada caso tem 5 repetições a frio e 5 a quente (depois de uma execução de
aquecimento), e o valor usado é a **mediana**. A medida só vale como fria se o
plano mostrar páginas lidas do disco (`shared read` > 0).

**Configuração fixa.** PostgreSQL 17 em Docker, `shared_buffers` de 128 MB e
`work_mem` de 4 MB (os padrões). Na sessão de medida, `jit = off` (a compilação
JIT soma um tempo variável) e um único processo por consulta, para os tempos
serem comparáveis. A medição usou um banco separado, carregado
com os arquivos da entrega, para não mexer nos dados do projeto.

**Por quê.** O cache esconde o custo: o item 2 com filtro leva 631 ms a frio e
11 ms a quente. Uma primeira rodada de medição, feita com cache quente e dados
uniformes, chegou a conclusões sobre índices que não se sustentaram a frio
(seção 11.5).

**Limitações.** O planejamento a frio inclui carregar o catálogo, por isso o
tempo de planejamento e o de execução são registrados separados, e os gráficos
usam o de execução. Os tempos absolutos dependem do disco da máquina. Os
resultados consolidados e os gráficos das comparações estão no
[benchmark.md](benchmark.md).

## 14. Ordem de execução e entrega

**Exigência.** O enunciado pede a entrega da DDL, dos dados, das rotinas, das
chamadas de teste e do documento de decisões. O professor pediu os triggers
separados, para não travar a inserção.

**Decisão.** A ordem de execução é:

```
ddl.sql → seed.sql → views.sql → functions.sql → triggers.sql → tests.sql
```

**Por quê.**

- **Triggers depois da carga:** orientação do professor; os triggers por linha
  pesariam milhões de vezes na carga, e o seed já obedece às regras (seção 8.3).
- **Views antes das functions:** as functions dependem delas, e as materializadas
  são preenchidas na criação, então precisam dos dados.
- **Índices de apoio depois da carga, no fim do `functions.sql`:** criar o índice
  sobre a tabela pronta é mais rápido que mantê-lo durante a inserção. O
  `ddl.sql` só tem os índices das chaves e dos `UNIQUE`.

O passo a passo (`make setup` e `make tests`, ou os comandos `psql` um a um) está
no [README.md](README.md).

| Arquivo pedido no Classroom | Arquivo do projeto |
|---|---|
| 1. DDL de construção das tabelas | `ddl.sql` |
| 2. PL/pgSQL: functions, triggers, views e outros | `views.sql`, `functions.sql` (com os índices de apoio no fim) e `triggers.sql` |
| 3. Dados para inserção | `seed.sql` (gera os dados; o arquivo é pequeno) |
| 4. Chamadas das consultas e functions para teste | `tests.sql` |
| 5. PDF de decisões | `decisoes_resumo.pdf` (gerado do `decisoes_resumo.md`), com este detalhamento como complemento |

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

# Stream do Bedo · Benchmark

Este arquivo reúne as comparações de desempenho que embasaram as decisões de
consultas, views e índices (seções 9 a 11 do
[decisoes_detalhamento.md](decisoes_detalhamento.md), resumidas no
[decisoes_resumo.md](decisoes_resumo.md)). Os gráficos estão em
[`imagens/`](imagens/).

Cada teste abaixo traz:

- **O que foi medido:** a pergunta que o teste responde;
- **Como:** o que muda entre as barras e o que fica fixo;
- **Legenda do gráfico:** o que são os eixos, as cores e os rótulos;
- **Resultado:** os números consolidados e a conclusão.

## Ambiente e protocolo

| Item | Valor |
|---|---|
| Banco | PostgreSQL 17.12 (Docker `postgres:17`, aarch64), num MacBook Air M1 |
| Configuração | Padrão do container: `shared_buffers` 128 MB, `work_mem` 4 MB, `effective_cache_size` 4 GB |
| Sessão de medida | `jit = off` e `max_parallel_workers_per_gather = 0`, para os tempos serem comparáveis |
| Dados | Seed na escala 1, versão atual (chave de `Video` em UUID v4 nativo): cerca de 8,7 milhões de registros e 1,5 GB de schema |
| Medida | `EXPLAIN (ANALYZE, BUFFERS)` da chamada real da function |
| A frio | Antes de **cada** medida: parada do Postgres (esvazia o `shared_buffers`), `drop_caches` na VM do Docker (esvazia o cache do sistema) e nova subida |
| A quente | Uma execução de aquecimento descartada e depois as medidas, sem reiniciar |
| Repetições | 5 por cenário; o valor usado é a **mediana** |
| Volume | 760 medidas de consulta (76 cenários × 2 estados de cache × 5), 27 de `INSERT` e 12 de `REFRESH` |

### Critérios das medidas

- **Tempo citado** = `Execution Time` da repetição mediana, obtido com
  `EXPLAIN (ANALYZE, BUFFERS)`.
- **Páginas lidas** = `shared read + shared hit` da linha `Buffers` do nó raiz
  (a primeira do plano), na mesma repetição.
- **Nó que explica o resultado** (`Seq Scan`, `Index Only Scan` etc.) é o
  observado no plano de execução.
- **Item 12 é plpgsql:** o `EXPLAIN` externo mostra só um `Function Scan`.
  Para observar a consulta interna, foi usado `auto_explain` com
  `log_nested_statements`.

### Como ler os números

- **Páginas lidas** são a métrica mais estável. Elas se repetem quase
  idênticas nas 5 repetições, enquanto o tempo a frio de uma mesma consulta
  chega a variar de 2 a 3 vezes entre as 5 repetições. A causa é o disco
  da VM do Docker: o `drop_caches` esvazia o cache dentro da VM, mas o macOS ainda pode ter
  parte do arquivo de disco da VM em memória.
- **Os tempos absolutos dependem da máquina.** O que vale é a comparação entre
  cenários.
- **Escala log:** nos gráficos de tempo e de páginas, o eixo vertical é
  logarítmico (cada linha de grade vale 10 vezes a anterior), porque os valores
  vão de poucos milissegundos a dezenas de segundos. Uma barra com metade da
  altura de outra **não** vale metade.

### Rótulos usados no eixo horizontal

Os gráficos 01, 02 e 06 têm uma barra por consulta, no formato
`item N · filtro`. O número é o da consulta do enunciado; o filtro é o valor
passado ao parâmetro opcional:

| Rótulo | Valor passado | Por que esse valor |
|---|---|---|
| `sem filtro` | parâmetro nulo (`DEFAULT NULL`) | Consulta sobre o banco inteiro |
| `Kick` | plataforma Kick | Plataforma pequena (3,5% dos canais): o filtro devolve poucos canais (é o caso em que índice ajuda) |
| `YouTube` | plataforma YouTube | Plataforma grande: 28% dos canais (o filtro devolve muito, e índice não ajuda) |
| `canal` | `Echo.Queen 136733 TV` | O canal com mais visualizações, ou seja, com mais vídeos e comentários |
| `streamer` | `echo.queen_136733` | O dono desse canal |
| `usuario` | `ghost.yt_297686` | O membro com mais inscrições |
| `empresa` | `Red Bull GmbH` | A empresa que mais patrocina |
| `k=10` | `p_k = 10` | Top-10 nos itens 8 a 12 |

## 1. Frio × quente: por que medir a frio

![Gráfico 06: tempo de cada consulta a frio e a quente, sem índices de apoio](imagens/06_frio_quente.png)

**O que foi medido:** quanto o cache esconde do custo real de cada consulta. O
professor alertou que, repetindo a consulta, o dado vem da memória e o índice
parece não fazer diferença.

**Como:** as mesmas consultas, sem índices de apoio (só PK, `UNIQUE` e os
`UNIQUE` das views materializadas), medidas de dois jeitos. Muda só o estado do
cache.

**Legenda do gráfico 06:**
- **Eixo vertical:** tempo de execução em ms, escala log.
- **Eixo horizontal:** uma consulta por grupo (rótulos na tabela acima).
- **Azul, "a frio":** reinício do Postgres e `drop_caches` antes de cada medida;
  as páginas vêm do disco.
- **Laranja, "a quente":** a mesma consulta repetida sem reiniciar; as páginas já
  estão na memória.

**Resultado** (páginas lidas do disco, `shared read`, entre parênteses):

| Consulta | A frio | A quente | Diferença |
|---|---:|---:|---:|
| Item 2, filtro por canal | 631 ms (2.955) | 11,3 ms (0) | 56× |
| Item 3, filtro por streamer | 224 ms (1.679) | 11,4 ms (0) | 20× |
| Item 5, filtro por empresa | 15,3 ms (543) | 2,7 ms (0) | 5,7× |
| Item 7, filtro por canal | 95 ms (1.848) | 19,6 ms (0) | 4,8× |
| Item 1, plataforma pequena (Kick) | 749 ms (22.527) | 261 ms (19.751) | 2,9× |
| Item 1, sem filtro | 2.981 ms (28.599) | 1.062 ms (27.806) | 2,8× |
| Item 2, sem filtro | 10.242 ms (32.224) | 9.651 ms (31.174) | 1,1× |

- **Nas consultas com filtro seletivo, a diferença é enorme:** elas leem poucas
  páginas, e a quente todas já estão no `shared_buffers` (`shared read` = 0 no
  plano a quente).
- **Nas consultas sem filtro, a diferença é pequena:** elas leem a tabela quase
  inteira, que não cabe no `shared_buffers` de 128 MB. Até a quente, o plano
  mostra quase todas as páginas como `read` (vindas do cache do sistema, não do
  `shared_buffers`).
- **No item 6 por usuário, a quente ficou acima do frio** (155 ms
  contra 185 ms),
  com `shared read` = 0. As 5 repetições a quente vão de 94 a 244 ms: é
  variação entre repetições, não efeito do cache.

Medindo só a quente, quase toda consulta filtrada parece instantânea, e o índice
"não faz diferença". Por isso as comparações seguintes são a frio.

## 2. Reescrita das consultas antes dos índices

![Gráfico 03: itens 2 e 3 em três formas de escrever a consulta, a frio](imagens/03_reescrita.png)

**O que foi medido:** se mudar a forma da consulta resolve a lentidão antes de
criar índice, como o professor orientou.

**Como:** os itens 2 e 3, com e sem filtro, escritos de três formas, todas sem
índices de apoio e a frio. Muda só o texto da consulta. A forma final é a de
`functions.sql`; as diferenças entre as três formas estão descritas na legenda.

**Legenda do gráfico 03:**
- **Eixo vertical:** tempo de execução em ms, escala log.
- **Eixo horizontal:** item e filtro (`canal` e `streamer` como na tabela de
  rótulos).
- **Azul, "original":** a primeira versão, que conta os comentários de **todos**
  os vídeos e só depois filtra o canal ou o streamer.
- **Laranja, "reescrita":** filtra o canal ou o streamer primeiro e conta só os
  comentários desses vídeos, numa passada.
- **Verde, "final":** lê a contagem pronta da view materializada V3.

**Resultado** (tempo a frio; páginas lidas entre parênteses):

| Consulta | Original (agrega tudo, depois filtra) | Reescrita (filtra antes) | Final (sobre a V3) |
|---|---:|---:|---:|
| Item 2, sem filtro | 8.435 ms (138.917) | 17.541 ms (214.491) | 10.242 ms (32.230) |
| Item 2, filtro por canal | 3.931 ms (114.281) | 1.112 ms (8.217) | **631 ms** (5.156), 6,2× |
| Item 3, sem filtro | 6.784 ms (85.227) | 42.546 ms (85.233) | **1.006 ms** (20.470), 6,7× |
| Item 3, filtro por streamer | 7.492 ms (114.986) | 997 ms (6.241) | **224 ms** (1.689), 33× |

(O "×" compara a versão final com a original.)

- **Filtrar antes de agregar** resolve os casos com filtro. No plano da
  original, `Seq Scan on comentario` lê as cerca de 113 mil páginas da tabela
  mesmo com filtro. Na reescrita, os comentários são lidos só dos vídeos do
  canal, pela PK.
- **Sem filtro, a reescrita direta piora:** agrupar 5 milhões de comentários
  estoura o `work_mem` e ordena em disco. No plano do item 3 aparece
  `Sort Method: external merge  Disk: 466440kB`. Esses casos foram resolvidos
  pela view materializada V3, que lê 4 vezes menos páginas.
- **O item 2 sem filtro continua caro,** e a versão final não ficou mais
  rápida que a original (10,2 contra 8,4 s), embora leia 4 vezes menos
  páginas. Ele devolve e ordena 1,25 milhão de vídeos, e o custo está em
  ordenar a saída: `Sort Method: external merge  Disk: 108808kB`. Com
  `LIMIT`, que é como a consulta é usada, vira uma ordenação parcial em
  memória.

## 3. Consulta direta × view virtual × view materializada

![Gráfico 04: itens 10 e 11 (top-10) em três fontes de dados, a frio](imagens/04_views.png)

**O que foi medido:** se as views aceleram os rankings top-k, e qual tipo de
view faz a diferença.

**Como:** os itens 10 e 11 com `k = 10`, a frio, sem índices de apoio. Muda só
de onde a consulta lê.

**Legenda do gráfico 04:**
- **Eixo vertical:** tempo de execução em ms, escala log.
- **Eixo horizontal:** item 10 (top-10 canais por doações) e item 11 (top-10
  canais por faturamento total).
- **Azul, "consulta direta":** junta e soma as tabelas base (`Doacao`,
  `Inscricao`, `Patrocinio` etc.) a cada chamada.
- **Laranja, "views virtuais V1/V2":** a mesma soma, escrita sobre as views
  virtuais; o planejador expande a view dentro da consulta.
- **Verde, "materializada V4":** lê o faturamento por canal já somado e só
  ordena.

**Resultado** (tempo a frio; páginas lidas entre parênteses):

| Consulta (k = 10) | Direta nas tabelas | Sobre as views virtuais V1/V2 | Sobre a materializada V4 |
|---|---:|---:|---:|
| Item 10 | 732 ms (171.696) | 756 ms (171.699) | **27,8 ms** (952), 26× |
| Item 11 | 3.279 ms (185.222) | 2.712 ms (185.322) | **37,3 ms** (952), 88× |

- **A view virtual não acelera:** o planejador a expande dentro da consulta. Os
  planos da direta e da virtual têm os mesmos nós (`Seq Scan on doacao`,
  `Index Scan using video_pkey`) e leem as mesmas páginas. A diferença de 17%
  no item 11 está dentro da variação entre repetições.
- **A materializada muda a ordem de grandeza,** em troca de dados com atraso. O
  plano lê só `mv_faturamento_canal` e `canal` (952 páginas).

**Custo de atualizar as materializadas** (tempo do `REFRESH`, mediana de 3, sem
gráfico):

| View | `REFRESH` comum | `REFRESH CONCURRENTLY` |
|---|---:|---:|
| V3 `mv_interacoes_video` (1,25 milhão de linhas) | 12,4 s | 27,0 s |
| V4 `mv_faturamento_canal` (22,7 mil linhas) | 1,4 s | 1,5 s |

O `REFRESH` não aceita `EXPLAIN`: o tempo foi medido dentro do servidor, com
`clock_timestamp()` antes e depois. O `CONCURRENTLY` não bloqueia leituras, mas
é mais lento. Por isso a atualização é periódica, e não por trigger.

## 4. Sem × com índices de apoio

![Gráfico 01: tempo a frio de cada consulta, sem e com os índices de apoio](imagens/01_tempo_indices_frio.png)

![Gráfico 02: páginas lidas por cada consulta, sem e com os índices de apoio](imagens/02_buffers_indices.png)

**O que foi medido:** o efeito dos índices de apoio escolhidos, consulta por
consulta.

**Como:** as consultas dos itens 1 a 12, a frio, já na forma final (com as views
V3 e V4). Muda só a presença dos índices de apoio das tabelas base.

**Legenda dos gráficos 01 e 02:**
- **Eixo vertical do 01:** tempo de execução a frio em ms (mediana de 5), escala
  log.
- **Eixo vertical do 02:** páginas de 8 KB lidas pela consulta (`shared read +
  hit`), escala log. Mostra o trabalho de leitura sem o ruído do tempo.
- **Eixo horizontal:** uma consulta por grupo (rótulos na seção "Ambiente").
- **Azul, "só PK e UNIQUE":** sem índices de apoio nas tabelas base. Os `UNIQUE`
  das views materializadas já existem, porque o `REFRESH CONCURRENTLY` os exige.
- **Laranja, "com os índices de apoio finais":** com `idx_inscricao_id_membro`,
  `idx_canal_id_streamer` e `idx_video_id_canal_cobertura`.

**Resultado.** Onde há um índice que atende o predicado, a mudança aparece no
plano e nas páginas lidas:

| Consulta | Sem índice de apoio | Com índice de apoio | Índice |
|---|---|---|---|
| Item 6, filtro por usuário | 155 ms, 4.135 páginas (`Seq Scan on inscricao`) | **4,5 ms**, 123 páginas (`Bitmap Index Scan on idx_inscricao_id_membro`) | `idx_inscricao_id_membro` |
| Item 1, plataforma pequena (Kick) | 749 ms, 25.526 páginas (`Seq Scan on video`) | **444 ms**, 9.530 páginas (`Index Only Scan using idx_video_id_canal_cobertura`) | `idx_video_id_canal_cobertura` |
| Item 3, filtro por streamer | 224 ms, 1.689 páginas (`Seq Scan on canal`); 11,4 ms a quente | **217 ms**, 1.027 páginas (`Index Scan using idx_canal_id_streamer`); **1,8 ms** a quente | `idx_canal_id_streamer` |

No item 1 com o Kick, a quente o índice leva de
261 ms para
20,8 ms. No item 3,
a frio, as duas versões ficam perto de 220 ms: o tempo é dominado pelo
primeiro acesso ao disco e ao catálogo, e o ganho aparece nas páginas e a
quente.

Onde **não** há ganho, o plano e as páginas lidas são os mesmos com e sem
índice (barras iguais no gráfico 02):
- **Itens sem filtro (1, 2, 3, 4, 6, 7) e item 1 com o YouTube** (28% dos
  canais): leem quase a tabela toda, e a varredura sequencial vence. É o caso
  "todos americanos" do professor. Exemplo: o item 1 com o YouTube lê 28.605
  páginas com `Seq Scan on video` sem
  e com o índice.
- **Itens 8 a 11:** ordenam as 22,7 mil linhas da V4 lendo 952 páginas, nos
  dois cenários.
- **Item 12:** lê `Canal` inteira nos dois cenários (seção 7).

Algumas barras do gráfico 01 mudam sem nenhuma mudança de plano nem de páginas
lidas no gráfico 02:
- item 1 sem filtro: de 2.981
  para 1.111 ms;
- item 3 sem filtro: de 1.006
  para 1.952 ms;
- item 7 por canal: de 95
  para 253 ms.

Esses três casos não usam nenhum índice novo e leem as mesmas páginas. A
diferença é variação da leitura a frio no disco da VM. No item 1 sem filtro
sem índices, por exemplo, as 5 repetições foram de 1.380 a 3.725 ms, todas com
as mesmas 28.599 páginas lidas do disco.

## 5. Hash × B-tree nos predicados de igualdade

![Gráfico 07: B-tree e hash nas duas consultas com predicado só de igualdade](imagens/07_hash_btree.png)

**O que foi medido:** qual tipo de índice serve melhor quando o predicado é só
de igualdade (`coluna = valor`), como o professor sugeriu avaliar.

**Como:** as duas consultas cujo filtro é só igualdade, a frio e a quente. Muda
só o tipo do índice na mesma coluna: item 3 por streamer (`Canal.id_streamer`) e
item 6 por usuário (`Inscricao.id_membro`).

**Legenda do gráfico 07:**
- **Eixo vertical:** tempo de execução em ms, escala log.
- **Eixo horizontal:** consulta e estado do cache, entre parênteses.
- **Azul:** índice B-tree.
- **Laranja:** índice hash.

**Resultado da leitura:**

| Consulta | Tipo | A frio | A quente | Páginas lidas |
|---|---|---:|---:|---:|
| Item 6, por usuário | B-tree | 4,5 ms | 0,5 ms | 123 |
| Item 6, por usuário | hash | 4,3 ms | 0,4 ms | 122 |
| Item 3, por streamer | B-tree | 217 ms | 1,8 ms | 1.027 |
| Item 3, por streamer | hash | 207 ms | 1,8 ms | 1.027 |

**Resultado da escrita** (teste da seção 6, mediana de 3):

| Índice | Tipo | Tamanho (lote de teste) | `INSERT` em lote |
|---|---|---:|---:|
| `Inscricao (id_membro)`, 300 mil linhas | B-tree | 8,4 MB | 2.206 ms |
| `Inscricao (id_membro)`, 300 mil linhas | hash | 10,1 MB | 1.719 ms |
| `Canal (id_streamer)`, 35,9 mil linhas | B-tree | 1,0 MB | 330 ms |
| `Canal (id_streamer)`, 35,9 mil linhas | hash | 1,3 MB | 659 ms |

- **Os dois leem as mesmas páginas** e têm o mesmo plano (`Bitmap Index Scan`
  no item 6, `Index Scan` no item 3). As diferenças de tempo são de décimos de
  milissegundo a quente e estão dentro da variação a frio.
- **Na escrita, nenhum dos dois vence sempre.** O hash inseriu mais rápido em
  `Inscricao` e mais devagar em `Canal`, e as rodadas variam muito: no hash de
  `Canal`, foram 346, 659 e 971 ms.
- **O hash ficou maior nos dois casos.** Ficou o B-tree: lê o mesmo, ocupa
  menos e também entrega os dados em ordem.

## 6. Ganho × custo de escrita

![Gráfico 05: ganho de leitura, overhead de INSERT e tamanho de cada índice](imagens/05_ganho_overhead.png)

**O que foi medido:** se o ganho de leitura de cada índice compensa o custo que
ele cria em toda inserção. É o "considerar o overhead de inserção" do item
mandatório 4.

**Como:**
- **Ganho:** tempo a frio da consulta que o índice atende, sem e com ele
  (seção 4).
- **Custo:** `INSERT ... SELECT` de linhas da própria tabela, em ordem aleatória
  (`ORDER BY random()`, como chegariam os dados reais), numa cópia vazia com as
  mesmas PK, `UNIQUE` e `CHECK`, com e sem o índice. `CHECKPOINT` antes de cada
  rodada; 3 rodadas; mediana. A cópia não tem FKs, para medir só o custo de
  manter o índice. Cada `INSERT` foi medido com `EXPLAIN (ANALYZE, BUFFERS)`.
- **Lote:** 300 mil linhas em `Inscricao` e `Video`; a tabela inteira em `Canal`
  (35,9 mil).

**Legenda do gráfico 05** (três painéis, cada um com a sua escala; cada barra é
um índice, identificado pela tabela e pela coluna):
- **Painel azul, "Ganho de leitura a frio":** quantas vezes a consulta-alvo ficou
  mais rápida com o índice, em escala log. A linha horizontal em 1 significa "sem
  ganho". Consultas-alvo: item 6 por usuário (`Inscricao`), item 3 por streamer
  (`Canal id_streamer`), item 1 com o Kick (`Video` e o candidato descartado
  `Canal nro_plataforma`, este comparado com o conjunto final sem ele).
- **Painel laranja, "Overhead de INSERT em lote":** quanto a mais de tempo o
  `INSERT` do lote levou com o índice, em %.
- **Painel verde, "Tamanho do índice":** tamanho do índice **no lote medido**, em
  MB. Não é o tamanho na tabela inteira, que está na última coluna da tabela
  abaixo.

**Resultado:**

| Índice | Linhas | Sem índice | Com índice | Overhead | Ganho de leitura (a frio) | Tamanho na tabela inteira |
|---|---:|---:|---:|---:|---:|---:|
| `idx_inscricao_id_membro` | 300 mil | 1.355 ms | 2.206 ms | +63% | 35× (155 → 4,5 ms) | 10,4 MB |
| `idx_canal_id_streamer` | 35,9 mil | 279 ms | 330 ms | +18% | 1,03× (páginas 1.689 → 1.027; a quente 6×) | 0,7 MB |
| `idx_video_id_canal_cobertura` | 300 mil | 4.542 ms | 4.848 ms | +7% | 1,7× (749 → 444 ms; a quente 13×) | 37,5 MB |
| `Canal (nro_plataforma)`, descartado | 35,9 mil | 279 ms | 329 ms | +18% | nenhum (444 → 585 ms) | 0,3 MB |

- **O mais caro, de `Inscricao`, é aceito:** inscrição é escrita rara e a busca
  por usuário é frequente.
- **`Canal (nro_plataforma)` foi descartado.** Com ele, o planejador troca o
  `Seq Scan on canal` por um `Bitmap Index Scan`, mas `Canal` tem só 665
  páginas, e as páginas lidas quase não mudam:
  - item 1 com o Kick: 9.530 → 9.446, e o tempo foi de 444
    para 585 ms;
  - item 4 com o Kick: 21.362 → 21.278, de 395
    para 436 ms;
  - item 12: o plano interno continua com `Seq Scan on canal`.

  O custo desses itens está em `Video` e `Doacao`, não em `Canal`.

## 7. Item 12 (desafio)

![Gráfico 08: item 12 em seis formas de implementação, a frio](imagens/08_item12.png)

**O que foi medido:** quanto custa a versão final do item 12 (que dá a posição
da plataforma no ranking geral mesmo com filtro) e se uma view ou um índice a
mais compensariam.

**Como:** três chamadas do item 12, todas com `k = 10`: sem filtro, com filtro
pela Kick (plataforma pequena) e pelo YouTube (plataforma grande). A frio,
mediana de 5. Muda só a forma de implementação. A versão final e a V5 são
plpgsql; nelas foi observado também o plano da consulta interna com
`auto_explain`, para identificar o que a function realmente lê.

**Legenda do gráfico 08:**
- **Eixo vertical:** tempo de execução a frio em ms, escala log.
- **Eixo horizontal:** sem filtro, filtro Kick e filtro YouTube.
- **Azul, "anterior":** a primeira versão, que com filtro só olhava a
  plataforma pedida e respondia "1º de 1".
- **Laranja, "final, sem índice de apoio":** a versão entregue, sem os índices
  de apoio.
- **Cinza, "final, com os índices entregues":** a versão entregue com os 3
  índices de apoio de `functions.sql`.
- **Verde, "final + índice de cobertura em Canal":** a versão entregue com um
  candidato a mais, `Canal (nro_plataforma, id_streamer) INCLUDE
  (qtd_visualizacoes)`.
- **Amarelo, "final sobre V5 virtual":** a contagem por plataforma escrita como
  view virtual.
- **Rosa, "final sobre V5 materializada":** a contagem por plataforma gravada
  numa view materializada de 28 linhas.

**Resultado** (tempo a frio / a quente, com as páginas lidas a frio entre
parênteses):

| Forma | Sem filtro (k = 10) | Filtro Kick | Filtro YouTube |
|---|---|---|---|
| Versão anterior (sem posição global) | 55 / 46 ms (675) | 11 / 3,1 ms (672) | 16 / 8,6 ms (672) |
| Final, sem índices de apoio | 97 / 68 ms (1.434) | 72 / 55 ms (1.431) | 72 / 55 ms (1.431) |
| **Final, com os índices entregues** | 84 / 57 ms (1.446) | 111 / 71 ms (1.443) | 82 / 135 ms (1.443) |
| Final + índice de cobertura em `Canal` | 75 / 56 ms (1.464) | 75 / 57 ms (1.461) | 76 / 57 ms (1.461) |
| Sobre uma V5 virtual | 73 / 55 ms (1.381) | 71 / 55 ms (1.377) | 74 / 56 ms (1.377) |
| Sobre uma V5 materializada | 7,1 / 1,1 ms (299) | 7,0 / 1,2 ms (300) | 7,2 / 4,0 ms (300) |

- **O custo vem da posição global.** Para dar a posição real mesmo com filtro, a
  consulta agrupa `Canal` inteira e conta os streamers distintos. No plano
  interno (`auto_explain`), a consulta da function lê 675 páginas, das quais
  665 são `Seq Scan on canal`, as mesmas da versão anterior. As outras cerca de
  770 páginas do total são do catálogo do sistema: compilar a function plpgsql
  e planejar a consulta interna a cada sessão nova. Por isso a versão anterior
  era mais barata com filtro, mas respondia errado ("1º de 1").
- **Índice de cobertura em `Canal`: descartado.** O plano interno continua com
  `Seq Scan on canal`: o planejador não usa o índice.
- **Os índices entregues não mudam o item 12:** o plano é o mesmo e as páginas
  são as mesmas (mais 12 de catálogo). As diferenças de tempo, como os 135 ms
  a quente com o YouTube, são variação entre repetições.
- **V5 materializada: medida e não adotada.** O ganho é de cerca de 65 ms a frio
  numa resposta de 28 linhas, e o item 12 deixaria de ser exato até a próxima
  atualização da view.

## Documentação complementar

- [`predicados.md`](predicados.md): inventário dos predicados das functions e
  distribuição das colunas que orientam a escolha dos índices.
- [`estatisticas.sql`](estatisticas.sql): consultas de distribuição e `pg_stats`
  para executar sobre os dados carregados.

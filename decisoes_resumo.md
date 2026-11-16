# Stream do Bedo · Resumo das decisões de projeto

Projeto de Banco de Dados (UFF, 2026/2), em PostgreSQL 17. Cada item começa pela
**decisão**, seguida do porquê. A marca **[D x.y]** aponta a seção de
`decisoes_detalhamento.md` com as alternativas, as contas e as medições; os
números de desempenho estão em `benchmark.md`.

## Modelo e normalização [D 3]

- **O modelo dado foi otimizado, não alterado.** Só as chaves foram remodeladas:
  nenhuma tabela, relacionamento ou coluna comum foi criada, e nenhum derivado
  foi removido. A `data_inscricao` de uma versão anterior saiu [D 3.1, 3.2].
- **Chaves naturais propagadas viraram surrogates** (`id_usuario`, `id_canal`,
  `id_video`). Nick, nome do canal e título + data do vídeo se repetiam em 6 a 11
  tabelas; agora ficam guardados uma vez só, e renomear muda uma linha, não
  milhões [D 3.3].
- **`Doacao` sem o `nick`:** o comentário já determina o autor
  (`(id_video, seq) → id_usuario`); com ele, a chave seria superchave.
  **`qtd_visualizacoes` e `qtd_users` ficaram**, mantidos por trigger.

## Volumetria e tipos [D 4]

- **Um único cenário justifica tipos, seed e índices:** vídeo longo e curto em
  dezenas de plataformas, 10 anos, coletado por crawlers, com ordens de grandeza
  de fontes reais (ITU, UMass, Statista, Guinness) [D 4.1, 4.2].
- **`INTEGER` não serve nem para o YouTube de hoje** (1,48 × 10^10 vídeos, 6,9
  vezes o limite). O pior caso do professor, um short a cada 10 s em 60
  plataformas, dá 1,9 × 10^15 vídeos: 0,02% do `BIGINT` [D 4.3].
- **Cada coluna tem o tipo da maior conta do mundo real:** `BIGINT` em
  `id_usuario` (6 × 10^9 internautas), `id_canal`, `visu_total` (1,66 × 10^10),
  `qtd_visualizacoes` (2,92 × 10^11) e `qtd_users`; `INTEGER` em `Empresa.nro`,
  `Plataforma.nro` e nos sequenciais (recorde de 1,6 × 10^7 comentários num
  vídeo); `NUMERIC(14, 2)` no dinheiro e `NUMERIC(18, 8)` no câmbio [D 4.4].

## Chaves [D 5]

- **`Usuario` e `Canal` com `BIGINT IDENTITY`, e a chave natural em
  `UNIQUE NOT NULL`** (`nick`; `(nome, nro_plataforma)`, porque o nome só é único
  na plataforma). As filhas propagam o id: `Patrocinio (nro_empresa, id_canal)`,
  `NivelCanal` e `Inscricao` [D 5.1, 5.2].
- **`Video` com `id_video UUID` (`gen_random_uuid()`) e
  `UNIQUE (id_canal, titulo, dataH)`.** A chave natural repetiria ~53 bytes em 5
  milhões de comentários; a composta `(id_canal, seq_video)` levaria o `id_canal`
  às tabelas grandes; o `BIGINT` depende de uma sequence central. O UUID nasce
  no coletor, sem consultar o banco nem renumerar ao juntar coletas. Custo
  medido: +37% em `Video` e +28% na PK de `Comentario` [D 5.3].
- **`Comentario` é entidade fraca de `Video`: PK `(id_video, seq)`,** com `seq`
  recomeçando em cada vídeo. Contra o modelo dado, o índice caiu 76% e o
  `INSERT`, 52%. Um `id_comentario` próprio ainda exigiria o
  `UNIQUE (id_video, seq)`: dois índices, +16% de espaço [D 5.4].
- **`Doacao` e as 4 formas herdam `(id_video, seq_comentario, seq_pg)`** (24
  bytes, sem perda de alinhamento). `Conversao` mantém o código ISO 4217
  [D 5.5, 5.6].

## Constraints [D 6]

- **`UNIQUE` só onde há regra de negócio:** as chaves naturais substituídas;
  plataforma por nome e fundadora; `email` e `telefone` separados; conta por
  plataforma; documento por país; `TxID` e `IdPayPal`. Combinações que já contêm
  uma coluna única não foram criadas [D 6.1 a 6.4].
- **`NOT NULL`** no que o minimundo dá a todos; **`CHECK`** em valores > 0,
  contadores ≥ 0, `visu_simul <= visu_total` e domínios de `tipo` e `status`.
  Índices de PK e `UNIQUE` não contam no teto de 5 [D 6.5 a 6.7].

## Moeda [D 7]

- **Patrocínio em USD,** sem conversão: vem de contrato externo.
- **Doação convertida no `INSERT`, pelo valor histórico** (T11), pela moeda do
  país de residência de quem comentou: é um fato passado, `Conversao` não guarda
  histórico de câmbio, e o YouTube faz o mesmo [D 7.3].
- **Membros convertidos na consulta, pelo valor corrigido** (V2): receita
  recorrente, e o câmbio de hoje é o que interessa a quem patrocina.
- Doação recusada não conta; só patrocínios e membros vigentes entram [D 7.4].

## Triggers [D 8]

- **11 triggers, um por regra do minimundo:** derivados (T1, T2); sequenciais
  por vídeo, comentário e conta, com `FOR UPDATE` (T3 a T5); doação em
  exatamente uma forma (T6); coerência de datas (T7); até 5 níveis (T8); dono e
  participante são streamers (T9); dono tem conta na plataforma (T10); conversão
  (T11) [D 8.1].
- **T1 e T2 por comando,** com tabelas de transição: mil vídeos num `INSERT`
  geram um `UPDATE` por canal [D 8.2].
- **`qtd_users` por trigger, aceitando a linha quente** na plataforma: 28 linhas
  em cache, `UPDATE` HOT, carga em lote. Com centenas de cadastros por segundo,
  a recontagem periódica seria melhor [D 8.5].
- **Triggers por último,** para não travar a carga; o seed obedece às mesmas
  regras. 37 casos de teste, todos OK [D 8.3, 8.4].

## Views: 4 de 5 [D 9]

- **V1 e V2 virtuais** (doação recebida, inscrição em USD): centralizam a regra
  de status e a conversão, e deixam o filtro chegar aos índices.
- **V3 e V4 materializadas** (interações por vídeo, faturamento por canal):
  contagem de 5 milhões de comentários e top-k por valor agregado, que toleram
  atraso. Item 3 filtrado: 7,5 s → 0,22 s; item 10: 0,73 s → 28 ms. Atualizadas
  por `sp_refresh_views()` (`REFRESH CONCURRENTLY`), não por trigger [D 9.2].
- **V5 medida e descartada:** ganharia ~60 ms, mas o item 12 deixaria de ser
  exato [D 9.3].

## Consultas [D 10]

- **12 functions com filtro opcional `DEFAULT NULL` ou `k`** (nulo devolve
  todos). Os itens 1 a 11 são `LANGUAGE sql STABLE`, para o planejador expandir a
  function e usar índice no filtro [D 10.1].
- **Consultas reescritas antes dos índices:** filtrar antes de agregar [D 10.3].
- **Item 12:** streamer da plataforma é quem tem canal nela; ordena por
  streamers e desempata por canais; empates no corte entram; com filtro, mostra
  a posição geral. Zero divergências contra contagem independente [D 10.4].

## Índices de apoio: 5 de 5 [D 11]

- **Escolhidos por predicado e distribuição (`pg_stats`), medidos a frio e com o
  custo de `INSERT`:** os 2 únicos das materializadas (exigidos pelo
  `REFRESH CONCURRENTLY`); `Inscricao (id_membro)`, item 6: 155 → 4,5 ms, +63% no
  `INSERT`; `Canal (id_streamer)`, item 3, T9 e T10: +18%;
  `Video (id_canal) INCLUDE (visu_total)`, item 1: 749 → 444 ms, +7% [D 11.3].
- **B-tree, não hash:** mesmas páginas lidas, menor e em ordem [D 11.4].
- **Sem índice onde o filtro devolve quase tudo:** `status <> 'recusado'` (90%
  das doações), YouTube (28% dos canais) [D 11.5, 11.6].

## Dados [D 12]

- **~8,7 milhões de registros**, com autorização do professor: com 10 mil linhas
  tudo caberia no cache e o índice não faria diferença. `Comentario` tem 5
  milhões de linhas (464 MB, 3,5 vezes o `shared_buffers`) [D 11.7, 12.1].
- **Tabelas de referência no tamanho real** (154 moedas, 199 países, 28
  plataformas) e **distribuição desbalanceada:** popularidade lognormal comanda
  visualizações, vídeos, comentários e receitas [D 12.2].
- **Reprodutível:** semente fixa, banco vazio exigido, uma transação com a
  conferência das regras dos triggers; `ESCALA=0.1` para teste rápido [D 12.3].

## Medição [D 13]

- **Tudo medido a frio:** reinício do Postgres e `drop_caches` antes de cada
  medida, 5 repetições, mediana, `EXPLAIN ANALYZE` salvo em `bench/planos/`. O
  cache esconde o custo: item 2 filtrado leva 631 ms a frio e 11 ms a quente.

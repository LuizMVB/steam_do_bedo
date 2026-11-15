# Stream do Bedo · Decisões de projeto

Trabalho final de Projeto de Banco de Dados (UFF, 2026/2), em PostgreSQL 17.
Este arquivo resume as decisões do grupo e as justificativas de design,
agrupando as decisões parecidas.

Os comentários do código citam as decisões por número (`-- DEC-NNN`). Cada
seção abaixo diz quais números ela cobre. O registro completo, decisão por
decisão, com todas as medições, está na tag `v1.1.0` do repositório.

A forma de executar e a ordem dos arquivos (DEC-030) estão no
[README.md](README.md).

## 1. Regra do trabalho e cenário (DEC-019, DEC-020)

- **O que pode mudar no modelo.** O modelo relacional do enunciado é
  otimizado, não alterado:
  - **pode:** remodelar chaves, inclusive com chave artificial (surrogate),
    mudar tipos, criar constraints, índices, views, triggers e functions;
  - **não pode:** criar tabelas, mudar relacionamentos, criar colunas comuns ou
    remover atributos derivados.

  Por isso a coluna `Inscricao.data_inscricao`, de uma versão anterior, saiu.
  As únicas colunas novas são as chaves artificiais `id_usuario`, `id_canal` e
  `id_video`.
- **Cenário de volumetria.** É um catálogo de streaming de jogos com **vídeo
  longo e curto** (lives, VODs, shorts, TikTok, Reels), em dezenas de
  plataformas e com horizonte de 10 anos. Esse único cenário justifica os tipos
  de chave, os volumes do seed e os índices:

| Entidade | Máximo no cenário | Tipo escolhido |
|---|---|---|
| Plataforma, Empresa | 10^3 a 10^8 | `INTEGER` |
| Usuario | 6 × 10^12, no pior caso (internet inteira, várias contas por pessoa) | `BIGINT` |
| Canal | acima de 2,15 × 10^9 (todo criador de vídeo curto tem canal) | `BIGINT` |
| Video | 1,9 × 10^15 (shorts a cada 10 s replicados em 60 plataformas, a conta sugerida pelo professor) | `UUID` |
| Comentários por vídeo, doações por comentário | 10^7 e 10 | `INTEGER` |

## 2. Chaves (DEC-005, 008, 014, 015, 017, 021 a 024)

| Tabela | Chave | Por quê |
|---|---|---|
| Usuario | `id_usuario BIGINT IDENTITY`, `nick` como `UNIQUE` | O nick pode mudar e se repetia como chave em 6 tabelas. Com inteiro, o join é mais barato e um renome não atualiza milhões de comentários. Foi sugestão do professor |
| Canal | `id_canal BIGINT IDENTITY`, `(nome, nro_plataforma)` como `UNIQUE` | A chave natural composta de texto se propagava para patrocínio, níveis, inscrições e vídeos |
| Video | `id_video UUID` gerado por `gen_random_uuid()`, `(id_canal, titulo, dataH)` como `UNIQUE` | No cenário, os ids são gerados de forma distribuída (por coletores e partições), sem sequência central e sem colisão. Custo aceito: cerca de 37% a mais de espaço em `Video` em relação ao `BIGINT` |
| Comentario | `(id_video, seq)` | O comentário depende do vídeo, como o professor confirmou. O `nick` saiu da chave, o que reduziu o índice em 76% em relação à chave natural de 6 colunas |
| Doacao e as 4 formas de pagamento | `(id_video, seq_comentario, seq_pg)` | Herda a chave do comentário. `UUID` + `INTEGER` + `INTEGER` somam 24 bytes, sem desperdício de alinhamento |

**UUID nativo (versão 4):** o projeto usa só a função nativa do PostgreSQL 17,
`gen_random_uuid()`.
- **Custo:** o id é aleatório, então cada vídeo novo entra num ponto qualquer
  do B-tree da PK, e não no fim, como numa sequence. Isso gera mais divisões de
  página na inserção. Na medição em lote, o v4 ficou com o mesmo tamanho do v7
  e com `INSERT` cerca de 9% mais lento.
- **Por que não o v7:** um UUID v7, ordenado no tempo, evitaria esse custo, mas
  o PostgreSQL 17 não tem `uuidv7()` nativo; ele só chega no 18. O grupo
  preferiu a função nativa a manter uma function própria.
- **No seed:** os vídeos são gravados em ordem de `id_video`. Como o
  `gen_random_uuid()` não obedece à semente, os sorteios que dependem da ordem
  dos vídeos usam uma ordem fixa: data, canal e número do vídeo.

## 3. Constraints (DEC-006, 009 a 011, 016, 025)

- **`UNIQUE` pelas regras de negócio do minimundo:**
  - nome da plataforma junto com a empresa fundadora;
  - nome da moeda;
  - e-mail e telefone do usuário;
  - nick;
  - número do usuário dentro de cada plataforma;
  - passaporte dentro do país emissor;
  - identificador nacional da empresa dentro do país;
  - nome do país;
  - `TxID` do bitcoin;
  - `IdPayPal`.
- **`NOT NULL`** onde o minimundo dá o atributo a todos: país de residência,
  data de fundação, data de início do canal e o `.gif` de cada nível.
- **`CHECK`:** valores positivos, contadores não negativos, pico simultâneo
  nunca acima do total de visualizações, e os domínios de `tipo` e `status`.
- **Não criados de propósito:** `UNIQUE` sobre conjuntos de colunas que já
  contêm uma chave única. Eles não protegem nada e gastam um índice.

## 4. Moeda (DEC-001 a 004, 026)

- **Patrocínio:** sempre em USD, porque vem de um contrato externo.
- **Doação:** o valor chega na moeda do país de residência de quem comentou, e o
  trigger T11 converte para USD no `INSERT`. É o valor **histórico**, o que o
  canal recebeu no dia; o professor aceitou as duas formas (gravar ou converter
  na consulta).
- **Membros:** o valor do nível é convertido na consulta, pela view V2. É o
  valor **corrigido**.
- **Critérios das consultas:**
  - doação recusada não conta como recebida;
  - não há histórico de patrocínio nem de membros, então só os vigentes entram;
  - `k` nulo devolve todos os canais.

## 5. Triggers (DEC-027)

| ID | Regra | Como |
|---|---|---|
| T1, T2 | `Canal.qtd_visualizacoes` é a soma de `visu_total`; `Plataforma.qtd_users` é o número de contas | Trigger por comando, com tabelas de transição: um `INSERT` de mil vídeos faz um único `UPDATE` no canal |
| T3, T4, T5 | Números sequenciais por vídeo, por comentário e por usuário e plataforma | `max + 1` com `SELECT … FOR UPDATE` na linha pai, para inserções simultâneas não gerarem o mesmo número |
| T6 | Doação em exatamente uma das 4 formas de pagamento (disjunta e total) | Rejeita a segunda forma; um trigger de constraint adiado rejeita, no `COMMIT`, doação sem forma |
| T7 | Ordem no tempo: fundação ≤ canal ≤ vídeo ≤ comentário | Não cabe em `CHECK`, porque envolve outra tabela |
| T8 | No máximo 5 níveis por canal | Rejeita o sexto |
| T9, T10 | Dono de canal e participante de vídeo são streamers (têm passaporte); o dono tem conta na plataforma | Trigger, e não FK, para não mudar os relacionamentos do modelo |
| T11 | Doação em USD | Converte pela moeda do país de residência |

## 6. Views (DEC-028): 4 das 5 permitidas

| View | Tipo | Atende | Por quê |
|---|---|---|---|
| V1 `vw_doacao_recebida` | Virtual | Itens 4, 7 e V4 | Concentra num lugar só a regra de status e o caminho doação → vídeo → canal |
| V2 `vw_inscricao_usd` | Virtual | Item 6 e V4 | Concentra a conversão do valor dos membros |
| V3 `mv_interacoes_video` | Materializada | Itens 2 e 3 | Contar os 5 milhões de comentários dominava o tempo dessas consultas |
| V4 `mv_faturamento_canal` | Materializada | Itens 8 a 11 | O top-k ordena por um valor agregado, e nenhum índice nas tabelas base atende isso |

- **Atualização:** as materializadas são atualizadas periodicamente com
  `CALL sp_refresh_views()`, que faz o `REFRESH … CONCURRENTLY` e não bloqueia
  leituras. Não há atualização por trigger, porque recontar a cada comentário
  custaria mais que a própria consulta.
- **Views virtuais não aceleram nada por si só,** porque o planejador as expande
  dentro da consulta. O ganho vem das materializadas.

## 7. Consultas (DEC-029, 033, 035)

- **Formato das functions:** todas são `LANGUAGE sql STABLE`, para o planejador
  expandir a function dentro da consulta (inline). Assim, o filtro opcional
  `p IS NULL OR col = p` usa índice quando o parâmetro é passado.
- **Reescrita antes dos índices:** as consultas foram reescritas antes de criar
  índices, como o professor orientou. Filtrar antes de agregar e ler a V3 tornou
  o item 3 filtrado 39 vezes mais rápido e o item 2 filtrado 11 vezes. A V4 deixou
  os itens 10 e 11 de 60 a 90 vezes mais rápidos.
- **Item 12 (desafio): top-k plataformas por streamers E canais.**
  - **Streamer da plataforma:** quem tem canal nela, contado uma vez só.
  - **O "E" do enunciado:** ordena por streamers e desempata por canais. Cada
    streamer distinto é uma audiência própria (alcance de público).
  - **Empates no corte de k:** entram todas as plataformas empatadas.
  - **Com filtro:** a plataforma mostra a sua posição no ranking geral, e não
    "1º de 1".
  - **Validação:** comparada com uma contagem independente, deu 0 divergências.

## 8. Índices de apoio (DEC-034, que substitui a DEC-018): 5 de 5

| # | Índice | Atende | Efeito medido a frio | Custo |
|---|---|---|---|---|
| 1 | `ux_mv_interacoes_video (id_canal, id_video)` | V3: itens 2 e 3 | obrigatório para o `REFRESH CONCURRENTLY`; também atende o filtro por canal | 48 MB |
| 2 | `ux_mv_faturamento_canal (id_canal)` | V4: itens 8 a 11 | obrigatório para o `REFRESH CONCURRENTLY` | 0,5 MB |
| 3 | `idx_inscricao_id_membro` (B-tree) | Item 6 por usuário | 160 → 7 ms; páginas lidas 4.040 → 54 | `INSERT` +59% |
| 4 | `idx_canal_id_streamer` (B-tree) | Item 3 por streamer; T9 e T10 | páginas lidas 1.554 → 892 | `INSERT` +17% |
| 5 | `idx_video_id_canal_cobertura (id_canal) INCLUDE (visu_total)` | Item 1 por plataforma | 587 → 341 ms; páginas 25.526 → 9.530 | `INSERT` +9% |

- **Método, como o professor indicou:**
  1. inventário dos predicados das consultas;
  2. distribuição de cada coluna (`pg_stats`);
  3. tipo do índice conforme o tipo do predicado;
  4. medição a frio, com e sem o índice.
- **Hash × B-tree:** onde o predicado era só de igualdade, os dois foram
  medidos. O hash leu as mesmas páginas, ficou maior e não inseriu mais rápido,
  então ficou o B-tree.
- **Predicados concentrados não foram indexados.** Por exemplo,
  `status <> 'recusado'` devolve 90% das doações, e consultas sem filtro leem a
  tabela inteira.
- **Os índices das views materializadas contam no teto de 5.**

## 9. Dados (DEC-031)

O professor autorizou ultrapassar a faixa de 1.000 a 10.000 registros do
enunciado: "povoar o máximo [...] centenas de milhares de tuplas", com
distribuição desbalanceada. A carga tem **cerca de 8,7 milhões de registros**:

| Tabela | Registros | Tabela | Registros |
|---|---:|---|---:|
| Conversao | 154 | Inscricao | 598.075 |
| Pais | 199 | Patrocinio | 18.785 |
| Empresa | 3.000 | Video | 1.247.319 |
| EmpresaPais | 3.471 | Participa | 94.415 |
| Plataforma | 28 | Comentario | 5.000.143 |
| Usuario | 500.000 | Doacao | 99.510 |
| PlataformaUsuario | 856.263 | BitCoin | 9.669 |
| StreamerPais | 26.081 | PayPal | 21.494 |
| Canal | 35.906 | CartaoCredito | 23.719 |
| NivelCanal | 98.855 | MecanismoPlat | 44.628 |

A contagem foi feita na versão com UUID v7 (tag `v1.1.0`). Com o
`gen_random_uuid()`, o sorteio das doações percorre os comentários numa ordem
um pouco diferente. Por isso `Doacao` e as quatro formas de pagamento podem
variar algumas centenas de registros; as demais tabelas não mudam.

- **Tabelas de referência no tamanho real,** abaixo de 1.000 com autorização do
  professor: 154 moedas ISO, 199 países e 28 plataformas reais.
- **Distribuições desbalanceadas e correlacionadas:** a popularidade de cada
  canal segue uma lognormal e comanda as visualizações, a quantidade de vídeos,
  os membros e o patrocínio. Os comentários são proporcionais às visualizações,
  com cauda longa. 5% dos usuários são streamers, e 1,9% dos comentários trazem
  doação.
- **Reprodutível:** o seed usa semente fixa. Os volumes, nomes, valores e
  distribuições se repetem a cada execução. Mudam só os UUIDs dos vídeos (o
  `gen_random_uuid()` não obedece à semente) e o que deriva deles: TxID,
  IdPayPal e o número do cartão. Ele recusa banco que não esteja vazio, roda
  numa única transação e, no fim, confere todas as regras dos triggers antes do
  `COMMIT`.

## 10. Medição (DEC-032)

Cada medida a frio é feita depois de:
1. reiniciar o Postgres, o que esvazia o `shared_buffers`;
2. limpar o cache de páginas da VM do Docker (`drop_caches`).

São 5 repetições, e o valor usado é a mediana. A medida só vale como fria se o
plano mostrar páginas lidas do disco (`shared read` > 0). O resultado completo
está em [benchmark.md](benchmark.md).

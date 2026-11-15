# Consulta com o professor (2026-11-11) · Plano de ação

## Objetivo

Registrar o que foi conversado com o professor Marcos Bedo sobre o trabalho, as
decisões que o grupo tomou a partir disso e **o que precisa ser feito, em que
ordem**, considerando o que o projeto tem hoje.

Fontes:

- Transcrição do áudio: [transcricao_consulta_professor_2026-11-11.md](transcricao_consulta_professor_2026-11-11.md).
  A coluna **Áudio** da tabela aponta o minuto do trecho.
- Enunciado: `ProjetoFinalDeDisciplina_02_2026-2.pdf`.
- Aviso do professor no Classroom sobre a entrega (copiado em [Formato de entrega](#formato-de-entrega-aviso-do-classroom)).
- Estado atual: `ddl.sql`, `procedures.sql`, `queries.sql`, `seed_v2.sql`,
  `seed_v2_RELATORIO.md` e `DECISIONS.md` (DEC-001 a DEC-018).

**Este documento não reorganiza o projeto no formato de entrega.** Isso fica
para a fase 5 (P20 e P21).

**Execução de 2026-11-15:** P01 a P19 feitos (ver o bloco "Resultado" de cada
ponto). A ordem de execução dos arquivos ficou `ddl.sql` → `seed_v3.sql` →
`views.sql` → `procedures.sql` → `triggers.sql` → `indices.sql` → `queries.sql`
(DEC-030). P20 a P22 continuam a fazer.

### Status

| Status | Significado |
|---|---|
| **Feito** | Já está no projeto e segue o que foi conversado |
| **Parcial** | Existe, mas precisa ser revisto ou completado |
| **A fazer** | Ainda não existe |
| **Decidir** | Depende de uma decisão do grupo antes de executar |

## Ordem lógica

O plano é sequencial: cada fase usa o resultado da anterior.

1. **Fase 0 · Premissas:** a regra do que pode ser alterado e o cenário de
   volumetria. Tudo o que vem depois (tipos de chave, seed, índices) se
   justifica pelo cenário.
2. **Fase 1 · DDL:** chaves, constraints e regra de moeda. O seed só pode ser
   escrito sobre o DDL final.
3. **Fase 2 · Especificação PL/pgSQL:** triggers, views e procedures. As regras
   dos triggers vêm **antes** do seed porque, na ordem de execução da entrega, os
   triggers são criados **depois** da carga. Então o seed precisa obedecer às
   mesmas regras e calcular os atributos derivados por conta própria.
4. **Fase 3 · Dados:** o seed v3 e a carga, seguidos do teste dos triggers.
5. **Fase 4 · Otimização e aferição:** primeiro as consultas são otimizadas,
   depois vêm o levantamento dos predicados e os índices. A medição a frio
   (`EXPLAIN ANALYZE` com e sem índices) e os gráficos vêm **no final**.
6. **Fase 5 · Documentação e entrega:** decisões, PDF e empacotamento.

Na entrega, a **ordem de execução** dos arquivos é diferente da ordem de
trabalho: DDL → dados → PL/pgSQL (functions, triggers e views) → chamadas das
consultas.

## Tabela de pontos

| # | Fase | Ponto | Resumo | Hoje no projeto | Ação | Depende de | Áudio | Status |
|---|---|---|---|---|---|---|---|---|
| P01 | 0 | Regra de alteração do modelo | Otimizar o projeto sem mudar as relações: pode criar constraints e remodelar chaves; não pode criar tabelas, mudar relações, criar colunas comuns nem remover atributos derivados | Surrogates (DEC-014, 015, 017) e CHECKs (DEC-016) seguem a regra. **`Inscricao.data_inscricao` (DEC-007) é coluna nova fora de chave** | Revisar todas as DECs contra a regra; reverter ou justificar a DEC-007 | - | 00:15 | Feito |
| P02 | 0 | Cenário de volumetria | O tipo de vídeo e a volumetria são definidos pelo grupo; o que importa é a coerência em todo o trabalho | Cálculos de capacidade isolados (DEC-005, 008, 015); distribuições do seed v2 limitadas a 10 mil linhas | Escrever uma DEC de cenário com plataformas, taxas e horizonte, e derivar dela o máximo de linhas por tabela | P01 | 02:06–03:57 | Feito |
| P03 | 1 | Chave de `Video` | Com várias plataformas, faz sentido avaliar outro identificador, talvez UUID | `id_video BIGINT IDENTITY` (DEC-015) | Decidir entre `BIGINT` e UUID pelo cenário (P02); se UUID, decidir v4 ou v7 e medir o impacto | P02 | 01:42–03:57 | Feito |
| P04 | 1 | Chave de `Comentario` | Comentário "não segura" chave própria; fica a chave dependente do vídeo | PK `(id_video, seq)`; geração de `seq` não decidida (DEC-017) | Confirmar o tipo de `seq` pelo cenário; geração de `seq` vai para o trigger T3 | P02, P03 | 03:07, 05:49 | Feito |
| P05 | 1 | Surrogate em `Usuario` | O professor perguntou por que `Comentario` referencia `nick_usuario` e não um `id_usuario` | `nick VARCHAR(255)` é a PK e se propaga para 6 tabelas; não medido (DEC-017, item 5) | Decidir `id_usuario` com `UNIQUE (nick)`; se adotar, medir como na DEC-017 | P02 | 06:01–06:23 | Feito |
| P06 | 1 | Constraints (item mandatório 2) | Construção criteriosa de identificadores, `UNIQUE` e `NOT NULL` | DEC-009 a 016 aplicadas | Revisar depois de P03 a P05; avaliar `UNIQUE` em `BitCoin.TxID` e `PayPal.IdPayPal` | P03, P04, P05 | - | Feito |
| P07 | 1 | Conversão de moeda | Patrocínio sempre em USD. Doação convertida pelo país de residência do usuário. As duas formas de converter estão certas, desde que documentadas | Membros convertidos (DEC-001, 002); **doação não convertida** (ponto em aberto nas DEC-003 e 004) | Registrar a DEC; decidir entre converter na consulta e gravar em USD; ajustar os itens 4, 7, 10 e 11 | P01 | 12:09–15:14 | Feito |
| P08 | 2 | Triggers (item mandatório 5) | Definir pelo minimundo; `qtd_visualizacoes` é a soma bruta de `visu_total`; o mesmo vale para `qtd_users`; triggers ficam em arquivo separado | Nenhum trigger; os derivados são calculados por `UPDATE` no seed v2 | Fechar a especificação T1 a T11, implementar e testar (P12) | P03 a P07 | 05:57, 11:30, 16:06–17:53 | Feito |
| P09 | 2 | Views virtuais e materializadas (item mandatório 3) | Até 5 views, cada uma justificada | Nenhuma view; só o conceito em `notes.md` | Definir V1 a V5, a estratégia de refresh e se o índice de view conta no teto de 5 | P07, P08 | - | Feito |
| P10 | 2 | Procedures (item mandatório 6) | Consultas parametrizadas; o item 12 vale ponto extra | 11 functions; item 12 não existe; `queries.sql` usa valores do seed v1 | Ajustar ao DDL final, à conversão (P07) e às views (P09); implementar o item 12 | P03 a P09 | - | Feito |
| P11 | 3 | Seed v3 | Banco virgem e DDL completo; o máximo de dados possível (centenas de milhares de linhas); distribuição desbalanceada e realista; o limite de 1 mil a 10 mil é só referência | O seed v2 trava em 1 mil a 10 mil linhas e infla as tabelas pequenas (960 países, 990 plataformas) | Escrever o `seed_v3.sql` conforme o detalhamento | P02 a P08 | 03:59–05:31 | Feito |
| P12 | 3 | Carga, validação e teste dos triggers | Os dados precisam ser reproduzíveis pelo professor | O seed v2 foi validado; procedures e triggers não foram testados sobre a carga | Rodar DDL → seed v3 → PL/pgSQL; conferir derivados; `VACUUM ANALYZE`; testar cada trigger | P08 a P11 | 11:11–11:25 | Feito |
| P13 | 4 | Otimização das consultas | Primeiro deixar as consultas o melhor possível; os índices vêm em cima disso | DEC-018 aponta o item 2 agregando todo `Comentario` antes de filtrar | Medir a linha de base, reescrever as functions e medir de novo | P12 | 08:25–08:39 | Feito |
| P14 | 4 | Predicados e seletividade | Olhar a similaridade dos predicados e a distribuição; se for muito concentrada, o índice não ajuda | DEC-018 fez isso sobre dados uniformes | Montar o inventário de predicados × `pg_stats` sobre o seed v3 | P13 | 07:03–08:00 | Feito |
| P15 | 4 | Índices: hash e B-tree (item mandatório 4) | O tipo do índice segue o predicado; tipicamente secundários sobre parte da PK, eventualmente hash | 2 índices B-tree (DEC-018), medidos com cache quente e dados uniformes | Escolher até 5 índices com o tipo certo, comparar hash e B-tree onde o predicado for só de igualdade, refazer a DEC-018 | P14 | 08:00–08:16 | Feito |
| P16 | 4 | Protocolo de medição a frio | `EXPLAIN ANALYZE` antes e depois; cuidado com o cache; com poucos dados o índice não faz diferença | DEC-018 mediu com cache quente | Reiniciar o processo do Postgres e limpar o cache do SO antes de cada medida; comprovar pelos buffers | P12 | 08:46–10:33 | Feito |
| P17 | 4 | Aferição | Comparar com e sem índice e mostrar o ganho | Sem script de aferição | Rodar a matriz de cenários e salvar os resultados em CSV | P15, P16 | 08:50 | Feito |
| P18 | 4 | Gráficos | Demonstrar o efeito dos índices e das views | Nada | Gerar gráficos a partir do CSV | P17 | - | Feito |
| P19 | 5 | `DECISIONS.md` | Registrar cada decisão com justificativa | DEC-001 a 018 | Novas DECs para P02, P03, P05, P07, P08, P09, P11 e P15; marcar o que foi substituído | Todas | - | Feito |
| P23 | 5 | Item 12 (desafio), etapa final | Top-k plataformas por streamers E canais, com filtro opcional; ponto extra, justificado no cerne do problema | Versão básica na DEC-029 | Interpretar, implementar, medir a frio, validar e registrar (executado depois de P19) | P19 | - | Feito |
| P20 | 5 | PDF de decisões | PDF curto, em torno de 2 páginas, só com decisões e justificativas; o resto vai nos comentários do código | Nada | Gerar a partir de um markdown enxuto, com os gráficos de P18 | P18, P19 | 11:40–12:01 | A fazer |
| P21 | 5 | Formato de entrega | 5 arquivos no Classroom; link do Drive para arquivos grandes; todos os integrantes fazem upload | Arquivos soltos e seeds antigos convivendo | Mapear os arquivos atuais nos 5 da entrega (não executar agora) | P20 | 11:02–11:40 | A fazer |
| P22 | 5 | Apresentação | Presença obrigatória; avaliação do código e apresentação oral | - | Preparar o roteiro a partir do PDF e dos gráficos | P20 | - | A fazer |

## Detalhamento

### P01 · Regra de alteração do modelo

> **Resultado:** `data_inscricao` e `p_data_ref` removidos (DEC-019, substitui a DEC-007); regra registrada no topo do `DECISIONS.md`.

**O que vale:** o trabalho é **otimizar** um modelo relacional já mapeado.

- **Pode:** criar constraints (`UNIQUE`, `NOT NULL`, `CHECK`, FK), remodelar
  chaves (inclusive com surrogate), mudar tipos e criar índices, views, triggers
  e functions.
- **Não pode:** criar ou remover tabelas, mudar relacionamentos, criar colunas
  que não sejam de chave, nem remover atributos derivados (`qtd_users` e
  `qtd_visualizacoes` ficam).

**Situação:** as surrogates `id_canal` e `id_video` são remodelagem de chave,
então são aceitas. A `Inscricao.data_inscricao` (DEC-007) **é uma coluna nova
que não é chave**. Ela conflita com a regra.

**O que fazer:**

- [x] Revisar a DEC-007. Ou remove a coluna e o parâmetro `p_data_ref` dos itens
  6, 9 e 11 (o minimundo não pede data), ou registra a justificativa e o risco de
  desconto na avaliação. Recomendação: remover, porque o minimundo já diz que só
  os membros vigentes ficam no sistema.
- [x] Conferir que nenhuma outra DEC cria coluna comum.
- [x] Registrar a regra no topo do `DECISIONS.md`, como critério para as próximas
  decisões.

### P02 · Cenário de volumetria

> **Resultado (2026-11-15):** cenário com vídeo longo **e curto** (escolha do grupo). Conta de capacidade e fontes na DEC-020.

**O que vale:** o grupo define o tipo de vídeo e o volume esperado. O argumento
é livre, mas precisa ser **o mesmo** no DDL (tipos de chave), no seed (volumes e
proporções), nos índices e no PDF.

**O professor sugeriu** fazer a conta: por exemplo, todos os streamers filmando
24 horas, com um vídeo a cada 10 minutos. Se for só vídeo longo (mais de 5 min),
o `BIGINT` não estoura. Se forem shorts de 10 em 10 segundos replicados em 60
plataformas, a conversa muda.

**O que fazer:**

- [x] Escrever uma DEC de cenário de referência com:
  - **escopo:** quais plataformas entram (só streaming de jogos ou também vídeo
    curto) e quantas;
  - **taxas:** streamers ativos, vídeos por streamer por dia, comentários por
    vídeo (com cauda longa), porcentagem de comentários com doação (no mundo
    real, de 1% a 5%), membros por canal e canais patrocinados;
  - **horizonte:** por exemplo, 10 anos de operação;
  - **resultado:** o máximo de linhas por tabela nesse horizonte e, dele, o tipo
    de cada chave (P03 a P05).
- [x] Usar o mesmo cenário, em escala menor, para os volumes do seed v3 (P11).

### P03 · Chave de `Video`: `BIGINT` ou UUID

> **Resultado:** UUID v7 por function própria (`uuid_v7()`), DEC-021. Medido: +37% em `Video`, +28% no índice da PK de `Comentario`.

**Contexto:** hoje é `id_video BIGINT GENERATED ALWAYS AS IDENTITY` (DEC-015).
O professor levantou que, com várias plataformas, faz sentido pensar em outro
identificador, talvez UUID.

**Argumentos para comparar e registrar:**

| Critério | `BIGINT IDENTITY` | UUID |
|---|---|---|
| Capacidade | 9,22 × 10^18, o que sobra para qualquer cenário | Praticamente ilimitada |
| Tamanho | 8 bytes | 16 bytes, repetidos em `Participa`, `Comentario`, `Doacao` e nas 4 tabelas de pagamento |
| Geração | Central, uma sequence no banco | Distribuída: cada plataforma ou crawler gera o id sem consultar o banco |
| Inserção no B-tree | Sempre no fim do índice (sequencial) | v4 é aleatório e espalha páginas (*page split*); v7 é ordenado no tempo e se comporta como sequencial |
| Suporte no Postgres 17 | Nativo | `gen_random_uuid()` gera v4; `uuidv7()` nativo só chega no Postgres 18, então v7 exige function própria ou upgrade |

**O que fazer:**

- [x] Decidir com base no P02. Se o cenário for ingestão de muitas plataformas
  com geração distribuída, o UUID se justifica e a recomendação é v7. Se for um
  banco central, o `BIGINT` já basta e é menor.
- [x] Se escolher UUID, medir o tamanho de `Comentario` e dos índices, do mesmo
  jeito que na DEC-017.
- [x] Propagar o tipo escolhido para todas as FKs e para os parâmetros das
  procedures.

### P04 · Chave de `Comentario`

> **Resultado:** `seq INTEGER` confirmado; `seq_pg`, `seq_doacao` e `seq_plataforma` passaram a `INTEGER` (DEC-024); geração pelo T3/T4/T5 (DEC-027).

**O que vale:** o professor confirmou que comentário não comporta identificador
próprio. A chave fica dependente do vídeo, `(id_video, seq)`, como na DEC-017.

**O que fazer:**

- [x] Confirmar `seq INTEGER` pelo cenário (máximo de comentários por vídeo).
- [x] Resolver a geração de `seq` por vídeo, que está em aberto na DEC-017: é o
  trigger T3.
- [x] Se P03 mudar o tipo de `id_video`, refazer a medida de tamanho.

### P05 · Surrogate em `Usuario`

> **Resultado:** `id_usuario BIGINT` com `UNIQUE (nick)`, DEC-022. Medido: `Comentario` igual (alinhamento), `Inscricao` −12% de heap. `id_canal` também passou a `BIGINT` (DEC-023).

**Contexto:** `Usuario.nick VARCHAR(255)` é a PK e se repete em
`PlataformaUsuario`, `StreamerPais`, `Canal`, `Inscricao`, `Participa` e
`Comentario`. `Comentario` é a maior tabela. A DEC-017 já apontou que o
`nick_usuario` é o que mais pesa na linha, mas isso não foi medido.

**O que fazer:**

- [x] Decidir se adota `id_usuario` (`INTEGER` ou `BIGINT`, pelo P02) como PK,
  com `nick` em `UNIQUE NOT NULL`.
- [x] Se adotar: trocar as 6 FKs e medir `Comentario` e `Inscricao` antes e
  depois. O índice `idx_inscricao_nick_membro` (DEC-018) passaria a ser sobre
  `id_usuario`.
- [x] Se não adotar: registrar o porquê, por exemplo que o nick é estável e
  curto na prática e que o custo é aceitável no cenário.

### P06 · Constraints (item mandatório 2)

> **Resultado:** DEC-025 (`UNIQUE` em `TxID`, `IdPayPal`, `(nro_plataforma, nro_usuario)`, passaporte, id nacional, nome do país; `NOT NULL` em país de residência, datas e gif; `CHECK visu_simul <= visu_total`).

**Situação:** DEC-009 a 016 cobrem `UNIQUE`, `NOT NULL` e `CHECK` nas tabelas
de referência e nos valores.

**O que fazer:**

- [x] Revisar depois de P03 a P05: toda chave natural que deixou de ser PK
  precisa de `UNIQUE` + `NOT NULL`.
- [x] Avaliar `UNIQUE (TxID)` em `BitCoin` e `UNIQUE (IdPayPal)` em `PayPal`.
  São regras de negócio reais, porque uma transação não se repete, mas cada uma
  custa um índice numa tabela que cresce. Decidir e justificar.

### P07 · Conversão de moeda

> **Resultado:** o grupo escolheu **gravar em USD no `INSERT`** (trigger T11, valor histórico), DEC-026. `pais_residencia` virou `NOT NULL` (DEC-025).

**Decisão do grupo:**

- **Patrocínio:** sempre em USD, sem conversão. O valor vem de um contrato
  externo, como o minimundo diz.
- **Doação:** convertida para USD pela moeda do **país de residência** do
  usuário que fez o comentário. O caminho é `Comentario.nick_usuario` →
  `Usuario.pais_residencia` → `Pais.moeda` → `Conversao.fator_conver`.
- **Membros:** continuam como já estão (DEC-001 e DEC-002).

**Falta decidir quando converter.** O professor disse que as duas formas estão
corretas:

| Opção | O que representa | Implementação |
|---|---|---|
| Converter na consulta | Valor **corrigido**: quanto aquilo vale hoje | Join com `Conversao` nas procedures (ou na view V1). O `Doacao.valor` fica em moeda local |
| Gravar em USD ao inserir | Valor **histórico**: quanto o streamer recebeu no dia | Trigger T11 converte `valor` no `INSERT`. O valor local se perde, porque não pode criar coluna (P01) |

Recomendação: **converter na consulta**. É o mesmo critério dos membros, não
exige trigger nem perde o valor local, e o professor comentou que o valor
corrigido serve bem para o propósito do sistema, que é escolher qual canal
patrocinar. Segundo ele, a maioria dos grupos está gravando, então a escolha
precisa ser justificada.

**O que fazer:**

- [x] Registrar a DEC, que fecha os pontos em aberto das DEC-003 e DEC-004.
- [x] Ajustar os itens 4, 7, 10 e 11 (de preferência pela view V1).
- [x] No seed v3, gerar `Doacao.valor` em moeda local, com magnitude coerente
  com a moeda (P11).
- [x] Definir o tratamento de usuário sem país: manter USD com fator 1, como na
  DEC-001, ou tornar `pais_residencia` `NOT NULL`.

### P08 · Triggers (item mandatório 5)

> **Resultado:** T1 a T11 adotados (T5, T9 e T10 incluídos; T11 porque P07 escolheu gravar), em `triggers.sql`, DEC-027. 37 casos em `testes_triggers.sql`, todos OK.

**O que vale:** todos os triggers necessários para manter a consistência,
derivados do minimundo. Eles ficam num **arquivo separado**, executado depois da
carga. O professor vai separar os triggers justamente para a inserção dos dados
não travar.

**Consequência:** como os triggers não existem durante a carga, o seed v3
precisa **obedecer às mesmas regras** e **calcular os atributos derivados**
sozinho.

**Especificação proposta:**

| ID | Regra (origem) | Tabela e evento | Comportamento | Status |
|---|---|---|---|---|
| T1 | `Canal.qtd_visualizacoes` é derivado (relacional) e é a soma bruta de `Video.visu_total` (professor, 16:20–17:38) | `Video`: `AFTER INSERT`, `UPDATE OF visu_total, id_canal`, `DELETE` | Aplica o delta (`NEW − OLD`, nulo conta como 0) no canal. Se `id_canal` mudar, subtrai do antigo e soma no novo | Definido |
| T2 | `Plataforma.qtd_users` é derivado (relacional); o professor citou os dois campos juntos (17:38) | `PlataformaUsuario`: `AFTER INSERT`, `DELETE`, `UPDATE OF nro_plataforma` | Soma +1 ou −1 na plataforma. Interpretação: usuários com conta na plataforma | Definido |
| T3 | `seq` do comentário "depende do vídeo" (minimundo); geração em aberto (DEC-017) | `Comentario`: `BEFORE INSERT` | Se `seq` vier nulo, trava a linha do vídeo (`SELECT … FOR UPDATE`) e usa `max(seq) + 1`, que é barato porque a PK `(id_video, seq)` serve. Contra: serializa comentários simultâneos no mesmo vídeo | Definido |
| T4 | `seq_pg` da doação "depende do vídeo, do usuário e do comentário" (minimundo) | `Doacao`: `BEFORE INSERT` | `max(seq_pg) + 1` por comentário, travando a linha do comentário | Definido |
| T5 | `seq_plataforma` "depende do usuário, do comentário e da plataforma" (minimundo) | `MecanismoPlat`: `BEFORE INSERT` | Sequencial por (usuário, plataforma). **Interpretação a confirmar** | Adotado (DEC-027) |
| T6 | A especialização de doação é disjunta: "d" no ER, uma das 4 formas | `BitCoin`, `PayPal`, `CartaoCredito`, `MecanismoPlat`: `BEFORE INSERT`, `UPDATE` | Rejeita se a mesma doação já existe em outra forma. Totalidade (toda doação ter forma) fica como trigger de constraint adiado, a avaliar | Definido |
| T7 | Coerência temporal (escolha do grupo, não cabe em `CHECK` porque envolve outra tabela) | `Comentario`, `Video`, `Canal`: `BEFORE INSERT`, `UPDATE` | Exige comentário ≥ vídeo ≥ canal ≥ fundação da plataforma (e inscrição ≥ canal, se a DEC-007 ficar) | Definido |
| T8 | "Existem cinco níveis de membros" (minimundo) | `NivelCanal`: `BEFORE INSERT`, `UPDATE OF id_canal` | Rejeita o sexto nível de um canal | Definido |
| T9 | O dono do canal e quem participa do vídeo são streamers (minimundo) | `Canal`, `Participa`: `BEFORE INSERT`, `UPDATE` | Exige que o nick tenha linha em `StreamerPais`. **Interpretação:** streamer é o usuário com passaporte | Adotado (DEC-027) |
| T10 | Relacionamento "tem conta" do ER | `Canal` (e talvez `Comentario`): `BEFORE INSERT` | Exige conta em `PlataformaUsuario` na plataforma do canal | Adotado só em `Canal` (DEC-027) |
| T11 | Só se P07 escolher gravar em USD | `Doacao`: `BEFORE INSERT` | Converte `valor` para USD pela moeda do usuário | Adotado (P07 escolheu gravar) |

O minimundo também diz que não há histórico de patrocínios e membros. Isso já
se resolve com `DELETE` e não precisa de trigger.

**O que fazer:**

- [x] Fechar T5, T9, T10 e T11 e registrar a DEC de triggers.
- [x] Implementar num arquivo próprio (por exemplo `triggers.sql`).
- [x] Para carga em lote, avaliar triggers por comando com tabelas de transição
  (`REFERENCING NEW TABLE`) em T1 e T2, para não atualizar a mesma linha de canal
  milhares de vezes.
- [x] Teste de cada trigger em P12: um caso que passa e um que é rejeitado, mais
  a conferência dos derivados depois de `INSERT`, `UPDATE` e `DELETE`.

### P09 · Views virtuais e materializadas (item mandatório 3)

> **Resultado:** V1 e V2 virtuais, V3 e V4 materializadas, V5 não criada; refresh periódico por `sp_refresh_views()`; o índice de view materializada **conta** no teto de 5. DEC-028.

**Definições:**

- **View virtual** (`CREATE VIEW`): é só uma consulta salva, sem dado gravado.
  Cada uso reexecuta a consulta sobre as tabelas base, e o planejador costuma
  expandir a view dentro da consulta. Serve para centralizar regras (filtros,
  joins, conversão) e simplificar as functions. Não acelera a consulta por si só.
- **View materializada** (`CREATE MATERIALIZED VIEW`): grava o resultado como uma
  tabela física. A leitura é imediata, mas o dado fica desatualizado até um
  `REFRESH MATERIALIZED VIEW`. O `REFRESH … CONCURRENTLY` não bloqueia leituras,
  mas exige um índice `UNIQUE` na view. Serve para agregações caras sobre tabelas
  grandes, quando um atraso no dado é aceitável.

**Candidatas (até 5, cada uma justificada):**

| ID | Tipo | Conteúdo | Atende | Por quê |
|---|---|---|---|---|
| V1 | Virtual | Doações não recusadas, com o valor em USD pelo país do usuário e com `id_canal` | Itens 4, 7, 10 e 11 | Centraliza a regra de status e de conversão (P07) num lugar só |
| V2 | Virtual | Inscrições com o valor do nível em USD | Itens 6, 9 e 11 | Centraliza a regra de conversão dos membros (DEC-001) |
| V3 | Materializada | Interações por vídeo: comentários online, offline e total | Itens 2 e 3 | `Comentario` é a maior tabela e agregá-la domina o tempo (DEC-018) |
| V4 | Materializada | Faturamento por canal: patrocínio, membros, doações e total em USD | Itens 8 a 11 (top-k) | O top-k ordena por um agregado, o que nenhum índice sobre as tabelas base atende. Para escolher patrocínio, um atraso de horas é aceitável |
| V5 | A definir | Streamers e canais por plataforma | Item 12 | Candidata se o item 12 ficar caro |

**O que fazer:**

- [x] Fechar as views e registrar a DEC (justificativa individual e estratégia de
  refresh: periódico, como em um job diário, ou disparado).
- [x] Decidir se o índice de uma view materializada conta no teto de 5 índices
  e registrar. Recomendação: contar, para não haver dúvida na avaliação.
- [x] Medir em P17: consulta direta × view virtual × view materializada.

### P10 · Procedures (item mandatório 6)

> **Resultado:** 12 functions (item 12 incluído), DEC-029; `queries.sql` com valores reais do seed v3.

**Situação:** 11 functions em `procedures.sql`. O item 12 (ponto extra) não
existe. O `queries.sql` ainda usa filtros do seed v1 (por exemplo
`'ninja_1962 TV'`) e cita a ordem de execução antiga.

**O que fazer:**

- [x] Ajustar as assinaturas e os joins ao DDL final (P03 a P05).
- [x] Aplicar a conversão das doações (P07), de preferência pelas views V1 e V2.
- [x] Implementar o item 12: top-k plataformas por quantidade de streamers **e**
  de canais, com filtro opcional por plataforma.
- [x] Atualizar o `queries.sql` com valores reais do seed v3 (P11).
- [x] Reescrever as functions para desempenho em P13 (não aqui).

### P11 · Seed v3

> **Resultado:** `seed_v3.sql` parametrizado por escala (`-v escala=`); na escala 1, 5 mi de comentários e carga em ~9 min. Relatório em `seed_v3_RELATORIO.md`, DEC-031.

**O que vale (professor e grupo):**

- parte de um **banco virgem** com o **DDL completo** (final);
- **o máximo de dados possível**, idealmente centenas de milhares de linhas nas
  tabelas grandes;
- o limite de 1.000 a 10.000 do item mandatório 1 é **só referência**: o
  professor disse que não espera 10 mil países;
- **distribuição desbalanceada e realista:** canais com muito mais vídeos que
  outros e vídeos com muito mais comentários que outros;
- correlações coerentes, como mais visualizações levando a mais comentários,
  membros e patrocínio;
- o conteúdo pode ser artificial;
- tudo coerente com o cenário de P02.

**Requisitos:**

- [x] **Tabelas pequenas no tamanho real:** cerca de 160 moedas, cerca de 195
  países e algumas dezenas de plataformas reais. Isso acaba com as 960 a 990
  linhas fictícias do seed v2. Registrar que o professor autorizou ficar abaixo
  de 1.000 nessas tabelas.
- [x] **Tabelas grandes no máximo viável** no Docker local (limite de 5,8 GB de
  memória). Proposta inicial, a ajustar pelo P02:

  | Tabela | Volume alvo |
  |---|---|
  | `Usuario` | ~500 mil |
  | `PlataformaUsuario` | ~800 mil |
  | `StreamerPais` | ~25 mil |
  | `Canal` | ~40 mil |
  | `NivelCanal` | 5 por canal (~200 mil) |
  | `Inscricao` | ~600 mil |
  | `Patrocinio` | ~15 mil |
  | `Video` | ~1 milhão |
  | `Participa` | ~300 mil |
  | `Comentario` | 2 a 5 milhões (pela DEC-017, cerca de 0,2 GB por milhão) |
  | `Doacao` | 1% a 5% dos comentários |

- [x] **Corrigir as distorções do seed v2:** 50% dos comentários com doação vira
  1% a 5%; a pirâmide achatada (1,7 comentário por vídeo) vira cauda longa; e 25%
  de usuários streamers vira uma proporção realista.
- [x] **Coerência com os triggers (P08):** `seq` contínuo por vídeo e por
  comentário, no máximo 5 níveis por canal, especialização disjunta e datas em
  ordem (incluindo o Mixer encerrado em 2020).
- [x] **Atributos derivados calculados pelo próprio seed:** `qtd_visualizacoes` e
  `qtd_users`. Prefira calculá-los no `INSERT` em vez de `UPDATE` final, para não
  dobrar o tamanho com tuplas mortas (problema apontado no relatório do seed v2).
- [x] **Valores de doação em moeda local** (P07).
- [x] **Mantém o que funcionou no v2:** checagem de banco vazio,
  `ON_ERROR_STOP`, uma transação só, `setseed` para reprodutibilidade e chaves
  obtidas por join em vez de números fixos.
- [x] **Troca a checagem de 1.000 a 10.000 linhas** por uma checagem de
  sanidade: mínimo por tabela e derivados batendo com as somas.
- [x] **Desempenho da carga:** inserção por conjunto (`generate_series`), sem
  laço linha a linha; criar os índices de apoio depois da carga.
- [x] **Amostra para entrega:** como o arquivo completo pode ficar grande, o
  aviso do Classroom permite link do Drive. Avaliar o seed parametrizado por
  escala, com uma escala pequena para teste rápido.
- [x] Gerar o relatório `seed_v3_RELATORIO.md`, no mesmo formato do v2.

### P12 · Carga, validação e teste dos triggers

> **Resultado:** cadeia completa com código de saída 0 num banco novo; derivados conferidos; 37 casos de trigger OK. Ver `seed_v3_RELATORIO.md`.

**O que fazer:**

- [x] Rodar num banco novo: `ddl.sql` → `seed_v3.sql` → PL/pgSQL (functions,
  views e triggers) → `queries.sql`.
- [x] `VACUUM ANALYZE` depois da carga, para que as estatísticas valham em P14.
- [x] Conferir os derivados: `qtd_visualizacoes` = `SUM(visu_total)` e
  `qtd_users` = `COUNT` de `PlataformaUsuario`.
- [x] Executar os casos de teste dos triggers T1 a T10.
- [x] Registrar o tamanho de cada tabela e índice (`pg_relation_size`,
  `pg_indexes_size`).
- [x] Rodar todas as chamadas do `queries.sql` e conferir que os resultados fazem
  sentido.

### P13 · Otimização das consultas

> **Resultado:** DEC-033. Filtrar antes de agregar: item 2 filtrado 3,7 → 0,8 s e item 3 filtrado 6,8 → 1,0 s (a frio); com a V3, 0,33 s e 0,18 s. Sem filtro, a reescrita direta piorou; a V3 resolve o item 3 (6,0 → 0,85 s). Item 3 reescrito em dois ramos excludentes.

**O que vale:** o professor orientou a deixar as consultas o melhor possível
**antes** dos índices, porque os índices vêm em cima delas.

**O que fazer:**

- [x] Medir a **linha de base**: `EXPLAIN (ANALYZE, BUFFERS)` de todas as
  functions, com e sem filtro, só com os índices de PK e `UNIQUE`, usando o
  protocolo a frio de P16.
- [x] Reescrever o que estiver ruim:
  - itens 2 e 3 agregam **todo** `Comentario` antes de filtrar o canal ou o
    streamer (DEC-018); aplicar o filtro antes de agregar;
  - evitar função sobre coluna no `WHERE`, que impede o uso de índice;
  - manter `LANGUAGE sql STABLE`, para o planejador expandir a function e
    resolver o padrão `p IS NULL OR col = p`;
  - avaliar a ordenação por texto (`cn.nome`), que a DEC-018 mostrou ser cara.
- [x] Medir de novo e guardar o antes e depois da reescrita, que também entra
  nos gráficos.

### P14 · Inventário de predicados e seletividade

> **Resultado:** `bench/predicados.md` (inventário) e `bench/estatisticas.sql`/`.txt` (`pg_stats` e seletividade real). Concentrados: `status <> 'recusado'` (90%), `coment_on`, plataforma YouTube (28%).

**Metodologia do professor:**

1. Olhar a complexidade das consultas e a **similaridade dos predicados**. Os
   predicados tendem a se repetir entre consultas e a não mudar com o tempo.
2. Olhar a **distribuição** da coluna: se o filtro devolve grande parte da
   tabela, o índice não ajuda. Exemplo dele: se quase todos os streamers são
   americanos, indexar o país não adianta.
3. A partir do **tipo de predicado**, escolher o tipo de índice (P15).

**O que fazer:**

- [x] Montar uma tabela de inventário com consulta, predicado, tipo (igualdade,
  faixa, join, `GROUP BY`, `ORDER BY`/`LIMIT`), coluna, seletividade estimada e
  candidato a índice.
- [x] Medir a distribuição sobre o seed v3 com `pg_stats` (`n_distinct`,
  `most_common_vals`, `most_common_freqs`, `histogram_bounds`) e com contagens
  por valor.
- [x] Marcar os predicados de distribuição muito concentrada, como
  `status <> 'recusado'` (cerca de 90% das linhas), como **não indexar** ou
  candidato a índice parcial.

### P15 · Índices: hash e B-tree (item mandatório 4)

> **Resultado:** DEC-034 (substitui a DEC-018), `indices.sql`. Cinco índices: os 2 `UNIQUE` das materializadas + `Inscricao (id_membro)`, `Canal (id_streamer)` e `Video (id_canal) INCLUDE (visu_total)`. Hash medido nos dois de igualdade: mesmas páginas, índice maior, fica B-tree. `Canal (nro_plataforma)` descartado (sem ganho).

**Regras de escolha:**

- **B-tree:** igualdade, faixa (`<`, `>`, `BETWEEN`), `ORDER BY`, `LIMIT` (top-k)
  e prefixo de chave composta. É o padrão e é o único tipo que aceita `UNIQUE`.
- **Hash:** só igualdade. No Postgres não aceita `UNIQUE`, multicoluna, faixa
  nem ordenação. Pode ser menor que o B-tree em chaves largas, como texto. É
  candidato quando o predicado é **só** `col = valor` sobre uma coluna larga (por
  exemplo `nick`, se P05 mantiver o nick como chave).
- **Composto:** a ordem das colunas segue a coluna mais filtrada primeiro.
- **Parcial e `INCLUDE`:** para predicados de distribuição concentrada e para
  permitir *index-only scan*.
- Tipicamente, os índices de apoio serão **secundários sobre parte da chave
  primária** de outra tabela (FKs que o Postgres não indexa sozinho).

**O que fazer:**

- [x] Para cada candidato de P14, definir tipo e colunas e justificar pelo
  predicado.
- [x] Onde o predicado for só de igualdade, **medir hash e B-tree** e escolher
  pelo resultado (tempo, buffers, tamanho e overhead de inserção).
- [x] Respeitar o teto de 5 índices (incluindo os de views materializadas, se o
  grupo decidir contar) e considerar o overhead de inserção em cada um.
- [x] Refazer a DEC-018: os dois índices atuais foram medidos com cache quente,
  dados uniformes e a chave antiga. Mantê-los ou trocá-los conforme a nova
  medição.
- [x] Criar os índices **depois** da carga, no arquivo de PL/pgSQL ou num bloco
  próprio do DDL.

### P16 · Protocolo de medição a frio

> **Resultado:** DEC-032, `bench/medir.sh` (stop → drop_caches → start → 1 consulta), no container separado `stream-bench`. Comprovado: `shared hit` = 6 e o resto `shared read` na raiz das medidas a frio.

**O que vale:** o professor alertou que o cache distorce a medição. Repetir a
mesma consulta faz ela vir da memória. Ele também alertou que, com poucos dados,
um bloco guarda muita coisa e a árvore vira só uma raiz em memória, então o
índice não faz diferença. Por isso a medição só vale sobre o seed v3 cheio.

Há **dois caches** a esvaziar antes de cada medida:

1. **`shared_buffers` do Postgres:** some ao matar e reiniciar o processo, por
   exemplo com `docker restart steam-do-bedo-db`.
2. **Cache de páginas do sistema operacional:** no Docker Desktop do Mac, ele
   fica na VM Linux e **sobrevive** ao restart do container. Limpar com
   `docker run --rm --privileged --pid=host alpine sh -c "sync; echo 3 > /proc/sys/vm/drop_caches"`.

**O que fazer:**

- [x] Escrever um script que, para cada medida: reinicia o Postgres, limpa o
  cache do SO, espera o banco aceitar conexão e roda **uma** consulta com
  `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.
- [x] **Comprovar que a medida foi a frio:** `shared read` maior que 0 e
  `shared hit` baixo na raiz do plano. Opcionalmente, conferir com
  `pg_buffercache`.
- [x] Fixar e registrar a configuração: `jit`, `max_parallel_workers_per_gather`,
  `work_mem`, `shared_buffers` e a versão do Postgres.
- [x] Repetir N vezes (por exemplo 5) e usar a **mediana**.
- [x] Medir também a quente (sem reiniciar) como cenário complementar, deixando
  claro qual é qual.

### P17 · Aferição

> **Resultado:** `bench/aferir.py` gerou `bench/resultados.csv` (650 medidas), `bench/planos/*.json`, `bench/escrita.csv`, `bench/tamanhos.csv` e `bench/configuracao.txt`.

**Matriz de cenários:**

| Dimensão | Valores |
|---|---|
| Consulta | Itens 1 a 12, com e sem filtro |
| Índices | Sem índices de apoio, só com os de PK e `UNIQUE` / com os índices de P15 / hash × B-tree onde houver comparação |
| Views | Consulta direta / view virtual / view materializada (P09) |
| Cache | Frio (P16) / quente |
| Escrita | Overhead de `INSERT` em lote com e sem cada índice e custo do `REFRESH` das views materializadas |

**O que fazer:**

- [x] Automatizar a matriz e salvar um CSV com consulta, cenário, cache,
  execução, tempo de planejamento, tempo de execução, nó principal do plano (Seq,
  Index, Bitmap ou Index Only), `shared read`, `shared hit` e linhas.
- [x] Guardar os planos em JSON, como evidência para a apresentação.

### P18 · Gráficos

> **Resultado:** `bench/graficos.py` gera 7 PNGs em `bench/graficos/` (dependência em `bench/requirements.txt`).

**O que fazer** (por exemplo em Python com matplotlib, lendo o CSV de P17):

- [x] Tempo por consulta, com e sem índice, a frio (barras agrupadas e escala
  log, porque os ganhos variam em ordens de grandeza).
- [x] Buffers lidos com e sem índice, que mostram o ganho em I/O e não só em
  tempo.
- [x] Antes e depois da reescrita das consultas (P13).
- [x] Consulta direta × view virtual × view materializada.
- [x] Ganho de leitura × overhead de inserção e tamanho de cada índice (o
  argumento do teto de 5).
- [x] Frio × quente, para justificar o protocolo.
- [x] Exportar em PNG, para o PDF e a apresentação.

### P19 · `DECISIONS.md`

> **Resultado:** DEC-019 a DEC-034; DEC-007 e DEC-018 marcadas como substituídas, pontos em aberto das DEC-001, 003, 004, 014, 015 e 017 fechados com referência à DEC nova; todo `-- DEC-NNN` do código existe no arquivo.

- [x] Novas DECs para o cenário (P02), a chave de `Video` (P03), a chave de
  `Usuario` (P05), a conversão da doação (P07), os triggers (P08), as views
  (P09), o volume do seed v3 autorizado pelo professor (P11) e os índices
  revisados (P15).
- [x] Marcar como substituídas as partes antigas: as medições da DEC-018, a
  DEC-007 se a coluna sair e o ponto em aberto das DEC-003 e 004.

### P23 · Item 12 (desafio), etapa final

> **Resultado:** DEC-035 (substitui a parte do item 12 da DEC-029). Streamer da
> plataforma = dono de canal nela (`COUNT(DISTINCT)`); "E" = ordem lexicográfica
> (streamers, depois canais), pelo alcance de público; posição global por `rank()`
> antes do filtro; empates no corte de k entram todos; k < 1 e plataforma inexistente
> dão erro. Medido a frio (~60 a 100 ms; V5 materializada e índice de cobertura
> medidos e descartados) e validado contra contagem independente (0 divergências).

- [x] DEC de interpretação escrita antes do código, com as alternativas descartadas.
- [x] Function revista em `procedures.sql`, com métricas auxiliares.
- [x] Medição a frio com e sem índices e views (`bench/resultados.csv`, `08_item12.png`).
- [x] Validação no `queries.sql`: sem filtro, plataforma grande, pequena, fora do
  top-k, empate, k maior que o total, parâmetros inválidos e contagem independente.

### P20 · PDF de decisões

- [ ] O PDF é curto, em torno de 2 páginas, **só com decisões e
  justificativas**. Os detalhes vão nos comentários do código, que o professor
  vai rodar.
- [ ] Gerar a partir de um markdown enxuto: o `DECISIONS.md` completo continua
  como registro interno.
- [ ] Incluir 2 ou 3 gráficos de P18.

### P21 · Formato de entrega

Não reorganizar agora. Mapeamento previsto:

| Arquivo da entrega | Origem no projeto hoje |
|---|---|
| 1. DDL de construção das tabelas | `ddl.sql` |
| 2. PL/pgSQL: functions, triggers, views e outros | `procedures.sql` + triggers (P08) + views (P09) + índices, se não ficarem no DDL |
| 3. Dados para inserção | `seed_v3.sql`, pelo Drive se for grande |
| 4. Chamadas das consultas e functions para teste | `queries.sql` + testes dos triggers |
| 5. PDF curto de decisões | P20 |

Pontos de atenção:

- O enunciado pede `.zip` com `README.md`, e o aviso do Classroom (mais recente)
  pede 5 arquivos. Seguir o Classroom e manter o `README.md` com o passo a passo
  de execução de qualquer forma.
- No fim: remover ou arquivar `seed.sql` e `seed_v2.sql`, e corrigir o nome do
  `READEME.md`.
- **Todos os integrantes** fazem upload. Link do Drive com permissão para
  `@id.uff`.

### P22 · Apresentação

- [ ] Presença obrigatória para a nota (avaliação do código e apresentação oral).
- [ ] Roteiro: cenário (P02) → chaves → regra de moeda → triggers → views →
  metodologia de índices → gráficos.

## Formato de entrega (aviso do Classroom)

Texto enviado pelo professor no Classroom:

> Prezad@s,
>
> Lembrete do Trabalho Final de Disciplina:
> Para o trabalho final devem ser enviados 5 arquivos no Classroom:
> 1 - Arquivo DDL de construção das tabelas
> 2 - Arquivo com plsql, incluindo functions, triggers, views e outros implementados pelo grupo.
> 3 - Arquivos com os dados para inserção
> 4 - Arquivos com as chamadas das consultas/funções para teste
> 5 - Arquivo .pdf curto contendo as decisões de projeto e justificativas de design do grupo.
>
> Arquivos grandes podem ser substituídos com link do Drive com devida permissão para @id.uff.
>
> TODOS OS INTEGRANTES DEVEM FAZER UPLOAD!
>
> A apresentação do trabalho final na semana que vem tem presença obrigatória para nota (avaliação do código + apresentação oral).

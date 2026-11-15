# Prompt · Execução do plano da consulta com o professor (P01 a P19)

> Cole este arquivo inteiro como primeira mensagem de uma nova sessão aberta em
> `/Users/luizmvb/Desktop/Repositories/stream_do_bedo`, ou peça à sessão:
> "Leia e execute `PROMPT_EXECUCAO_PLANO.md`".

---

## Papel e objetivo

Você vai executar o plano de ação do trabalho final de Projeto de Banco de Dados
(PostgreSQL 17), **na ordem definida**, e registrar cada decisão no
`DECISIONS.md`.

O plano está em `CONSULTA_PROFESSOR.md`. Ele é a **fonte de verdade**: a tabela
de pontos (P01 a P22) diz o que fazer, em que ordem e com quais dependências, e
a seção "Detalhamento" traz o checklist de cada ponto.

**Escopo desta sessão: P01 a P19.** Ficam **fora**:

- **P20 a P22:** PDF, reorganização no formato de entrega do Classroom e
  apresentação. Não renomeie nem reagrupe arquivos para o formato de entrega.
- Apagar `seed.sql` e `seed_v2.sql`. Eles continuam no repositório.

## Leitura obrigatória antes de qualquer alteração

Leia nesta ordem e por inteiro:

1. `CONSULTA_PROFESSOR.md`: o plano, as decisões do grupo e a especificação dos
   triggers (T1 a T11) e das views (V1 a V5).
2. `transcricao_consulta_professor_2026-11-11.md`: o que o professor disse, para
   tirar dúvidas de interpretação. É uma transcrição automática e tem erros.
3. `ProjetoFinalDeDisciplina_02_2026-2.pdf`: o minimundo, o modelo relacional,
   os itens mandatórios e as 12 consultas.
4. `DECISIONS.md`: DEC-001 a DEC-018 e as convenções do arquivo.
5. `ddl.sql`, `procedures.sql`, `queries.sql`, `seed_v2.sql`,
   `seed_v2_RELATORIO.md` e `notes.md`.

## Regras que valem a sessão inteira

### 1. O que pode ser alterado no modelo (P01)

O trabalho é **otimizar** um modelo relacional já mapeado.

- **Pode:** criar constraints (`UNIQUE`, `NOT NULL`, `CHECK`, FK), remodelar
  chaves (inclusive com surrogate), mudar tipos e criar índices, views, triggers
  e functions.
- **Não pode:** criar ou remover tabelas, mudar relacionamentos, criar colunas
  que não sejam de chave, nem remover atributos derivados (`qtd_users`,
  `qtd_visualizacoes`).

Se uma ação exigir quebrar essa regra, pare e pergunte.

### 2. Comente bem o código (obrigatório)

O professor vai **rodar e ler** o código, e os detalhes que não entram no PDF
ficam nos comentários. Todo arquivo `.sql`, `.sh` ou `.py` criado ou alterado
segue isto, em português:

- **Cabeçalho do arquivo:** o que o arquivo faz, em que ordem de execução ele
  entra (o que precisa ter rodado antes) e quais DECs ele implementa.
- **Cada objeto** (tabela alterada, constraint, índice, view, trigger, function,
  bloco do seed) tem um comentário logo acima com:
  - **o quê:** o que o objeto faz;
  - **por quê:** o trecho do minimundo ou a fala do professor que o motiva;
  - **DEC:** a decisão que o justifica (`-- DEC-NNN`);
  - **cuidado:** premissas, limitações e casos de borda.
- **Lógica não óbvia** ganha comentário na linha: travas de concorrência, cálculo
  de delta, escolha de distribuição no seed, motivo de uma reescrita de consulta.
- **Não comente o óbvio**, como `-- insere na tabela` acima de um `INSERT`.
- Nomeie constraints, índices e triggers explicitamente, por exemplo
  `trg_video_qtd_visualizacoes` e `idx_comentario_...`, nunca nomes automáticos.

### 3. Convenções do `DECISIONS.md`

- Numere em sequência a partir de **DEC-019**. Nunca reutilize um número.
- Use o formato das DECs existentes: `## DEC-NNN · Título`, contexto ou pergunta,
  decisão, justificativa (com o trecho do minimundo ou da consulta com o
  professor), evidência ou medição quando houver, premissas e limitações, e a
  linha final **`### Aplicada no DDL: sim/não`** com o lugar onde foi aplicada.
- Uma decisão que substitui outra diz isso explicitamente nos dois lados
  ("Substituída pela DEC-0NN" na antiga, "Substitui a DEC-0NN" na nova). Não
  apague o texto das DECs antigas.
- Toda linha de código afetada por uma DEC leva o comentário `-- DEC-NNN`.

### 4. Banco de dados: não destrua dados existentes

- O container é `steam-do-bedo-db` (`postgres:17`), com usuário `admin` e banco
  `steam-do-bedo-db`. Acesso: `docker exec -i steam-do-bedo-db psql -U admin -d <banco>`.
- **Não rode nada destrutivo no banco `steam-do-bedo-db`** sem perguntar. Isso
  inclui o próprio `ddl.sql`, que faz `DROP SCHEMA … CASCADE`.
- Para testar e medir, crie bancos descartáveis no mesmo container (por exemplo
  `stream_v3_teste`, `stream_v3_bench`) e apague-os no fim, como foi feito no
  seed v2.
- **Só um container ligado por vez.** Mais de um derruba a máquina do usuário.
  Use bancos descartáveis dentro do container ativo. Se precisar de outro
  container, pergunte antes e desligue o anterior. Não recrie o
  `steam-do-bedo-db` por conta própria: os dados ficam no volume `postgres_data`.
- **Pergunte antes da primeira vez** que for reiniciar o container
  (`docker restart`) ou rodar o container privilegiado que limpa o cache do
  sistema (`drop_caches`, P16). Os dois afetam o ambiente do usuário.

### 5. Git

Não faça commit nem push sem o usuário pedir. Ao fim de cada fase, mostre o que
mudou.

### 6. Mantenha o plano atualizado

A cada ponto concluído, atualize a coluna **Status** da tabela em
`CONSULTA_PROFESSOR.md` e marque os itens do checklist (`- [x]`). Se descobrir
algo que muda o plano, registre no ponto correspondente.

## Portão de decisões: pergunte antes de alterar o DDL

Alguns pontos estão como **Decidir**. Antes de editar qualquer arquivo, faça
**uma rodada de perguntas** ao usuário, com no máximo 4 perguntas por vez. Cada
pergunta traz as opções, as consequências e a recomendação que já está no
`CONSULTA_PROFESSOR.md`:

| Ponto | Pergunta | Recomendação do plano |
|---|---|---|
| P01 | `Inscricao.data_inscricao` (DEC-007) é coluna nova fora de chave: remover ou manter justificando? | Remover, junto com `p_data_ref` dos itens 6, 9 e 11 |
| P02 | Cenário de volumetria: só streaming de jogos com vídeos longos, ou inclui plataformas de vídeo curto? | Propor números e confirmar com o usuário |
| P03 | Chave de `Video`: `BIGINT IDENTITY` ou UUID (v4 nativo no PG17; v7 por function própria)? | Depende do P02: geração distribuída leva a UUID v7; banco central leva a `BIGINT` |
| P05 | Adotar `id_usuario` surrogate com `UNIQUE (nick)`? | Decidir com medição (como na DEC-017) |
| P07 | Doação: converter na consulta (valor corrigido) ou gravar em USD no `INSERT` (valor histórico)? | Converter na consulta |
| P08 | T5 (`seq_plataforma` por usuário e plataforma), T9 (streamer é quem tem `StreamerPais`) e T10 (exigir conta em `PlataformaUsuario`): adotar? | Ver a tabela de triggers no plano |
| P09 | O índice de view materializada conta no teto de 5 índices? | Contar |

Para P02, P03 e P05, se faltar base para decidir, faça primeiro a conta de
volumetria e uma medição pequena em banco descartável. Leve os números para a
pergunta.

## Execução por fases

Siga a ordem do `CONSULTA_PROFESSOR.md`. Ao fim de **cada fase**:

1. Rode a verificação da fase.
2. Escreva as DECs da fase no `DECISIONS.md`.
3. Atualize os status no plano.
4. Dê um resumo curto ao usuário: o que mudou, o que foi verificado e o que
   ficou pendente.

### Fase 0 e 1 · Premissas e DDL (P01 a P07)

- Escreva a DEC de cenário de volumetria (P02), com a conta de capacidade que
  justifica o tipo de cada chave.
- Aplique no `ddl.sql` as decisões de P01, P03, P04, P05 e P06, propagando tipos
  e FKs em todas as tabelas dependentes.
- Registre a regra de moeda (P07) e a forma de conversão escolhida.
- Atualize o cabeçalho do `ddl.sql` com a nova ordem de execução.
- **Verificação:** o `ddl.sql` roda do zero num banco descartável, com código de
  saída 0, e o catálogo (`\d`) mostra as PKs, FKs e `UNIQUE` esperados.

### Fase 2 · Especificação PL/pgSQL (P08 a P10)

- **`triggers.sql`:** T1 a T10, mais T11 se P07 escolher gravar em USD.
  - Cada trigger tem a function e o trigger nomeados e comentados.
  - T3 e T4 tratam concorrência com `SELECT … FOR UPDATE` e explicam o motivo no
    comentário.
  - Em T1 e T2, avalie triggers por comando com tabelas de transição.
- **`views.sql`:** as views fechadas (V1 a V5), com justificativa individual no
  comentário e a estratégia de refresh das materializadas.
- **`procedures.sql`:**
  - ajuste ao DDL final;
  - aplique a conversão das doações (itens 4, 7, 10 e 11), de preferência pelas
    views;
  - o **item 12** (desafio) **não** é feito aqui: ele é a última etapa da
    sessão (ver "Etapa final"). Se já existir uma versão, ela será revista lá.
- **Ordem de execução sugerida** (confirme e registre na DEC):
  `ddl.sql` → `seed_v3.sql` → `views.sql` → `procedures.sql` → `triggers.sql` →
  `indices.sql` → `queries.sql`.
  - Os triggers rodam **depois** da carga, porque o professor separa os triggers
    para a inserção não travar.
  - Os índices de apoio também vêm depois, para não pesar na carga.
  - Se mover os índices da DEC-018 para fora do `ddl.sql`, registre.
- **Verificação:** os arquivos compilam sobre o DDL num banco descartável.

### Fase 3 · Dados (P11 e P12)

- **`seed_v3.sql`**, seguindo o checklist de P11:
  - parte de banco virgem com o DDL final;
  - tabelas pequenas no tamanho real (cerca de 160 moedas, 195 países e dezenas
    de plataformas reais);
  - tabelas grandes no máximo viável, da ordem de centenas de milhares a
    milhões de linhas, conforme o P02;
  - distribuições desbalanceadas e correlacionadas;
  - 1% a 5% dos comentários com doação;
  - doação em moeda local;
  - obedece a todas as regras dos triggers;
  - calcula os derivados no próprio `INSERT`;
  - `setseed` para ser reproduzível;
  - checagem de banco vazio, `ON_ERROR_STOP` e uma transação só;
  - inserção por conjunto, sem laço linha a linha.
- **Comentários do seed:** cada bloco explica a distribuição escolhida e o
  motivo, porque isso é argumento de coerência com o cenário.
- **`seed_v3_RELATORIO.md`**, no formato do v2: ordem de execução, volumes,
  distribuições obtidas, tempo de carga, tamanho em disco e evidência da
  execução.
- **`testes_triggers.sql`:** para cada trigger, um caso que passa e um que é
  rejeitado, mais a conferência dos derivados depois de `INSERT`, `UPDATE` e
  `DELETE`. Rode dentro de transação com `ROLLBACK`, para não sujar a carga.
- **`queries.sql`:** atualize com valores reais do seed v3 e inclua o item 12.
- **Verificação (P12):**
  - a cadeia inteira roda num banco descartável novo, com código de saída 0;
  - `VACUUM ANALYZE`;
  - os derivados batem com `SUM` e `COUNT`;
  - todos os testes de trigger passam;
  - todas as chamadas do `queries.sql` retornam linhas coerentes;
  - os tamanhos de tabelas e índices ficam registrados.

### Fase 4 · Otimização e aferição (P13 a P18)

Ordem obrigatória: **linha de base → reescrita das consultas → predicados →
índices → aferição → gráficos.**

- **Protocolo a frio (P16):** crie um script em `bench/` (por exemplo
  `bench/medir.sh`) que, para cada medida:
  - reinicia o Postgres;
  - limpa o cache de páginas da VM do Docker;
  - espera o banco aceitar conexão;
  - roda **uma** consulta com `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.

  Comprove que a medida foi a frio (`shared read` > 0 e `shared hit` baixo).
  Registre `jit`, `max_parallel_workers_per_gather`, `work_mem`,
  `shared_buffers` e a versão. Use 5 repetições e a mediana. Meça também a
  quente, como cenário separado.
- **Linha de base (P13):** todas as functions, com e sem filtro, só com os
  índices de PK e `UNIQUE`.
- **Reescrita (P13):** comece pelos itens 2 e 3, que agregam todo `Comentario`
  antes de filtrar. Meça antes e depois.
- **Inventário de predicados (P14):** salve em `bench/predicados.md` uma tabela
  com consulta, predicado, tipo, coluna, distribuição (`pg_stats`) e candidato a
  índice. Marque os predicados concentrados como "não indexar" ou "índice
  parcial".
- **Índices (P15):**
  - até 5 no total, em `indices.sql`;
  - B-tree para faixa, ordenação, top-k e prefixo;
  - hash só onde o predicado for **apenas igualdade**, e comparando com B-tree
    pela medição;
  - considere o overhead de inserção de cada um;
  - refaça a DEC-018: escreva uma nova DEC que a substitui.
- **Aferição (P17):** rode a matriz de cenários do plano (consulta × índices ×
  views × frio/quente × overhead de escrita) e salve:
  - `bench/resultados.csv`;
  - `bench/planos/*.json`.
- **Gráficos (P18):** crie `bench/graficos.py` (Python com matplotlib, num venv
  fora do repositório ou com `bench/requirements.txt`) que lê o CSV e gera PNGs
  em `bench/graficos/`:
  - tempo com e sem índice a frio, em escala log;
  - buffers;
  - antes e depois da reescrita;
  - consulta direta × view virtual × view materializada;
  - ganho × overhead × tamanho por índice;
  - frio × quente.

  O script também é comentado.
- **Verificação:** os scripts rodam do zero e regeneram CSV e gráficos. Abra os
  PNGs e confira que eles mostram o que a DEC afirma.

### Fase 5 parcial · Registro (P19)

- Confirme que existe uma DEC para P02, P03, P05, P07, P08, P09, P11 e P15, e
  que as partes antigas estão marcadas como substituídas: DEC-007 (se a coluna
  sair), as medições da DEC-018 e o ponto em aberto das DEC-003 e 004.
- Confira que todo `-- DEC-NNN` citado no código existe no `DECISIONS.md` e
  vice-versa.

### Etapa final · Item 12, o desafio (depois de P19)

Enunciado: *"Listar as top-k plataformas pela quantidade de streamers **E**
canais. Dar a opção de filtrar por plataforma como parâmetro opcional na forma de
uma stored procedure."*

Só comece com P01 a P19 concluídos. Este item é o ponto extra e precisa ser
feito **com maestria**: cada escolha justificada pelo minimundo e pelo cenário
(P02), não só uma consulta que funciona.

1. **Interpretação (escreva a DEC antes do código).** Decida e justifique cada
   ponto:
   - **O que é "streamer da plataforma".** Opções:
     - dono de canal na plataforma (`Canal.nick_streamer`);
     - streamer com conta na plataforma (`PlataformaUsuario` ∩ streamers);
     - dono ou participante de vídeo (`Participa`).

     Conte com `COUNT(DISTINCT …)`: um streamer com vários canais na mesma
     plataforma conta uma vez.
   - **O que significa o "E" sublinhado.** Opções:
     - ordenação lexicográfica (streamers, depois canais);
     - critério combinado;
     - exigir as duas quantidades.

     Escolha a que responde à pergunta do minimundo sobre **alcance de público**
     e justifique.
   - **Empates no corte de k.** `FETCH FIRST k ROWS WITH TIES` ou desempate
     determinístico. Justifique.
   - **Filtro por plataforma.** A posição no ranking precisa ser **global**,
     calculada sobre todas as plataformas e só depois filtrada. Ao filtrar, a
     plataforma mostra a sua posição real, e não "1º de 1".
   - **Bordas:** plataforma sem canais (`LEFT JOIN`, contagem zero), `k` nulo ou
     menor que 1, plataforma inexistente no filtro e coerência com
     `Plataforma.qtd_users` (que é outra métrica: não confundir).
2. **Implementação:**
   - function parametrizada (`p_k`, `p_nro_plataforma DEFAULT NULL`) em
     `procedures.sql`, comentada conforme a regra 2;
   - retorna nome da plataforma, quantidade de streamers, quantidade de canais,
     posição no ranking e as métricas auxiliares que reforcem a interpretação
     (por exemplo, canais por streamer);
   - considere usar a view V5, se ela existir.
3. **Desempenho:**
   - rode o item 12 no protocolo a frio (P16), com e sem os índices de P15 (por
     exemplo `idx_canal_nro_plataforma`) e com e sem a V5;
   - inclua os resultados em `bench/resultados.csv` e um gráfico em
     `bench/graficos/`;
   - se valer a pena trocar algum índice ou view por causa do item 12, respeite
     o teto de 5 e atualize as DECs.
4. **Validação:**
   - chamadas em `queries.sql`: sem filtro, com filtro de uma plataforma grande,
     com filtro de uma plataforma pequena, `k` com empate e `k` maior que o
     número de plataformas;
   - confira os números contra uma contagem manual independente;
   - registre a validação na DEC.
5. **Registro:** uma DEC própria do item 12 (interpretação, alternativas
   descartadas, desempenho e validação), e o item 12 na tabela de
   `CONSULTA_PROFESSOR.md`.

## Critério de pronto da sessão

- [ ] P01 a P19 com status **Feito** em `CONSULTA_PROFESSOR.md`, ou com o motivo
  registrado se algum ficou de fora.
- [ ] A cadeia `ddl.sql` → `seed_v3.sql` → `views.sql` → `procedures.sql` →
  `triggers.sql` → `indices.sql` → `queries.sql` roda num banco descartável novo
  com código de saída 0.
- [ ] `testes_triggers.sql` passa.
- [ ] `bench/resultados.csv` e os gráficos foram gerados pelo protocolo a frio.
- [ ] `DECISIONS.md` tem DEC-019 em diante, cobrindo cada decisão, com a linha
  "Aplicada no DDL".
- [ ] O item 12 está implementado, medido, validado e registrado em DEC própria
  (Etapa final).
- [ ] Todo arquivo novo ou alterado está comentado conforme a regra 2.
- [ ] Os bancos descartáveis foram apagados e o banco `steam-do-bedo-db` não foi
  alterado sem autorização.
- [ ] Relatório final ao usuário com: o que foi feito por fase, decisões
  tomadas, números principais (ganho dos índices e volumes do seed), o que não
  foi verificado e o que fica para P20 a P22.

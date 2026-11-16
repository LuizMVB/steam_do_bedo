# Stream do Bedo

Trabalho final de Projeto de Banco de Dados (UFF, 2026/2), implementado em
**PostgreSQL 17**.

O banco cataloga streamers de jogos online para responder a perguntas sobre:
- alcance de público;
- patrocínios;
- doações;
- membros inscritos;
- interações (comentários).

As decisões de projeto estão resumidas em [decisoes_resumo.md](decisoes_resumo.md)
e explicadas uma a uma em [decisoes_detalhamento.md](decisoes_detalhamento.md);
as medições de desempenho, em [benchmark.md](benchmark.md).

## Entregáveis

Os 5 arquivos pedidos no Classroom e onde cada um está no projeto:

| # | Entregável pedido | Arquivo(s) do projeto | O que contém |
|---|---|---|---|
| 1 | DDL de construção das tabelas | [`ddl.sql`](ddl.sql) | Schema `steam_do_bedo` com as 20 tabelas, chaves artificiais e constraints `UNIQUE`, `NOT NULL` e `CHECK` |
| 2 | PL/pgSQL: functions, triggers, views e outros | [`views.sql`](views.sql) | 2 views virtuais, 2 materializadas e a procedure `sp_refresh_views` |
| | | [`functions.sql`](functions.sql) | Functions das 12 consultas e, no fim do arquivo, os índices de apoio |
| | | [`triggers.sql`](triggers.sql) | Triggers T1 a T11, em arquivo separado para rodar depois da carga |
| 3 | Dados para inserção | [`seed.sql`](seed.sql) | Gera cerca de 8,7 milhões de registros com semente fixa; o arquivo é pequeno, então não precisa de link do Drive |
| 4 | Chamadas das consultas e functions para teste | [`tests.sql`](tests.sql) | Chama cada function em vários cenários: sem filtro, com filtro e top-k com k diferentes |
| 5 | PDF curto com as decisões de projeto e justificativas | [`decisoes_resumo.pdf`](decisoes_resumo.pdf) | Versão em PDF do [`decisoes_resumo.md`](decisoes_resumo.md) |
| | | [`decisoes_detalhamento.md`](decisoes_detalhamento.md), [`benchmark.md`](benchmark.md) | Complemento: cada decisão por extenso e as medições de desempenho (não fazem parte do PDF) |

## Requisitos

- **Docker** com Compose v2 (Docker Desktop no Mac ou no Windows).
- **make**: já vem no macOS e no Linux. No Windows, use o WSL ou rode os
  comandos da seção [Sem make](#sem-make).
- **Porta 5432 livre.** Para usar outra, defina `POSTGRES_PORT` (veja
  [Acesso por cliente externo](#acesso-por-cliente-externo)).
- **Cerca de 3 GB livres em disco** para a carga completa.
- **Deixe só este container ligado durante a carga.** Ela é pesada, e dividir a
  memória com outros containers deixa tudo lento.

## Execução rápida

```bash
make setup
```

```bash
make tests
```

O `make setup` sobe o banco e executa todos os arquivos na ordem certa. A carga
completa leva de 6 a 9 minutos. Para um teste rápido, com cerca de 10% dos dados
e menos de 1 minuto:

```bash
make setup ESCALA=0.1
```

## Passo a passo

Cada arquivo depende dos anteriores. O `make setup` executa as etapas 1 a 5, e
cada etapa também pode ser rodada sozinha:

| Etapa | Comando | Arquivo | O que faz | Item do enunciado |
|---|---|---|---|---|
| 0 | `make up` | `docker-compose.yml` | Sobe o PostgreSQL 17 e espera o banco aceitar conexões | — |
| 1 | `make ddl` | `ddl.sql` | Recria o schema `steam_do_bedo` com as 20 tabelas, as chaves artificiais e as constraints `UNIQUE`, `NOT NULL` e `CHECK` | 2: identificadores artificiais e constraints |
| 2 | `make seed` | `seed.sql` | Carrega cerca de 8,7 milhões de registros artificiais, com distribuição desbalanceada e realista | 1: inserção de tuplas |
| 3 | `make views` | `views.sql` | Cria 2 views virtuais e 2 materializadas | 3: visões |
| 4 | `make functions` | `functions.sql` | Cria as functions das 12 consultas e, no fim do arquivo, os índices de apoio | 6: functions; 4: índices de apoio |
| 5 | `make triggers` | `triggers.sql` | Cria os triggers T1 a T11, que mantêm a consistência do banco | 5: triggers |
| 6 | `make tests` | `tests.sql` | Chama cada function em vários cenários: sem filtro, com filtro e top-k com k diferentes | 6: chamadas das consultas |

### Por que essa ordem

- **O `ddl.sql` apaga tudo.** Ele faz `DROP SCHEMA ... CASCADE` e recria o
  schema do zero. Para recomeçar, basta rodar o `make setup` de novo.
- **O `seed.sql` exige o banco vazio.** Ele aborta sem inserir nada se encontrar
  alguma linha. Por isso roda logo depois do `ddl.sql`.
- **As views vêm depois da carga.** As views materializadas são preenchidas no
  momento em que são criadas.
- **As functions vêm depois das views,** porque leem as views. Os índices de
  apoio ficam no fim do `functions.sql`, para serem criados sobre as tabelas já
  carregadas, o que é mais rápido do que mantê-los durante a carga.
- **Os triggers vêm por último,** por orientação do professor, para não pesar
  nem travar a inserção em lote. O seed já obedece às mesmas regras e calcula
  sozinho os atributos derivados (`qtd_visualizacoes` e `qtd_users`).

## Consultas

Todas estão no schema `steam_do_bedo`. Os parâmetros com `DEFAULT NULL` são os
filtros opcionais.

| # | Function | Parâmetros |
|---|---|---|
| 1 | `sp_obter_streamers_com_maior_qtd_videos_publicados` | `p_plataforma` (nro, opcional) |
| 2 | `sp_obter_videos_mais_comentados` | `p_nome_canal` (opcional) |
| 3 | `sp_obter_canais_por_qtd_total_interacoes` | `p_nick_streamer` (opcional) |
| 4 | `sp_obter_canais_pela_media_doacoes_por_comentario` | `p_nro_plataforma` (opcional) |
| 5 | `sp_obter_canais_patrocinados_com_valores_por_empresa` | `p_nome_empresa` (opcional) |
| 6 | `sp_obter_qtd_canais_e_gasto_mensal_por_usuario` | `p_nick_usuario` (opcional) |
| 7 | `sp_obter_canais_com_doacoes_recebidas` | `p_nome_canal` (opcional) |
| 8 | `sp_obter_top_k_canais_por_patrocinio` | `p_k` (nulo devolve todos) |
| 9 | `sp_obter_top_k_canais_por_aportes_de_membros` | `p_k` |
| 10 | `sp_obter_top_k_canais_por_doacoes_recebidas` | `p_k` |
| 11 | `sp_obter_top_k_canais_por_faturamento` | `p_k` |
| 12 | `sp_obter_top_k_plataformas_por_streamers_e_canais` (desafio) | `p_k`, `p_nro_plataforma` (opcionais) |

Exemplo, num `make psql`:

```sql
SET search_path TO steam_do_bedo;
SELECT * FROM sp_obter_top_k_canais_por_faturamento(10);
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10,
    (SELECT nro FROM plataforma WHERE nome = 'Kick'));
```

Valores dos filtros:
- **Valores que existem em qualquer escala:** as plataformas, como `YouTube`,
  `Twitch` e `Kick`, e as empresas reais, como `Red Bull GmbH`.
- **Valores que só valem na escala 1:** o canal, o streamer e o usuário do
  cabeçalho do `tests.sql`. A carga é sempre igual nessa escala, porque o seed
  usa semente fixa.

## Views materializadas

Os itens 2, 3 e 8 a 11 leem as views materializadas V3 e V4, que mostram os
dados da última atualização. Depois de inserir ou alterar dados, atualize-as:

```bash
make refresh
```

O comando chama `CALL steam_do_bedo.sp_refresh_views()`, que atualiza as duas
views sem bloquear as leituras.

## Acesso por cliente externo

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Porta | `5432` |
| Banco | `steam-do-bedo-db` |
| Usuário | `admin` |
| Senha | `admin` |
| Schema | `steam_do_bedo` |

Usuário, senha, banco e porta podem ser trocados pelas variáveis
`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` e `POSTGRES_PORT`, num
arquivo `.env` ou no ambiente. Se trocar o usuário ou o banco, passe o mesmo
valor para o make: `make setup DB_USER=... DB_NAME=...`.

## Desligar e limpar

```bash
make down
```

O `make down` desliga o container, e os dados ficam guardados no volume.

```bash
make clean
```

O `make clean` desliga o container e **apaga o volume com os dados**.

O `make help` lista todos os comandos.

## Sem make

Com o container no ar (`docker compose up -d --wait`), execute os arquivos nesta
ordem:

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -f /workspace/ddl.sql
```

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -v escala=1 -f /workspace/seed.sql
```

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -f /workspace/views.sql
```

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -f /workspace/functions.sql
```

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -f /workspace/triggers.sql
```

```bash
docker compose exec -T db psql -U admin -d steam-do-bedo-db -v ON_ERROR_STOP=1 -f /workspace/tests.sql
```

Em outro PostgreSQL 17, sem Docker, a ordem é a mesma, com
`psql -d <banco> -v ON_ERROR_STOP=1 -f <arquivo>`.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `ddl.sql` | Tabelas, chaves e constraints |
| `seed.sql` | Carga de dados, com escala ajustável |
| `views.sql` | Views virtuais e materializadas e a procedure de atualização |
| `functions.sql` | Functions das 12 consultas e os índices de apoio |
| `triggers.sql` | Triggers T1 a T11 |
| `tests.sql` | Chamadas das functions em vários cenários |
| `decisoes_resumo.md`, `decisoes_resumo.pdf` | Resumo das decisões de projeto e justificativas (o PDF é o entregável 5) |
| `decisoes_detalhamento.md` | Cada decisão por extenso: exigência, alternativas, medições e limitações |
| `benchmark.md`, `imagens/` | Comparações de desempenho e gráficos; os scripts e os planos de cada medida ficam na pasta `bench/` da tag `v2.1.0` |
| `predicados.md`, `estatisticas.sql` | Inventário dos predicados das consultas e distribuição das colunas, base da escolha dos índices |
| `docker-compose.yml`, `Makefile` | Ambiente e atalhos de execução |

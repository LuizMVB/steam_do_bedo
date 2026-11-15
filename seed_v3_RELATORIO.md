# Relatório do `seed_v3.sql`

## Regra principal

O `seed_v3.sql` substitui o `seed.sql` e o `seed_v2.sql`. Nunca execute mais de um
seed. Ele parte de um banco com o schema do `ddl.sql` e todas as tabelas vazias, e
gera tudo do zero, inclusive as tabelas de referência.

## Ordem de execução

```bash
psql -U admin -d <banco> -v ON_ERROR_STOP=1 -f ddl.sql
```

```bash
psql -U admin -d <banco> -v ON_ERROR_STOP=1 -f seed_v3.sql
```

Para um teste rápido, a escala é ajustável (padrão 1; 0,1 roda em menos de 1 minuto):

```bash
psql -U admin -d <banco> -v ON_ERROR_STOP=1 -v escala=0.1 -f seed_v3.sql
```

Depois: `views.sql` → `procedures.sql` → `triggers.sql` → `indices.sql` →
`queries.sql` (DEC-030). O `testes_triggers.sql` roda depois do `triggers.sql`.

## Como as garantias são cumpridas

| Regra | Como o script cumpre |
|---|---|
| Banco vazio | Um bloco `DO` no início confere as 20 tabelas e aborta com `RAISE EXCEPTION` se alguma tiver linhas ou não existir |
| Parar no primeiro erro | `\set ON_ERROR_STOP on` |
| Nada parcial | Uma transação só (`BEGIN` … `COMMIT`); a conferência final também aborta a transação |
| Reprodutível | `setseed(0.42)`, sem paralelismo, fuso UTC; o UUID v7 dos vídeos é derivado do `dataH` e de uma semente (não de `gen_random_uuid()`) |
| Por conjunto | `generate_series`, `JOIN` e `LATERAL`; nenhum laço linha a linha |
| Chaves de identidade | `Empresa.nro`, `Plataforma.nro`, `Usuario.id_usuario` e `Canal.id_canal` são obtidos por `JOIN` pela chave natural, nunca por número fixo |
| Derivados no `INSERT` | `Plataforma.qtd_users` e `Canal.qtd_visualizacoes` vêm de tabelas temporárias de preparação; não há `UPDATE` final (sem tuplas mortas) |
| Regras dos triggers | `seq` contínuo por vídeo, `seq_pg` por comentário, `seq_plataforma` por (usuário, plataforma); até 5 níveis por canal; doação em exatamente uma forma; datas em ordem (inclusive o Mixer, encerrado em 2020-07-22); dono do canal streamer e com conta na plataforma; doação em USD |
| Conferência de sanidade | Substitui a checagem de 1.000 a 10.000 do v2: confere todas as regras acima, os derivados contra `SUM`/`COUNT` e a taxa de doação (1% a 5%); qualquer falha aborta |
| Estatísticas | `VACUUM (ANALYZE)` das 20 tabelas depois do `COMMIT` |

## Evidência da execução

Ambiente: Docker `postgres:17` (17.11, aarch64), container de aferição
`stream-bench`, banco descartável novo (`stream_v3_teste`), escala 1.

### Cadeia completa

| Arquivo | Código de saída | Tempo |
|---|---|---|
| `ddl.sql` | 0 | 1 s |
| `seed_v3.sql` | 0 | 522 s (8 min 42 s) |
| `views.sql` | 0 | 21 s |
| `procedures.sql` | 0 | 1 s |
| `triggers.sql` | 0 | 1 s |
| `indices.sql` | 0 | 3 s |
| `queries.sql` | 0 | 49 s |
| `testes_triggers.sql` | 0 | 42 s (37 casos, todos OK) |

Mensagem da conferência: `seed_v3: conferência de sanidade OK (1.90% dos
comentários com doação)`.

### Volume final

| Tabela | Linhas | Tabela | Linhas |
|---|---|---|---|
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

Total: cerca de 8,7 milhões de tuplas. A carga leva de 6 a 9 minutos (383 s e 522 s em duas execuções).

### Tamanho em disco (depois do `VACUUM ANALYZE`, com views e índices finais)

| Objeto | Tabela | Índices | Total |
|---|---|---|---|
| Comentario | 442 MB | 194 MB | 636 MB |
| Video | 155 MB | 176 MB | 331 MB |
| Usuario | 63 MB | 94 MB | 158 MB |
| mv_interacoes_video (V3) | 92 MB | 48 MB | 140 MB |
| PlataformaUsuario | 43 MB | 59 MB | 102 MB |
| Inscricao | 31 MB | 28 MB | 60 MB |
| demais 16 objetos | | | ~63 MB |
| **Schema inteiro** | | | **1.490 MB** |

### Reprodutibilidade

Duas cargas independentes (bancos `stream_bench` e `stream_v3_final`, em momentos
diferentes) geraram o mesmo hash MD5 do conteúdo de `Comentario`, `Inscricao`,
`Doacao` e `PlataformaUsuario` (por exemplo, `Comentario`:
`9aaf1d272e6380ecc8023af7b76377bc` nas duas). Uma terceira carga, já com a busca
das contas por `LATERAL` (ver "Problemas encontrados"), deu os mesmos hashes: a
correção mudou o plano, não os dados, e as medições de `bench/` valem para ela.

## Distribuições obtidas (escala 1)

| Aspecto | Valor no seed v3 | Como é gerado |
|---|---|---|
| Vídeos por canal | mediana 15, p90 79, p99 306, máximo 2.645 | lognormal correlacionada com a popularidade do canal; canais de vídeo curto publicam mais |
| Comentários por vídeo | 52% dos vídeos sem comentário; mediana 0, p90 6, p99 58, máximo 12.723; média 4 | proporcional a `visu_total^0,85` com ruído (cauda longa) |
| Visualizações | 1% dos canais tem 76% das visualizações; 10% têm 96% | popularidade lognormal (σ = 2,2) |
| Autores | 1% dos autores escreve 14,6% dos comentários; 479 mil autores distintos | lei de potência sobre as contas da plataforma |
| Formato | 74% dos vídeos são curtos (até 60 s), 26% longos | formato da plataforma (curto, longo, misto) |
| Comentários online | 22,4% | 85% em live, 50% em vídeo longo de plataforma mista, 0% em vídeo curto |
| Comentários com doação | 1,90% (99.510 doações; 5% dos comentários com doação têm duas) | 5% dos online e 1% dos offline |
| Status da doação | lido 70%, recebido 20%, recusado 10% | sorteio |
| Valor mediano da doação (USD) | mecanismo 4,01; cartão 10,21; PayPal 11,91; BitCoin 39,80 | lognormal por forma, convertida da moeda local |
| Contas por plataforma | YouTube 27,7%, TikTok 19,7%, Instagram 12,6%, Twitch 8,6% … | peso de mercado |
| País de residência | EUA 11,2%, Índia 9,4%, Brasil 8,4%, Indonésia 4,7% … | peso por país (199 países) |
| Membros | 64% dos usuários são membros; 160 mil de 1 canal, 90 mil de 2, 42 mil de 3 … | canais pela popularidade, membros por lei de potência |
| Patrocínio | 21% dos canais, concentrado no topo | chance 3% + 90% × percentil^4 |
| Streamers | 5% dos usuários (26 mil passaportes) | sorteio |

Comparado com o seed v2: 50% → 1,9% dos comentários com doação; 1,7 → 4 comentários
por vídeo, com cauda longa (até 12.723); 25% → 5% de streamers; tabelas de referência
no tamanho real.

## Testes dos triggers (`testes_triggers.sql`)

37 casos, todos OK: para cada trigger (T1 a T11) um caso aceito e um rejeitado com o
SQLSTATE esperado, e a conferência dos derivados depois de `INSERT`, `UPDATE`,
`DELETE` e de um `INSERT` em lote. Tudo dentro de uma transação desfeita com
`ROLLBACK`.

## Problemas encontrados na validação e corrigidos

- **Tabelas temporárias sem estatística:** o autovacuum nunca analisa tabela
  temporária, e o planejador escolhia nested loop com varredura completa nos JOINs
  de sorteio; a carga travou em `Inscricao`. Correção: `ANALYZE` em cada tabela
  temporária logo após a criação, e nas tabelas reais usadas em JOINs seguintes.
- **Memoize repetindo sorteios:** o planejador guardava em cache o resultado de
  subconsultas `LATERAL` com `random()` pela chave de entrada; só 0,39% dos
  comentários ficavam com doação e todos os vídeos tinham o mesmo convidado.
  Correção: `SET LOCAL enable_memoize = off` e sorteios correlacionados com a linha.
- **Plano instável no sorteio do autor:** numa quarta carga, o `INSERT` de
  `Comentario` passou de 14 minutos (nas três anteriores a carga inteira levou de 6 a
  9 min). O `JOIN` com a tabela de contas sorteadas dependia da estimativa do
  planejador, que muda com a amostra do `ANALYZE`. Correção: a conta sorteada é
  buscada por `LATERAL` pela chave única (`Comentario` e `Inscricao`), que é sempre
  um acesso pelo índice.
- **DDI não único:** +1 e +7 são compartilhados; usado o prefixo que distingue o
  país (DEC-031).

## Pontos em aberto

- O seed v3 não conhece a data de encerramento das plataformas além do Mixer.

# Inventário de predicados

Base da escolha dos índices de apoio. Metodologia do professor
(consulta de 2026-11-11, 07:03–08:16):

1. olhar a complexidade das consultas e a **similaridade dos predicados** (eles se
   repetem entre consultas e não mudam com o tempo);
2. olhar a **distribuição** da coluna: se o filtro devolve grande parte da tabela, o
   índice não ajuda ("se fosse só streamers americanos [...] não adianta criar um
   índice ali");
3. pelo **tipo do predicado**, escolher o tipo do índice (B-tree ou hash).

A distribuição vem do `pg_stats` e de contagens sobre o seed na escala 1
(`bench/estatisticas.sql`; saída em `bench/estatisticas.txt`).

## Tabela de predicados

| Consulta | Predicado | Tipo | Coluna | Distribuição (seed, escala 1) | Já atendido por | Candidato |
|---|---|---|---|---|---|---|
| 1, 4, 12 (com filtro) | `c.nro_plataforma = p` | igualdade | `Canal.nro_plataforma` | 28 valores; YouTube 28,1%, TikTok 20,1%, Instagram 12,6%; Kick 3,5% | nada (`canal_nome_plataforma_key` tem `nome` na frente) | **B-tree** `Canal (nro_plataforma)`; útil nas plataformas pequenas, inútil nas grandes |
| 12 | `GROUP BY p.nro` + `JOIN canal ON c.nro_plataforma = p.nro` | junção/agrupamento | `Canal.nro_plataforma` | 28 valores | idem | mesmo índice (B-tree entrega em ordem) |
| 1, 2, 4, 7, V1 | `v.id_canal = c.id_canal` | junção | `Video.id_canal` | ~35 vídeos por canal, correlação física 0,001 | `video_canal_titulo_datah_key` (prefixo) | não indexar (já atendido) |
| 2, 7 (com filtro) | `cn.nome = p` | igualdade | `Canal.nome` | quase único | `canal_nome_plataforma_key` (prefixo) | não indexar |
| 3 (com filtro), T9, T10 | `u.nick = p` → `cn.id_streamer = u.id_usuario` | igualdade | `Canal.id_streamer` | ~1,4 canal por streamer; o maior tem 0,014% de Canal | nada | **B-tree ou hash** `Canal (id_streamer)` (só igualdade: comparar) |
| 3, 6 (com filtro) | `u.nick = p` | igualdade | `Usuario.nick` | único | `usuario_nick_key` | não indexar |
| 6 (com filtro), FK | `i.id_membro = u.id_usuario` | igualdade | `Inscricao.id_membro` | ~1,9 inscrição por membro; o maior tem 0,0025% de Inscricao | nada (PK começa por `id_canal`) | **B-tree ou hash** `Inscricao (id_membro)` (só igualdade: comparar) |
| 2, 3 (V3) | `m.id_canal = c.id_canal` | igualdade/junção | `mv_interacoes_video.id_canal` | ~35 vídeos por canal, cauda longa | `ux_mv_interacoes_video` (prefixo) | já é o índice UNIQUE da V3 (conta no teto) |
| 8 a 11 (V4) | `ORDER BY vr_* DESC LIMIT k` | top-k | `mv_faturamento_canal.vr_*` | ~30 mil linhas | nada | não indexar: ordenar 30 mil linhas custa milissegundos; 4 colunas diferentes pediriam 4 índices |
| 4, 7, 10, 11, V1 | `d.status <> 'recusado'` | desigualdade | `Doacao.status` | 3 valores; `<> 'recusado'` devolve 89,8% | — | **não indexar**: devolve ~90% da tabela |
| V3 | `c.coment_on` (FILTER) | booleano | `Comentario.coment_on` | 2 valores; online 22,7% | — | não indexar: 2 valores, a contagem lê tudo |
| 5 (com filtro) | `e.nome = p` → `p.nro_empresa = e.nro` | igualdade | `Patrocinio.nro_empresa` | marcas grandes com centenas de patrocínios | `empresa_nome_key` + `patrocinio_pkey` (prefixo) | não indexar |
| V2, 6, 9, 11 | `n.id_canal = i.id_canal AND n.nivel = i.nivel` | junção | `NivelCanal` | 5 por canal | `nivelcanal_pkey` | não indexar |
| V3, itens 2 e 3 originais | `c.id_video = v.id_video` | junção | `Comentario.id_video` | cauda longa | `comentario_pkey` (prefixo) | não indexar |
| 12 | `GROUP BY p.nro` + `COUNT(DISTINCT c.id_streamer)` + `rank()` global | agrupamento/ordenação | `Canal (nro_plataforma, id_streamer)` | 28 plataformas, ~36 mil canais | nada | testado `Canal (nro_plataforma, id_streamer) INCLUDE (qtd_visualizacoes)`: não usado pelo planejador; **não indexar** |
| T5 | usuário e plataforma de `MecanismoPlat` | junção | — | 44,6 mil linhas | PKs de `Comentario` e `Video` | não indexar (escrita rara; não gastar o teto) |

## Predicados concentrados (não indexar ou só índice parcial)

- `Doacao.status <> 'recusado'`: devolve 89,8% de `Doacao`. Varrer a tabela vence
  qualquer índice; um índice parcial (`WHERE status <> 'recusado'`) teria quase o
  tamanho da tabela. **Não indexar** (já era a conclusão da primeira medição).
- `Comentario.coment_on`: 2 valores (22,7% online). A V3 conta os dois numa passada só.
  **Não indexar.**
- `Canal.nro_plataforma = YouTube`: devolve 28% dos canais e 30% dos vídeos. Com o
  índice, o planejador continua varrendo `Video` para o YouTube (medido); o índice só
  ajuda nas plataformas pequenas (Kick: 3,5%).
- `Video.id_canal`: a correlação física é 0,001. Os vídeos de um canal estão
  espalhados pela tabela, porque a chave é um UUID v4, aleatório.
  Por isso, ler "vídeos de um canal" pela tabela custa uma página por vídeo, e o
  índice de cobertura evita essas visitas.

## Conclusão

Os candidatos que sobram são três igualdades seletivas em tabelas sem índice que
as atenda: `Canal (nro_plataforma)`, `Canal (id_streamer)` e
`Inscricao (id_membro)`. Os dois de igualdade pura foram medidos também como hash.

A medição a frio mostrou que `Canal (nro_plataforma)` não ajuda: `Canal` cabe em 665
páginas, e o custo dos itens 1, 4 e 12 estava em `Video`. No lugar dele, a mesma
medição apontou `Video (id_canal) INCLUDE (visu_total)`, que deixa o item 1
contar e somar por canal só pelo índice. Com os dois índices `UNIQUE` das views
materializadas, os 5 índices finais estão no decisoes_detalhamento.md.

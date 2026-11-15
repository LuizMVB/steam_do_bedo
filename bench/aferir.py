#!/usr/bin/env python3
# =====================================================================
# bench/aferir.py · matriz de aferição (P13, P15, P16, P17)
#
# O que faz: roda a matriz consulta × cenário de índices × cache (frio e
# quente), 5 repetições por célula, e grava:
#   bench/resultados.csv   uma linha por execução medida
#   bench/planos/*.json    o plano da 1ª repetição de cada célula
#   bench/escrita.csv      overhead de INSERT em lote com e sem cada índice
#                          e custo do REFRESH das views materializadas
#   bench/tamanhos.csv     tamanho de cada tabela e índice
# Cada medida a frio passa por bench/medir.sh (reinicia o container e
# limpa o cache do SO antes; DEC-032).
#
# Ordem: depois da carga completa (ddl -> seed_v3 -> views -> procedures)
# e de bench/consultas_alternativas.sql, no banco de aferição. Os índices
# de apoio são criados e apagados por este script conforme o cenário; os
# triggers não são criados (não influem em leitura).
#
# Uso:  python3 bench/aferir.py [--banco stream_bench] [--reps 5]
#                               [--so-quente] [--fases base,indices,...]
# Cuidado:
#   * Leva cerca de 1 hora (cada medida a frio reinicia o Postgres).
#   * Reinicia o container de aferição (CT, padrão stream-bench), nunca o
#     do projeto. O usuário autorizou isso para este container.
#   * Os valores de filtro saem do próprio banco (nada fixo), então o
#     script roda sobre qualquer escala do seed.
# DEC-032 (protocolo), DEC-033 (reescrita), DEC-034 (índices).
# =====================================================================
import argparse
import csv
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BENCH = RAIZ / "bench"
CT = os.environ.get("CT", "stream-bench")
USR = os.environ.get("PGUSER_BENCH", "admin")


def psql(banco, sql, at=True):
    """Executa SQL no container e devolve a saída (texto)."""
    args = ["docker", "exec", "-i", CT, "psql", "-U", USR, "-d", banco, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
    if at:
        args += ["-At"]
    r = subprocess.run(args, input=sql, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"psql falhou: {r.stderr.strip()}\nSQL: {sql[:300]}")
    return r.stdout.strip()


def um_valor(banco, sql):
    return psql(banco, sql).splitlines()[0]


# ---------------------------------------------------------------------
# Valores de filtro, tirados dos dados (DEC-032: filtros reais do seed).
# plataforma_pequena: Kick (~3% das contas); plataforma_grande: YouTube
# (~30%), o caso de predicado concentrado do P14.
# canal: o canal com mais visualizações; streamer: o dono dele;
# usuario: o membro com mais inscrições; empresa: a que mais patrocina.
# ---------------------------------------------------------------------
def filtros(banco):
    f = {}
    f["plat_peq"] = um_valor(banco, "SELECT nro FROM steam_do_bedo.plataforma WHERE nome = 'Kick'")
    f["plat_grd"] = um_valor(banco, "SELECT nro FROM steam_do_bedo.plataforma WHERE nome = 'YouTube'")
    f["canal"] = um_valor(banco, "SELECT nome FROM steam_do_bedo.canal ORDER BY qtd_visualizacoes DESC, id_canal LIMIT 1")
    f["streamer"] = um_valor(banco, """SELECT u.nick FROM steam_do_bedo.canal c JOIN steam_do_bedo.usuario u
                                       ON u.id_usuario = c.id_streamer ORDER BY c.qtd_visualizacoes DESC, c.id_canal LIMIT 1""")
    f["usuario"] = um_valor(banco, """SELECT u.nick FROM steam_do_bedo.inscricao i JOIN steam_do_bedo.usuario u
                                      ON u.id_usuario = i.id_membro GROUP BY u.nick ORDER BY count(*) DESC, u.nick LIMIT 1""")
    f["empresa"] = um_valor(banco, """SELECT e.nome FROM steam_do_bedo.patrocinio p JOIN steam_do_bedo.empresa e
                                      ON e.nro = p.nro_empresa GROUP BY e.nome ORDER BY count(*) DESC, e.nome LIMIT 1""")
    return f


def q(s):
    return "'" + s.replace("'", "''") + "'"


def consultas(f):
    """Consultas da matriz: (id, item, filtro, variante, SQL)."""
    s = "steam_do_bedo."
    c = []
    # itens 1 a 12, versão final, com e sem filtro
    c += [("i01_sem", 1, "sem", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados();"),
          ("i01_peq", 1, "plataforma pequena", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados({f['plat_peq']});"),
          ("i01_grd", 1, "plataforma grande", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados({f['plat_grd']});"),
          ("i02_sem", 2, "sem", "final", f"SELECT * FROM {s}sp_obter_videos_mais_comentados();"),
          ("i02_com", 2, "canal", "final", f"SELECT * FROM {s}sp_obter_videos_mais_comentados({q(f['canal'])});"),
          ("i03_sem", 3, "sem", "final", f"SELECT * FROM {s}sp_obter_canais_por_qtd_total_interacoes();"),
          ("i03_com", 3, "streamer", "final", f"SELECT * FROM {s}sp_obter_canais_por_qtd_total_interacoes({q(f['streamer'])});"),
          ("i04_sem", 4, "sem", "final", f"SELECT * FROM {s}sp_obter_canais_pela_media_doacoes_por_comentario();"),
          ("i04_peq", 4, "plataforma pequena", "final", f"SELECT * FROM {s}sp_obter_canais_pela_media_doacoes_por_comentario({f['plat_peq']});"),
          ("i05_sem", 5, "sem", "final", f"SELECT * FROM {s}sp_obter_canais_patrocinados_com_valores_por_empresa();"),
          ("i05_com", 5, "empresa", "final", f"SELECT * FROM {s}sp_obter_canais_patrocinados_com_valores_por_empresa({q(f['empresa'])});"),
          ("i06_sem", 6, "sem", "final", f"SELECT * FROM {s}sp_obter_qtd_canais_e_gasto_mensal_por_usuario();"),
          ("i06_com", 6, "usuario", "final", f"SELECT * FROM {s}sp_obter_qtd_canais_e_gasto_mensal_por_usuario({q(f['usuario'])});"),
          ("i07_sem", 7, "sem", "final", f"SELECT * FROM {s}sp_obter_canais_com_doacoes_recebidas();"),
          ("i07_com", 7, "canal", "final", f"SELECT * FROM {s}sp_obter_canais_com_doacoes_recebidas({q(f['canal'])});"),
          ("i08_k10", 8, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_patrocinio(10);"),
          ("i09_k10", 9, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_aportes_de_membros(10);"),
          ("i10_k10", 10, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_doacoes_recebidas(10);"),
          ("i11_k10", 11, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_faturamento(10);"),
          ("i12_sem", 12, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_plataformas_por_streamers_e_canais(10);"),
          ("i12_peq", 12, "k=10, plataforma pequena", "final", f"SELECT * FROM {s}sp_obter_top_k_plataformas_por_streamers_e_canais(10, {f['plat_peq']});")]
    return c


def consultas_item12(f):
    """Item 12 (DEC-035): versão final x anterior (DEC-029) x V5 virtual x V5
    materializada; sem filtro (k=10), plataforma pequena e grande."""
    fn = "steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais"
    return [
        ("i12_sem", 12, "k=10", "final", f"SELECT * FROM {fn}(10);"),
        ("i12_peq", 12, "k=10, plataforma pequena", "final", f"SELECT * FROM {fn}(10, {f['plat_peq']});"),
        ("i12_grd", 12, "k=10, plataforma grande", "final", f"SELECT * FROM {fn}(10, {f['plat_grd']});"),
        ("i12_sem", 12, "k=10", "anterior", "SELECT * FROM bench.item12_anterior(10);"),
        ("i12_peq", 12, "k=10, plataforma pequena", "anterior", f"SELECT * FROM bench.item12_anterior(10, {f['plat_peq']});"),
        ("i12_grd", 12, "k=10, plataforma grande", "anterior", f"SELECT * FROM bench.item12_anterior(10, {f['plat_grd']});"),
        ("i12_sem", 12, "k=10", "v5_virtual", "SELECT * FROM bench.item12_v5(false, 10);"),
        ("i12_peq", 12, "k=10, plataforma pequena", "v5_virtual", f"SELECT * FROM bench.item12_v5(false, 10, {f['plat_peq']});"),
        ("i12_sem", 12, "k=10", "v5_mat", "SELECT * FROM bench.item12_v5(true, 10);"),
        ("i12_peq", 12, "k=10, plataforma pequena", "v5_mat", f"SELECT * FROM bench.item12_v5(true, 10, {f['plat_peq']});"),
    ]


def consultas_alternativas(f):
    """Reescrita (P13) e views (P09): original x direta x virtual x materializada."""
    return [
        ("i02_sem", 2, "sem", "original", "SELECT * FROM bench.item2_original();"),
        ("i02_com", 2, "canal", "original", f"SELECT * FROM bench.item2_original({q(f['canal'])});"),
        ("i02_sem", 2, "sem", "direta", "SELECT * FROM bench.item2_direta();"),
        ("i02_com", 2, "canal", "direta", f"SELECT * FROM bench.item2_direta({q(f['canal'])});"),
        ("i03_sem", 3, "sem", "original", "SELECT * FROM bench.item3_original();"),
        ("i03_com", 3, "streamer", "original", f"SELECT * FROM bench.item3_original({q(f['streamer'])});"),
        ("i03_sem", 3, "sem", "direta", "SELECT * FROM bench.item3_direta();"),
        ("i03_com", 3, "streamer", "direta", f"SELECT * FROM bench.item3_direta({q(f['streamer'])});"),
        ("i10_k10", 10, "k=10", "direta", "SELECT * FROM bench.item10_direta(10);"),
        ("i10_k10", 10, "k=10", "virtual", "SELECT * FROM bench.item10_virtual(10);"),
        ("i11_k10", 11, "k=10", "direta", "SELECT * FROM bench.item11_direta(10);"),
        ("i11_k10", 11, "k=10", "virtual", "SELECT * FROM bench.item11_virtual(10);"),
    ]


# ---------------------------------------------------------------------
# Cenários de índices de apoio. "sem_apoio" = só PK, UNIQUE e os UNIQUE
# das views materializadas. Os demais criam os índices indicados.
# Os candidatos saem do inventário de predicados (bench/predicados.md).
# ---------------------------------------------------------------------
INDICES = {
    "idx_inscricao_id_membro":      "CREATE INDEX idx_inscricao_id_membro ON steam_do_bedo.inscricao (id_membro)",
    "idx_inscricao_id_membro_hash": "CREATE INDEX idx_inscricao_id_membro_hash ON steam_do_bedo.inscricao USING hash (id_membro)",
    "idx_canal_id_streamer":        "CREATE INDEX idx_canal_id_streamer ON steam_do_bedo.canal (id_streamer)",
    "idx_canal_id_streamer_hash":   "CREATE INDEX idx_canal_id_streamer_hash ON steam_do_bedo.canal USING hash (id_streamer)",
    "idx_canal_nro_plataforma":     "CREATE INDEX idx_canal_nro_plataforma ON steam_do_bedo.canal (nro_plataforma)",
    # candidato que a medição apontou: o item 1 lia Video inteira; com
    # visu_total no INCLUDE, contar e somar por canal vira index-only scan
    "idx_video_id_canal_cobertura": "CREATE INDEX idx_video_id_canal_cobertura ON steam_do_bedo.video (id_canal) INCLUDE (visu_total)",
    # candidato do item 12 (DEC-035): agrupar Canal por plataforma e contar
    # streamers distintos só pelo índice, já em ordem
    "idx_canal_plat_streamer_cob":  "CREATE INDEX idx_canal_plat_streamer_cob ON steam_do_bedo.canal (nro_plataforma, id_streamer) INCLUDE (qtd_visualizacoes)",
}

CENARIOS = {
    "sem_apoio": [],
    "btree":     ["idx_inscricao_id_membro", "idx_canal_id_streamer", "idx_canal_nro_plataforma"],
    "hash":      ["idx_inscricao_id_membro_hash", "idx_canal_id_streamer_hash", "idx_canal_nro_plataforma"],
    # escolha final (DEC-034): sai nro_plataforma (sem ganho), entra a cobertura
    "final":     ["idx_inscricao_id_membro", "idx_canal_id_streamer", "idx_video_id_canal_cobertura"],
    # final + o candidato do item 12 (seria o 6º: só para medir)
    "final_item12": ["idx_inscricao_id_membro", "idx_canal_id_streamer", "idx_video_id_canal_cobertura",
                     "idx_canal_plat_streamer_cob"],
}

# consultas que tocam Video ou Canal(nro_plataforma): as únicas que a troca
# do 5º índice pode mudar (as demais já foram medidas na fase "indices")
CONSULTAS_FINAL = {"i01_sem", "i01_peq", "i01_grd", "i02_com", "i04_sem", "i04_peq", "i07_sem", "i07_com", "i12_peq"}


def aplica_cenario(banco, cenario):
    drops = "".join(f"DROP INDEX IF EXISTS steam_do_bedo.{n};\n" for n in INDICES)
    creates = "".join(INDICES[n] + ";\n" for n in CENARIOS[cenario])
    psql(banco, drops + creates + "ANALYZE steam_do_bedo.inscricao; ANALYZE steam_do_bedo.canal; "
                                  "VACUUM (ANALYZE) steam_do_bedo.video; CHECKPOINT;")


def nos(plano):
    """Percorre o plano e devolve todos os nós."""
    pilha = [plano]
    while pilha:
        n = pilha.pop()
        yield n
        pilha.extend(n.get("Plans", []))


def resume(arquivo_json):
    dados = json.loads(Path(arquivo_json).read_text())[0]
    raiz = dados["Plan"]
    scans = []
    for n in nos(raiz):
        # só varreduras de tabela, índice ou view materializada (não as de
        # subconsulta, function ou CTE, que só repassam linhas)
        if "Scan" in n["Node Type"] and n["Node Type"] not in ("Subquery Scan", "Function Scan", "CTE Scan", "Values Scan", "WorkTable Scan"):
            rel = n.get("Relation Name") or n.get("Index Name") or ""
            lidos = n.get("Shared Read Blocks", 0) + n.get("Shared Hit Blocks", 0)
            scans.append((lidos, f"{n['Node Type']} {rel}".strip()))
    scans.sort(reverse=True)
    return {
        "planejamento_ms": dados.get("Planning Time"),
        "execucao_ms": dados.get("Execution Time"),
        "no_principal": scans[0][1] if scans else raiz["Node Type"],
        "scans": "; ".join(s for _, s in scans[:4]),
        "shared_read": raiz.get("Shared Read Blocks", 0),
        "shared_hit": raiz.get("Shared Hit Blocks", 0),
        "linhas": raiz.get("Actual Rows"),
    }


CAMPOS = ["fase", "consulta", "item", "filtro", "variante", "cenario", "cache", "rep",
          "planejamento_ms", "execucao_ms", "no_principal", "scans", "shared_read", "shared_hit", "linhas", "plano"]


def mede(banco, fase, cid, item, filtro, variante, sql, cenario, reps, quente, escritor):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as t:
        t.write(sql + "\n")
        arq_sql = t.name
    modos = (["quente"] if quente else ["frio", "quente"])
    for cache in modos:
        if cache == "quente":
            # aquecimento: a 1ª execução traz as páginas para o cache e não conta
            subprocess.run([str(BENCH / "medir.sh"), banco, arq_sql, os.devnull, "quente"], check=True)
        for rep in range(1, reps + 1):
            nome = f"{fase}__{cid}__{variante}__{cenario}__{cache}.json"
            destino = BENCH / "planos" / nome if rep == 1 else Path(tempfile.gettempdir()) / f"bench_{os.getpid()}.json"
            subprocess.run([str(BENCH / "medir.sh"), banco, arq_sql, str(destino), cache], check=True)
            r = resume(destino)
            linha = {"fase": fase, "consulta": cid, "item": item, "filtro": filtro, "variante": variante,
                     "cenario": cenario, "cache": cache, "rep": rep,
                     "plano": f"planos/{nome}" if rep == 1 else "", **r}
            escritor.writerow(linha)
            print(f"  {fase} {cid:8} {variante:8} {cenario:9} {cache:6} #{rep} "
                  f"{r['execucao_ms']:10.1f} ms  read={r['shared_read']:>7} hit={r['shared_hit']:>7}  {r['no_principal']}",
                  flush=True)
    os.unlink(arq_sql)


# ---------------------------------------------------------------------
# Overhead de escrita (P15, P17): INSERT ... SELECT de N linhas numa cópia
# da tabela (mesmas PK, UNIQUE e CHECK; sem FK), com e sem o índice, 3
# rodadas, CHECKPOINT antes de cada uma; mediana. Mede só o custo de
# manter o índice, a quente. OVERRIDING SYSTEM VALUE copia o id_canal
# (identity GENERATED ALWAYS) como está; ORDER BY random() insere em ordem
# aleatória, como chegariam as inscrições reais.
# ---------------------------------------------------------------------
def overhead_escrita(banco, escritor):
    casos = [
        ("inscricao", "id_membro", 300000),
        ("canal", "id_streamer", None),
        ("canal", "nro_plataforma", None),
        ("video", "id_canal) INCLUDE (visu_total", 300000),   # índice de cobertura
    ]
    for tabela, coluna, limite in casos:
        lim = f"LIMIT {limite}" if limite else ""
        for tipo in ["nenhum", "btree", "hash"]:
            if tipo == "hash" and (coluna == "nro_plataforma" or "INCLUDE" in coluna):
                continue
            tempos = []
            for rodada in range(3):
                idx = "" if tipo == "nenhum" else f"CREATE INDEX ON bench.copia USING {tipo} ({coluna});"
                psql(banco, f"""DROP TABLE IF EXISTS bench.copia;
                    CREATE TABLE bench.copia (LIKE steam_do_bedo.{tabela} INCLUDING ALL);
                    {idx} CHECKPOINT;""")
                saida = psql(banco, f"""EXPLAIN (ANALYZE, FORMAT JSON)
                    INSERT INTO bench.copia OVERRIDING SYSTEM VALUE SELECT * FROM steam_do_bedo.{tabela} ORDER BY random() {lim};""")
                tempos.append(json.loads(saida)[0]["Execution Time"])
            tam = um_valor(banco, "SELECT coalesce(sum(pg_relation_size(i.indexrelid)),0) FROM pg_index i "
                                  "WHERE i.indrelid = 'bench.copia'::regclass AND NOT i.indisunique")
            escritor.writerow({"operacao": f"INSERT {tabela}", "indice": coluna.replace(") INCLUDE (", " INCLUDE ") if tipo != "nenhum" else "(sem índice extra)",
                               "tipo": tipo, "linhas": limite or um_valor(banco, f"SELECT count(*) FROM steam_do_bedo.{tabela}"),
                               "mediana_ms": round(statistics.median(tempos), 1),
                               "tempos_ms": " ".join(f"{t:.1f}" for t in tempos), "tamanho_indice_bytes": tam})
            print(f"  escrita {tabela}.{coluna} {tipo}: {statistics.median(tempos):.1f} ms", flush=True)
    psql(banco, "DROP TABLE IF EXISTS bench.copia;")

    # custo do REFRESH das materializadas (concorrente e comum)
    for mv in ["mv_interacoes_video", "mv_faturamento_canal"]:
        for modo in ["CONCURRENTLY", ""]:
            # o tempo é medido dentro do servidor e volta no NOTICE (stderr),
            # para não somar o custo do docker exec
            tempos = []
            for rodada in range(3):
                r = subprocess.run(["docker", "exec", "-i", CT, "psql", "-U", USR, "-d", banco, "-X", "-q"],
                                   input=f"""DO $$ DECLARE t0 timestamptz := clock_timestamp(); BEGIN
                    REFRESH MATERIALIZED VIEW {modo} steam_do_bedo.{mv};
                    RAISE NOTICE 'ms=%', round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1);
                    END $$;""", capture_output=True, text=True, check=True)
                tempos.append(float(r.stderr.split("ms=")[1].split()[0]))
            escritor.writerow({"operacao": f"REFRESH {modo or 'comum'}".strip(), "indice": mv, "tipo": "view materializada",
                               "linhas": um_valor(banco, f"SELECT count(*) FROM steam_do_bedo.{mv}"),
                               "mediana_ms": round(statistics.median(tempos), 1),
                               "tempos_ms": " ".join(f"{t:.1f}" for t in tempos),
                               "tamanho_indice_bytes": um_valor(banco, f"SELECT pg_indexes_size('steam_do_bedo.{mv}')")})
            print(f"  refresh {mv} {modo or 'comum'}: {statistics.median(tempos):.1f} ms", flush=True)


def tamanhos(banco):
    linhas = psql(banco, """
        SELECT c.relname, CASE c.relkind WHEN 'i' THEN 'indice' WHEN 'm' THEN 'view materializada' ELSE 'tabela' END,
               coalesce(t.relname, ''), am.amname, pg_relation_size(c.oid), c.reltuples::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'steam_do_bedo'
        LEFT JOIN pg_index i ON i.indexrelid = c.oid
        LEFT JOIN pg_class t ON t.oid = i.indrelid
        LEFT JOIN pg_am am ON am.oid = c.relam
        WHERE c.relkind IN ('r', 'i', 'm')
        ORDER BY pg_relation_size(c.oid) DESC""")
    with open(BENCH / "tamanhos.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["objeto", "tipo", "tabela", "metodo", "bytes", "linhas_estimadas"])
        for l in linhas.splitlines():
            w.writerow(l.split("|"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--banco", default="stream_bench")
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--so-quente", action="store_true", help="pula as medidas a frio (teste rápido do script)")
    ap.add_argument("--fases", default="base,reescrita,indices,hash,final,item12,escrita")
    a = ap.parse_args()
    fases = a.fases.split(",")

    config = psql(a.banco, "SELECT version(); SHOW shared_buffers; SHOW work_mem; SHOW effective_cache_size; SHOW random_page_cost;")
    (BENCH / "configuracao.txt").write_text(
        "Configuração do servidor de aferição (as sessões de medida fixam jit=off e "
        "max_parallel_workers_per_gather=0; ver bench/medir.sh)\n" + config + "\n")
    f = filtros(a.banco)
    (BENCH / "filtros.json").write_text(json.dumps(f, ensure_ascii=False, indent=2))
    print("filtros:", f, flush=True)

    novo = not (BENCH / "resultados.csv").exists() or "base" in fases
    with open(BENCH / "resultados.csv", "w" if novo else "a", newline="") as arq:
        w = csv.DictWriter(arq, fieldnames=CAMPOS)
        if novo:
            w.writeheader()
        if "base" in fases:            # P13: linha de base, só PK/UNIQUE
            aplica_cenario(a.banco, "sem_apoio")
            for cid, item, filtro, var, sql in consultas(f):
                mede(a.banco, "base", cid, item, filtro, var, sql, "sem_apoio", a.reps, a.so_quente, w)
        if "reescrita" in fases:       # P13 e P09: original x direta x virtual (sem índices de apoio)
            aplica_cenario(a.banco, "sem_apoio")
            for cid, item, filtro, var, sql in consultas_alternativas(f):
                mede(a.banco, "reescrita", cid, item, filtro, var, sql, "sem_apoio", a.reps, a.so_quente, w)
        if "indices" in fases:         # P15: com os índices escolhidos (B-tree)
            aplica_cenario(a.banco, "btree")
            for cid, item, filtro, var, sql in consultas(f):
                mede(a.banco, "indices", cid, item, filtro, var, sql, "btree", a.reps, a.so_quente, w)
        if "hash" in fases:            # P15: hash no lugar de B-tree onde o predicado é só igualdade
            aplica_cenario(a.banco, "hash")
            for cid, item, filtro, var, sql in consultas(f):
                if cid in ("i03_com", "i06_com"):
                    mede(a.banco, "hash", cid, item, filtro, var, sql, "hash", a.reps, a.so_quente, w)
        if "final" in fases:           # P15: conjunto final, com o índice de cobertura
            aplica_cenario(a.banco, "final")
            for cid, item, filtro, var, sql in consultas(f):
                if cid in CONSULTAS_FINAL:
                    mede(a.banco, "final", cid, item, filtro, var, sql, "final", a.reps, a.so_quente, w)
    if "item12" in fases:              # DEC-035: item 12 em todos os cenários
        with open(BENCH / "resultados.csv", "a", newline="") as arq:
            w = csv.DictWriter(arq, fieldnames=CAMPOS)
            aplica_cenario(a.banco, "sem_apoio")
            for cid, item, filtro, var, sql in consultas_item12(f):
                mede(a.banco, "item12", cid, item, filtro, var, sql, "sem_apoio", a.reps, a.so_quente, w)
            for cen in ["final", "final_item12"]:
                aplica_cenario(a.banco, cen)
                for cid, item, filtro, var, sql in consultas_item12(f):
                    if var == "final":
                        mede(a.banco, "item12", cid, item, filtro, var, sql, cen, a.reps, a.so_quente, w)
    if "escrita" in fases:             # P15 e P17: overhead de escrita e REFRESH
        aplica_cenario(a.banco, "sem_apoio")
        with open(BENCH / "escrita.csv", "w", newline="") as arq:
            w = csv.DictWriter(arq, fieldnames=["operacao", "indice", "tipo", "linhas", "mediana_ms", "tempos_ms",
                                                "tamanho_indice_bytes"])
            w.writeheader()
            overhead_escrita(a.banco, w)
    aplica_cenario(a.banco, "final")
    tamanhos(a.banco)
    print("fim", flush=True)


if __name__ == "__main__":
    sys.exit(main())

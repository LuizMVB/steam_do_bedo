#!/usr/bin/env python3
# =====================================================================
# Projeto de Banco de Dados 2026/2 - Stream do Bedo
# bench/aferir.py · aferição das consultas, views e índices
#
# O que faz: roda a matriz consulta × cenário de índices × cache (frio e
# quente), 5 repetições por célula, e grava a ORIGEM de cada número do
# benchmark.md:
#   bench/resultados.csv      uma linha por execução medida (todas as reps)
#   bench/planos/<fase>/*.txt um arquivo por célula: a consulta, a tabela
#                             das 5 repetições, qual delas é a mediana e o
#                             EXPLAIN (ANALYZE, BUFFERS) completo DESSA
#                             repetição. O "Execution Time" e o "Buffers"
#                             do nó raiz no arquivo são o número citado.
#   bench/escrita.csv         overhead de INSERT em lote e custo do REFRESH
#   bench/planos/escrita/*.txt EXPLAIN ANALYZE do INSERT mediano de cada caso
#   bench/tamanhos.csv        tamanho de cada tabela e índice (cenário final)
#   bench/filtros.json        valores de filtro usados (tirados dos dados)
#   bench/configuracao.txt    versão e parâmetros do servidor
#
# Protocolo a frio (antes de CADA medida): para o container (esvazia o
# shared_buffers), esvazia o cache de páginas da VM do Docker
# ("echo 3 > /proc/sys/vm/drop_caches" num container privilegiado, que só
# existe enquanto o do banco está parado) e sobe de novo. A quente: uma
# execução de aquecimento descartada e depois as 5 medidas.
# Sessão de medida: jit = off e max_parallel_workers_per_gather = 0.
#
# Item 12 é plpgsql: o EXPLAIN de fora só mostra "Function Scan". Para
# mostrar o plano de dentro, as chamadas plpgsql rodam com auto_explain
# (log_nested_statements, nível NOTICE), e o plano interno vai para o
# arquivo da célula logo depois do plano externo.
#
# Ordem: banco stream_bench carregado com ddl -> seed -> views ->
# functions e depois bench/consultas_alternativas.sql. Triggers não são
# criados (não influem em leitura).
# Uso:  python3 bench/aferir.py [--banco stream_bench] [--reps 5]
#                               [--fases base,final,reescrita,...] [--retomar]
# Cuidado:
#   * Leva de 2 a 3 horas; cada medida a frio reinicia o container CT.
#   * Só um container ligado por vez: o de drop_caches roda com o do banco
#     parado.
# =====================================================================
import argparse
import csv
import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BENCH = RAIZ / "bench"
PLANOS = BENCH / "planos"
CT = os.environ.get("CT", "steam-do-bedo-db")
USR = os.environ.get("PGUSER_BENCH", "admin")

SESSAO = "SET jit = off;\nSET max_parallel_workers_per_gather = 0;\n"
# plano interno das functions plpgsql (item 12), enviado ao cliente como NOTICE
AUTO_EXPLAIN = ("LOAD 'auto_explain';\n"
                "SET auto_explain.log_min_duration = 0;\n"
                "SET auto_explain.log_analyze = on;\n"
                "SET auto_explain.log_buffers = on;\n"
                "SET auto_explain.log_nested_statements = on;\n"
                "SET auto_explain.log_level = notice;\n")


def psql(banco, sql, at=True):
    """Executa SQL no container e devolve (stdout, stderr)."""
    args = ["docker", "exec", "-i", CT, "psql", "-U", USR, "-d", banco, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
    if at:
        args += ["-At"]
    r = subprocess.run(args, input=sql, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"psql falhou: {r.stderr.strip()}\nSQL: {sql[:300]}")
    return r.stdout.strip(), r.stderr.strip()


def um_valor(banco, sql):
    return psql(banco, sql)[0].splitlines()[0]


def esfria(banco):
    """Para o Postgres, esvazia o cache da VM e sobe de novo."""
    subprocess.run(["docker", "stop", "-t", "60", CT], check=True, capture_output=True)
    subprocess.run(["docker", "run", "--rm", "--privileged", "postgres:17",
                    "sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches"], check=True, capture_output=True)
    subprocess.run(["docker", "start", CT], check=True, capture_output=True)
    for _ in range(200):
        r = subprocess.run(["docker", "exec", CT, "psql", "-U", USR, "-d", banco, "-Atqc", "SELECT 1"],
                           capture_output=True)
        if r.returncode == 0:
            return
        time.sleep(0.3)
    raise RuntimeError("o banco não voltou depois do restart")


# ---------------------------------------------------------------------
# Leitura do EXPLAIN em texto
# ---------------------------------------------------------------------
RE_EXEC = re.compile(r"Execution Time: ([\d.]+) ms")
RE_PLAN = re.compile(r"Planning Time: ([\d.]+) ms")
RE_SCAN = re.compile(r"(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Bitmap Index Scan)"
                     r"(?: Backward)?(?: using (\S+))? on (\S+)")


def resume(texto, interno=""):
    linhas = texto.splitlines()
    # "Buffers" do nó raiz: a primeira linha Buffers antes da seção Planning
    read = hit = 0
    for l in linhas:
        if l.strip().startswith("Planning"):
            break
        if l.strip().startswith("Buffers:"):
            shared = l.split("shared", 1)[1].split(",")[0] if "shared" in l else ""
            m = re.search(r"hit=(\d+)", shared)
            hit = int(m.group(1)) if m else 0
            m = re.search(r"read=(\d+)", shared)
            read = int(m.group(1)) if m else 0
            break
    scans = []
    for l in linhas + interno.splitlines():
        m = RE_SCAN.search(l)
        if m:
            tipo, idx, rel = m.groups()
            s = f"{tipo} {idx or rel}"
            if s not in scans:
                scans.append(s)
    return {"execucao_ms": float(RE_EXEC.search(texto).group(1)),
            "planejamento_ms": float(RE_PLAN.search(texto).group(1)),
            "shared_read": read, "shared_hit": hit,
            "scans": "; ".join(scans[:5])}


# ---------------------------------------------------------------------
# Valores de filtro, tirados dos dados.
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
    """Itens 1 a 12 na versão entregue: (id, item, filtro, variante, SQL)."""
    s = "steam_do_bedo."
    return [
        ("i01_sem", 1, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados();"),
        ("i01_peq", 1, "Kick", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados({f['plat_peq']});"),
        ("i01_grd", 1, "YouTube", "final", f"SELECT * FROM {s}sp_obter_streamers_com_maior_qtd_videos_publicados({f['plat_grd']});"),
        ("i02_sem", 2, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_videos_mais_comentados();"),
        ("i02_com", 2, "canal", "final", f"SELECT * FROM {s}sp_obter_videos_mais_comentados({q(f['canal'])});"),
        ("i03_sem", 3, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_canais_por_qtd_total_interacoes();"),
        ("i03_com", 3, "streamer", "final", f"SELECT * FROM {s}sp_obter_canais_por_qtd_total_interacoes({q(f['streamer'])});"),
        ("i04_sem", 4, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_canais_pela_media_doacoes_por_comentario();"),
        ("i04_peq", 4, "Kick", "final", f"SELECT * FROM {s}sp_obter_canais_pela_media_doacoes_por_comentario({f['plat_peq']});"),
        ("i05_sem", 5, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_canais_patrocinados_com_valores_por_empresa();"),
        ("i05_com", 5, "empresa", "final", f"SELECT * FROM {s}sp_obter_canais_patrocinados_com_valores_por_empresa({q(f['empresa'])});"),
        ("i06_sem", 6, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_qtd_canais_e_gasto_mensal_por_usuario();"),
        ("i06_com", 6, "usuario", "final", f"SELECT * FROM {s}sp_obter_qtd_canais_e_gasto_mensal_por_usuario({q(f['usuario'])});"),
        ("i07_sem", 7, "sem filtro", "final", f"SELECT * FROM {s}sp_obter_canais_com_doacoes_recebidas();"),
        ("i07_com", 7, "canal", "final", f"SELECT * FROM {s}sp_obter_canais_com_doacoes_recebidas({q(f['canal'])});"),
        ("i08_k10", 8, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_patrocinio(10);"),
        ("i09_k10", 9, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_aportes_de_membros(10);"),
        ("i10_k10", 10, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_doacoes_recebidas(10);"),
        ("i11_k10", 11, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_canais_por_faturamento(10);"),
        ("i12_sem", 12, "k=10", "final", f"SELECT * FROM {s}sp_obter_top_k_plataformas_por_streamers_e_canais(10);"),
        ("i12_peq", 12, "k=10, Kick", "final", f"SELECT * FROM {s}sp_obter_top_k_plataformas_por_streamers_e_canais(10, {f['plat_peq']});"),
        ("i12_grd", 12, "k=10, YouTube", "final", f"SELECT * FROM {s}sp_obter_top_k_plataformas_por_streamers_e_canais(10, {f['plat_grd']});"),
    ]


def consultas_alternativas(f):
    """Seções 2 e 3 do benchmark.md: original x reescrita x virtual."""
    return [
        ("i02_sem", 2, "sem filtro", "original", "SELECT * FROM bench.item2_original();"),
        ("i02_com", 2, "canal", "original", f"SELECT * FROM bench.item2_original({q(f['canal'])});"),
        ("i02_sem", 2, "sem filtro", "reescrita", "SELECT * FROM bench.item2_direta();"),
        ("i02_com", 2, "canal", "reescrita", f"SELECT * FROM bench.item2_direta({q(f['canal'])});"),
        ("i03_sem", 3, "sem filtro", "original", "SELECT * FROM bench.item3_original();"),
        ("i03_com", 3, "streamer", "original", f"SELECT * FROM bench.item3_original({q(f['streamer'])});"),
        ("i03_sem", 3, "sem filtro", "reescrita", "SELECT * FROM bench.item3_direta();"),
        ("i03_com", 3, "streamer", "reescrita", f"SELECT * FROM bench.item3_direta({q(f['streamer'])});"),
        ("i10_k10", 10, "k=10", "direta", "SELECT * FROM bench.item10_direta(10);"),
        ("i10_k10", 10, "k=10", "virtual", "SELECT * FROM bench.item10_virtual(10);"),
        ("i11_k10", 11, "k=10", "direta", "SELECT * FROM bench.item11_direta(10);"),
        ("i11_k10", 11, "k=10", "virtual", "SELECT * FROM bench.item11_virtual(10);"),
    ]


def consultas_item12(f):
    """Seção 7: versão anterior, V5 virtual e V5 materializada."""
    p, g = f["plat_peq"], f["plat_grd"]
    return [
        ("i12_sem", 12, "k=10", "anterior", "SELECT * FROM bench.item12_anterior(10);"),
        ("i12_peq", 12, "k=10, Kick", "anterior", f"SELECT * FROM bench.item12_anterior(10, {p});"),
        ("i12_grd", 12, "k=10, YouTube", "anterior", f"SELECT * FROM bench.item12_anterior(10, {g});"),
        ("i12_sem", 12, "k=10", "v5_virtual", "SELECT * FROM bench.item12_v5(false, 10);"),
        ("i12_peq", 12, "k=10, Kick", "v5_virtual", f"SELECT * FROM bench.item12_v5(false, 10, {p});"),
        ("i12_grd", 12, "k=10, YouTube", "v5_virtual", f"SELECT * FROM bench.item12_v5(false, 10, {g});"),
        ("i12_sem", 12, "k=10", "v5_mat", "SELECT * FROM bench.item12_v5(true, 10);"),
        ("i12_peq", 12, "k=10, Kick", "v5_mat", f"SELECT * FROM bench.item12_v5(true, 10, {p});"),
        ("i12_grd", 12, "k=10, YouTube", "v5_mat", f"SELECT * FROM bench.item12_v5(true, 10, {g});"),
    ]


def plpgsql(sql):
    """Chamadas cujo plano interno o EXPLAIN de fora não mostra."""
    return "plataformas_por_streamers" in sql or "item12_v5" in sql


# ---------------------------------------------------------------------
# Cenários de índices de apoio. "sem_apoio" = só PK, UNIQUE e os UNIQUE
# das views materializadas (exigidos pelo REFRESH CONCURRENTLY).
# ---------------------------------------------------------------------
INDICES = {
    "idx_inscricao_id_membro":      "CREATE INDEX idx_inscricao_id_membro ON steam_do_bedo.inscricao (id_membro)",
    "idx_inscricao_id_membro_hash": "CREATE INDEX idx_inscricao_id_membro_hash ON steam_do_bedo.inscricao USING hash (id_membro)",
    "idx_canal_id_streamer":        "CREATE INDEX idx_canal_id_streamer ON steam_do_bedo.canal (id_streamer)",
    "idx_canal_id_streamer_hash":   "CREATE INDEX idx_canal_id_streamer_hash ON steam_do_bedo.canal USING hash (id_streamer)",
    "idx_canal_nro_plataforma":     "CREATE INDEX idx_canal_nro_plataforma ON steam_do_bedo.canal (nro_plataforma)",
    "idx_video_id_canal_cobertura": "CREATE INDEX idx_video_id_canal_cobertura ON steam_do_bedo.video (id_canal) INCLUDE (visu_total)",
    "idx_canal_plat_streamer_cob":  "CREATE INDEX idx_canal_plat_streamer_cob ON steam_do_bedo.canal (nro_plataforma, id_streamer) INCLUDE (qtd_visualizacoes)",
}
FINAIS = ["idx_inscricao_id_membro", "idx_canal_id_streamer", "idx_video_id_canal_cobertura"]
CENARIOS = {
    "sem_apoio": [],
    "final": FINAIS,                                         # os 3 entregues em functions.sql
    "hash": ["idx_inscricao_id_membro_hash", "idx_canal_id_streamer_hash", "idx_video_id_canal_cobertura"],
    "final_plataforma": FINAIS + ["idx_canal_nro_plataforma"],      # candidato descartado
    "final_item12": FINAIS + ["idx_canal_plat_streamer_cob"],        # candidato do item 12
}
DESCRICAO = {
    "sem_apoio": "só PK, UNIQUE e os UNIQUE das views materializadas",
    "final": "índices de apoio entregues: " + ", ".join(FINAIS),
    "hash": "hash em Inscricao(id_membro) e Canal(id_streamer), no lugar dos B-tree",
    "final_plataforma": "entregues + idx_canal_nro_plataforma (candidato descartado)",
    "final_item12": "entregues + idx_canal_plat_streamer_cob (candidato do item 12)",
}


def aplica_cenario(banco, cenario):
    drops = "".join(f"DROP INDEX IF EXISTS steam_do_bedo.{n};\n" for n in INDICES)
    creates = "".join(INDICES[n] + ";\n" for n in CENARIOS[cenario])
    psql(banco, drops + creates + "ANALYZE steam_do_bedo.inscricao; ANALYZE steam_do_bedo.canal; "
                                  "VACUUM (ANALYZE) steam_do_bedo.video; CHECKPOINT;")
    print(f"cenário {cenario}: {DESCRICAO[cenario]}", flush=True)


CAMPOS = ["fase", "consulta", "item", "filtro", "variante", "cenario", "cache", "rep", "mediana",
          "planejamento_ms", "execucao_ms", "shared_read", "shared_hit", "paginas", "scans", "plano"]


def executa(banco, sql):
    pre = SESSAO + (AUTO_EXPLAIN if plpgsql(sql) else "")
    out, err = psql(banco, pre + "EXPLAIN (ANALYZE, BUFFERS)\n" + sql + "\n")
    return out, err


def mede(banco, fase, cid, item, filtro, variante, sql, cenario, reps, escritor, feitas):
    for cache in ["frio", "quente"]:
        rel = f"planos/{fase}/{cid}__{variante}__{cenario}__{cache}.txt"
        if (fase, cid, variante, cenario, cache) in feitas:
            continue
        if cache == "quente":
            executa(banco, sql)                       # aquecimento: não conta
        medidas = []
        for rep in range(1, reps + 1):
            if cache == "frio":
                esfria(banco)
            out, err = executa(banco, sql)
            r = resume(out, err)
            medidas.append((rep, r, out, err))
            print(f"  {fase:9} {cid:8} {variante:10} {cenario:16} {cache:6} #{rep} "
                  f"{r['execucao_ms']:10.1f} ms  read={r['shared_read']:>7} hit={r['shared_hit']:>7}  {r['scans'][:60]}",
                  flush=True)
        # mediana: a repetição do meio pelo tempo de execução
        ordem = sorted(medidas, key=lambda m: m[1]["execucao_ms"])
        rep_med = ordem[len(ordem) // 2][0]
        grava_plano(BENCH / rel, fase, cid, item, filtro, variante, sql, cenario, cache, medidas, rep_med)
        for rep, r, _, _ in medidas:
            escritor.writerow({"fase": fase, "consulta": cid, "item": item, "filtro": filtro, "variante": variante,
                               "cenario": cenario, "cache": cache, "rep": rep, "mediana": int(rep == rep_med),
                               "paginas": r["shared_read"] + r["shared_hit"], "plano": rel, **r})
        escritor.arq.flush()


def grava_plano(destino, fase, cid, item, filtro, variante, sql, cenario, cache, medidas, rep_med):
    destino.parent.mkdir(parents=True, exist_ok=True)
    tempos = sorted(m[1]["execucao_ms"] for m in medidas)
    with open(destino, "w") as f:
        f.write(f"-- Item {item} · filtro: {filtro} · variante: {variante}\n")
        f.write(f"-- Cenário de índices: {cenario} ({DESCRICAO[cenario]})\n")
        f.write(f"-- Cache: {cache}" + (" (restart do Postgres + drop_caches antes de cada repetição)\n"
                                         if cache == "frio" else " (1 execução de aquecimento descartada)\n"))
        f.write("-- Sessão: SET jit = off; SET max_parallel_workers_per_gather = 0;\n")
        f.write(f"-- Consulta medida:\n--   EXPLAIN (ANALYZE, BUFFERS) {sql}\n--\n")
        f.write("-- Repetições (Execution Time e Buffers do nó raiz de cada uma):\n")
        f.write("--   rep | execução (ms) | planejamento (ms) | shared read | shared hit | páginas\n")
        for rep, r, _, _ in medidas:
            marca = "  <- mediana" if rep == rep_med else ""
            f.write(f"--   {rep:>3} | {r['execucao_ms']:>13.3f} | {r['planejamento_ms']:>17.3f} | "
                    f"{r['shared_read']:>11} | {r['shared_hit']:>10} | {r['shared_read'] + r['shared_hit']:>7}{marca}\n")
        f.write(f"-- Mediana do tempo: {statistics.median(tempos):.3f} ms "
                f"(repetições em ordem: {', '.join(f'{t:.1f}' for t in tempos)})\n")
        f.write(f"-- Abaixo, o plano completo da repetição {rep_med} (a mediana).\n\n")
        _, _, out, err = next(m for m in medidas if m[0] == rep_med)
        f.write(out + "\n")
        if err:
            f.write("\n-- Plano interno da function plpgsql (auto_explain, mesma execução):\n\n")
            f.write(err.replace("psql:<stdin>:", "") + "\n")


# ---------------------------------------------------------------------
# Overhead de escrita: INSERT ... SELECT de N linhas, em ordem aleatória,
# numa cópia da tabela (mesmas PK, UNIQUE e CHECK; sem FK), com e sem o
# índice; 3 rodadas com CHECKPOINT antes; mediana. A quente.
# ---------------------------------------------------------------------
def overhead_escrita(banco, escritor):
    casos = [
        ("inscricao", "id_membro", 300000, ["nenhum", "btree", "hash"]),
        ("canal", "id_streamer", None, ["nenhum", "btree", "hash"]),
        ("canal", "nro_plataforma", None, ["btree"]),
        ("video", "id_canal) INCLUDE (visu_total", 300000, ["nenhum", "btree"]),
    ]
    for tabela, coluna, limite, tipos in casos:
        lim = f"LIMIT {limite}" if limite else ""
        for tipo in tipos:
            medidas = []
            for rodada in range(1, 4):
                idx = "" if tipo == "nenhum" else f"CREATE INDEX ON bench.copia USING {tipo} ({coluna});"
                psql(banco, f"""DROP TABLE IF EXISTS bench.copia;
                    CREATE TABLE bench.copia (LIKE steam_do_bedo.{tabela} INCLUDING ALL);
                    {idx} CHECKPOINT;""")
                sql = (f"INSERT INTO bench.copia OVERRIDING SYSTEM VALUE\n"
                       f"SELECT * FROM steam_do_bedo.{tabela} ORDER BY random() {lim};")
                out, _ = psql(banco, SESSAO + "EXPLAIN (ANALYZE, BUFFERS)\n" + sql)
                medidas.append((rodada, float(RE_EXEC.search(out).group(1)), out))
            tam = um_valor(banco, "SELECT coalesce(sum(pg_relation_size(i.indexrelid)),0) FROM pg_index i "
                                  "WHERE i.indrelid = 'bench.copia'::regclass AND NOT i.indisunique")
            nome_col = coluna.replace(") INCLUDE (", "_inc_")
            rel = f"planos/escrita/insert_{tabela}__{nome_col}__{tipo}.txt"
            ordem = sorted(medidas, key=lambda m: m[1])
            rod_med = ordem[1][0]
            n = limite or um_valor(banco, f"SELECT count(*) FROM steam_do_bedo.{tabela}")
            destino = BENCH / rel
            destino.parent.mkdir(parents=True, exist_ok=True)
            with open(destino, "w") as f:
                f.write(f"-- INSERT em lote em {tabela}: {n} linhas em ordem aleatória numa cópia vazia\n")
                f.write(f"-- Índice extra: {'nenhum' if tipo == 'nenhum' else tipo + ' (' + coluna + ')'}\n")
                f.write(f"-- Tamanho do índice extra no fim: {int(tam):,} bytes\n".replace(",", "."))
                f.write("-- Rodadas (Execution Time):\n")
                for rod, t, _ in medidas:
                    f.write(f"--   {rod} | {t:10.3f} ms" + ("  <- mediana" if rod == rod_med else "") + "\n")
                f.write(f"-- Abaixo, o plano da rodada {rod_med} (a mediana).\n\n")
                f.write(next(m[2] for m in medidas if m[0] == rod_med) + "\n")
            escritor.writerow({"operacao": f"INSERT {tabela}",
                               "indice": coluna.replace(") INCLUDE (", " INCLUDE ") if tipo != "nenhum" else "(sem índice extra)",
                               "tipo": tipo, "linhas": n,
                               "mediana_ms": round(statistics.median(m[1] for m in medidas), 1),
                               "tempos_ms": " ".join(f"{m[1]:.1f}" for m in medidas),
                               "tamanho_indice_bytes": tam, "plano": rel})
            print(f"  escrita {tabela}.{coluna} {tipo}: {statistics.median(m[1] for m in medidas):.1f} ms", flush=True)
    psql(banco, "DROP TABLE IF EXISTS bench.copia;")

    # REFRESH não aceita EXPLAIN: o tempo é medido no servidor (clock_timestamp)
    log = []
    for mv in ["mv_interacoes_video", "mv_faturamento_canal"]:
        for modo in ["", "CONCURRENTLY"]:
            tempos = []
            for _ in range(3):
                _, err = psql(banco, f"""DO $$ DECLARE t0 timestamptz := clock_timestamp(); BEGIN
                    REFRESH MATERIALIZED VIEW {modo} steam_do_bedo.{mv};
                    RAISE NOTICE 'ms=%', round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1);
                    END $$;""")
                tempos.append(float(err.split("ms=")[1].split()[0]))
            linhas = um_valor(banco, f"SELECT count(*) FROM steam_do_bedo.{mv}")
            log.append(f"REFRESH MATERIALIZED VIEW {modo + ' ' if modo else ''}steam_do_bedo.{mv}  "
                       f"({linhas} linhas): {', '.join(f'{t:.1f}' for t in tempos)} ms -> mediana "
                       f"{statistics.median(tempos):.1f} ms")
            escritor.writerow({"operacao": f"REFRESH {modo or 'comum'}", "indice": mv, "tipo": "view materializada",
                               "linhas": linhas, "mediana_ms": round(statistics.median(tempos), 1),
                               "tempos_ms": " ".join(f"{t:.1f}" for t in tempos),
                               "tamanho_indice_bytes": um_valor(banco, f"SELECT pg_indexes_size('steam_do_bedo.{mv}')"),
                               "plano": "planos/escrita/refresh.txt"})
            print("  " + log[-1], flush=True)
    (PLANOS / "escrita" / "refresh.txt").write_text(
        "-- REFRESH não aceita EXPLAIN. Cada tempo foi medido dentro do servidor:\n"
        "--   DO $$ DECLARE t0 timestamptz := clock_timestamp(); BEGIN\n"
        "--       REFRESH MATERIALIZED VIEW [CONCURRENTLY] <view>;\n"
        "--       RAISE NOTICE 'ms=%', <clock_timestamp() - t0 em ms>; END $$;\n"
        "-- 3 rodadas por linha, a quente; o valor usado é a mediana.\n\n" + "\n".join(log) + "\n")


def tamanhos(banco):
    out, _ = psql(banco, """
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
        for l in out.splitlines():
            w.writerow(l.split("|"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--banco", default="stream_bench")
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--fases", default="base,reescrita,item12,final,hash,plataforma,cobertura12,escrita")
    ap.add_argument("--retomar", action="store_true", help="pula as células que já estão no resultados.csv")
    a = ap.parse_args()
    fases = a.fases.split(",")
    PLANOS.mkdir(exist_ok=True)

    config, _ = psql(a.banco, "SELECT version(); SHOW shared_buffers; SHOW work_mem; "
                              "SHOW effective_cache_size; SHOW random_page_cost;")
    tam_db = um_valor(a.banco, "SELECT pg_size_pretty(pg_database_size(current_database()))")
    (BENCH / "configuracao.txt").write_text(
        "Servidor de aferição (as sessões de medida fixam jit=off e max_parallel_workers_per_gather=0)\n"
        "version / shared_buffers / work_mem / effective_cache_size / random_page_cost:\n"
        + config + f"\ntamanho do banco {a.banco}: {tam_db}\n")
    f = filtros(a.banco)
    (BENCH / "filtros.json").write_text(json.dumps(f, ensure_ascii=False, indent=2) + "\n")
    print("filtros:", f, flush=True)

    arq_res = BENCH / "resultados.csv"
    feitas = set()
    if a.retomar and arq_res.exists():
        with open(arq_res) as fr:
            feitas = {(l["fase"], l["consulta"], l["variante"], l["cenario"], l["cache"]) for l in csv.DictReader(fr)}
    novo = not (a.retomar and arq_res.exists())
    with open(arq_res, "w" if novo else "a", newline="") as arq:
        w = csv.DictWriter(arq, fieldnames=CAMPOS)
        w.arq = arq
        if novo:
            w.writeheader()

        def roda(fase, cenario, lista):
            aplica_cenario(a.banco, cenario)
            for cid, item, filtro, var, sql in lista:
                mede(a.banco, fase, cid, item, filtro, var, sql, cenario, a.reps, w, feitas)

        if "base" in fases:         # seções 1, 2, 3, 4 e 7: versão entregue sem índices de apoio
            roda("base", "sem_apoio", consultas(f))
        if "reescrita" in fases:    # seções 2 e 3: formas alternativas, sem índices de apoio
            roda("reescrita", "sem_apoio", consultas_alternativas(f))
        if "item12" in fases:       # seção 7: alternativas do item 12, sem índices de apoio
            roda("item12", "sem_apoio", consultas_item12(f))
        if "final" in fases:        # seções 4, 5, 6 e 7: com os índices entregues
            roda("final", "final", consultas(f))
        if "hash" in fases:         # seção 5: hash no lugar dos B-tree de igualdade
            roda("hash", "hash", [c for c in consultas(f) if c[0] in ("i03_com", "i06_com")])
        if "plataforma" in fases:   # seção 6: candidato descartado Canal(nro_plataforma)
            roda("plataforma", "final_plataforma",
                 [c for c in consultas(f) if c[0] in ("i01_peq", "i01_grd", "i04_peq", "i12_sem", "i12_peq", "i12_grd")])
        if "cobertura12" in fases:  # seção 7: candidato de cobertura em Canal para o item 12
            roda("item12", "final_item12", [c for c in consultas(f) if c[1] == 12])
    if "escrita" in fases:          # seção 6: overhead de INSERT e REFRESH
        aplica_cenario(a.banco, "sem_apoio")
        with open(BENCH / "escrita.csv", "w", newline="") as arq:
            w = csv.DictWriter(arq, fieldnames=["operacao", "indice", "tipo", "linhas", "mediana_ms", "tempos_ms",
                                                "tamanho_indice_bytes", "plano"])
            w.writeheader()
            overhead_escrita(a.banco, w)
    aplica_cenario(a.banco, "final")
    tamanhos(a.banco)
    print("fim", flush=True)


if __name__ == "__main__":
    sys.exit(main())

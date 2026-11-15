#!/usr/bin/env python3
# =====================================================================
# bench/graficos.py · gráficos da aferição (P18)
#
# O que faz: lê bench/resultados.csv e bench/escrita.csv (gerados por
# bench/aferir.py) e grava PNGs em bench/graficos/:
#   01_tempo_indices_frio.png   tempo a frio, sem x com índices (log)
#   02_buffers_indices.png      páginas lidas (shared read + hit), sem x com
#   03_reescrita.png            itens 2 e 3: original x reescrita x view mat.
#   04_views.png                itens 10 e 11: direta x virtual x materializada
#   05_ganho_overhead.png       por índice: ganho de leitura, overhead de
#                               inserção e tamanho (argumento do teto de 5)
#   06_frio_quente.png          linha de base a frio x a quente (o protocolo)
#   07_hash_btree.png           hash x B-tree nas consultas de igualdade
#   08_item12.png               item 12 (desafio): versão anterior x final x
#                               índice de cobertura x V5 virtual x V5 mat.
# Cada barra é a MEDIANA das repetições (DEC-032).
#
# Ordem: depois de bench/aferir.py.
# Uso: python3 bench/graficos.py   (precisa de matplotlib: bench/requirements.txt)
# Cores: paleta categórica de referência validada para daltonismo (azul,
#   laranja, verde-água, na ordem fixa); a mesma variante tem sempre a
#   mesma cor em todos os gráficos. Escala log onde os ganhos variam em
#   ordens de grandeza (indicado no eixo).
# DEC-032, DEC-033, DEC-034
# =====================================================================
import csv
import statistics
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

BENCH = Path(__file__).resolve().parent
SAIDA = BENCH / "graficos"
SAIDA.mkdir(exist_ok=True)

AZUL, LARANJA, AGUA = "#2a78d6", "#eb6834", "#1baf7a"
AMARELO, MAGENTA = "#eda100", "#e87ba4"   # slots 4 e 5 da paleta, só no gráfico 08
TEXTO, TEXTO2, GRADE, FUNDO = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"

plt.rcParams.update({
    "figure.facecolor": FUNDO, "axes.facecolor": FUNDO, "savefig.facecolor": FUNDO,
    "axes.edgecolor": GRADE, "axes.labelcolor": TEXTO2, "xtick.color": TEXTO2, "ytick.color": TEXTO2,
    "axes.grid": True, "grid.color": GRADE, "grid.linewidth": 0.6, "axes.axisbelow": True,
    "axes.spines.top": False, "axes.spines.right": False, "font.size": 9,
    "axes.titlesize": 11, "axes.titleweight": "bold", "axes.titlecolor": TEXTO, "axes.titlepad": 24,
    "legend.frameon": False,
})


def le_resultados():
    with open(BENCH / "resultados.csv") as f:
        return list(csv.DictReader(f))


def mediana(linhas, campo):
    return statistics.median(float(l[campo]) for l in linhas)


def agrupa(linhas, **filtro):
    g = defaultdict(list)
    for l in linhas:
        if all(l[k] == v for k, v in filtro.items()):
            g[l["consulta"]].append(l)
    return g


CURTO = {"sem": "sem filtro", "plataforma pequena": "Kick", "plataforma grande": "YouTube",
         "k=10, plataforma pequena": "k=10, Kick"}


def rotulo(cid, filtro):
    return f"item {int(cid[1:3])} · {CURTO.get(filtro, filtro)}"


def barras(ax, categorias, series, log=True, unidade="ms"):
    """Barras agrupadas finas; series = [(nome, cor, valores)]."""
    n = len(series)
    larg = 0.8 / n
    for i, (nome, cor, vals) in enumerate(series):
        xs = [x + (i - (n - 1) / 2) * larg for x in range(len(categorias))]
        ax.bar(xs, vals, width=larg * 0.92, color=cor, label=nome, edgecolor=FUNDO, linewidth=1)
    ax.set_xticks(range(len(categorias)))
    # rótulos inclinados quando são muitos, para não se sobreporem
    if len(categorias) > 6:
        ax.set_xticklabels(categorias, fontsize=7.5, rotation=35, ha="right", rotation_mode="anchor")
    else:
        ax.set_xticklabels(categorias, fontsize=8)
    if log:
        ax.set_yscale("log")
    ax.set_ylabel(unidade + (" (escala log)" if log else ""))
    # legenda acima da área do gráfico: nunca cobre as barras altas
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=n, fontsize=8, borderaxespad=0.2)


def salva(fig, nome):
    fig.tight_layout()
    fig.savefig(SAIDA / nome, dpi=160)
    plt.close(fig)
    print("gravado", SAIDA / nome)


def com_indices(res, cache):
    """Medidas com o conjunto FINAL de índices (DEC-034): a fase "final" para
    as consultas que tocam Video/Canal e a fase "indices" para as demais (os
    índices de Inscricao e Canal(id_streamer) são os mesmos nas duas)."""
    fin = agrupa(res, fase="final", cache=cache, variante="final")
    idx = agrupa(res, fase="indices", cache=cache, variante="final")
    return {c: fin.get(c, idx[c]) for c in idx}


def g01_02(res):
    base = agrupa(res, fase="base", cache="frio", variante="final")
    idx = com_indices(res, "frio")
    ids = [c for c in base if c in idx]
    cats = [rotulo(c, base[c][0]["filtro"]) for c in ids]

    fig, ax = plt.subplots(figsize=(13, 4.6))
    barras(ax, cats, [("só PK e UNIQUE", AZUL, [mediana(base[c], "execucao_ms") for c in ids]),
                      ("com os índices de apoio finais", LARANJA, [mediana(idx[c], "execucao_ms") for c in ids])])
    ax.set_title("Tempo de execução a frio por consulta, sem e com índices de apoio (mediana de 5)", loc="left")
    salva(fig, "01_tempo_indices_frio.png")

    fig, ax = plt.subplots(figsize=(13, 4.6))
    tot = lambda ls: statistics.median(int(l["shared_read"]) + int(l["shared_hit"]) for l in ls)  # noqa: E731
    barras(ax, cats, [("só PK e UNIQUE", AZUL, [tot(base[c]) for c in ids]),
                      ("com os índices de apoio finais", LARANJA, [tot(idx[c]) for c in ids])],
           unidade="páginas de 8 kB lidas")
    ax.set_title("Páginas lidas (shared read + hit) por consulta, sem e com índices de apoio", loc="left")
    salva(fig, "02_buffers_indices.png")


def g03(res):
    final = agrupa(res, fase="base", cache="frio", variante="final")
    orig = agrupa(res, fase="reescrita", cache="frio", variante="original")
    dire = agrupa(res, fase="reescrita", cache="frio", variante="direta")
    ids = [c for c in ["i02_sem", "i02_com", "i03_sem", "i03_com"] if c in orig and c in dire and c in final]
    cats = [rotulo(c, final[c][0]["filtro"]) for c in ids]
    fig, ax = plt.subplots(figsize=(8, 4.4))
    barras(ax, cats, [("original (agrega tudo antes de filtrar)", AZUL, [mediana(orig[c], "execucao_ms") for c in ids]),
                      ("reescrita (filtra antes, 1 passada)", LARANJA, [mediana(dire[c], "execucao_ms") for c in ids]),
                      ("final: view materializada V3", AGUA, [mediana(final[c], "execucao_ms") for c in ids])])
    ax.set_title("Itens 2 e 3: efeito da reescrita e da view materializada (a frio)", loc="left")
    salva(fig, "03_reescrita.png")


def g04(res):
    final = agrupa(res, fase="base", cache="frio", variante="final")
    dire = agrupa(res, fase="reescrita", cache="frio", variante="direta")
    virt = agrupa(res, fase="reescrita", cache="frio", variante="virtual")
    ids = [c for c in ["i10_k10", "i11_k10"] if c in dire and c in virt and c in final]
    cats = [rotulo(c, final[c][0]["filtro"]) for c in ids]
    fig, ax = plt.subplots(figsize=(7, 4.4))
    barras(ax, cats, [("consulta direta nas tabelas", AZUL, [mediana(dire[c], "execucao_ms") for c in ids]),
                      ("sobre as views virtuais V1/V2", LARANJA, [mediana(virt[c], "execucao_ms") for c in ids]),
                      ("view materializada V4", AGUA, [mediana(final[c], "execucao_ms") for c in ids])])
    ax.set_title("Top-k (itens 10 e 11): direta x virtual x materializada (a frio)", loc="left")
    salva(fig, "04_views.png")


def g05(res):
    """Por índice candidato: ganho na consulta que o motivou, overhead de
    INSERT em lote e tamanho. Inclui o candidato descartado (nro_plataforma)."""
    with open(BENCH / "escrita.csv") as f:
        esc = list(csv.DictReader(f))
    base = agrupa(res, fase="base", cache="frio", variante="final")
    # (rótulo, tabela, índice como está no escrita.csv, consulta, fase com o índice)
    alvo = [("Inscricao\nid_membro", "inscricao", "id_membro", "i06_com", "indices"),
            ("Canal\nid_streamer", "canal", "id_streamer", "i03_com", "indices"),
            ("Canal\nnro_plataf.\n(descartado)", "canal", "nro_plataforma", "i12_peq", "indices"),
            ("Video\nid_canal\n+ visu_total", "video", "id_canal INCLUDE visu_total", "i01_peq", "final")]
    nomes, ganho, overhead, tamanho = [], [], [], []
    for rot, tabela, indice, cid, fase in alvo:
        # cada candidato tem a sua linha "nenhum" (sem índice extra) logo antes
        # dele no escrita.csv; Canal aparece duas vezes, então usa a anterior
        linhas = [e for e in esc if e["operacao"] == f"INSERT {tabela}"]
        for i, e in enumerate(linhas):
            if e["indice"] == indice and e["tipo"] == "btree":
                sem = next(float(x["mediana_ms"]) for x in reversed(linhas[:i]) if x["tipo"] == "nenhum")
                com = e
                break
        else:
            continue
        com_idx = agrupa(res, fase=fase, cache="frio", variante="final")
        if cid not in base or cid not in com_idx:
            continue
        nomes.append(rot)
        ganho.append(mediana(base[cid], "execucao_ms") / mediana(com_idx[cid], "execucao_ms"))
        overhead.append(100 * (float(com["mediana_ms"]) - sem) / sem)
        tamanho.append(int(com["tamanho_indice_bytes"]) / 2**20)
    fig, axs = plt.subplots(1, 3, figsize=(13, 4))
    for ax, vals, tit, un, cor in [
        (axs[0], ganho, "Ganho de leitura a frio (consulta-alvo)", "vezes mais rápido (log; 1 = sem ganho)", AZUL),
        (axs[1], overhead, "Overhead de INSERT em lote", "% de tempo a mais", LARANJA),
        (axs[2], tamanho, "Tamanho do índice (lote medido)", "MB", AGUA)]:
        ax.bar(range(len(nomes)), vals, width=0.5, color=cor, edgecolor=FUNDO)
        ax.set_xticks(range(len(nomes)))
        ax.set_xticklabels(nomes, fontsize=7.5)
        ax.set_title(tit, loc="left", fontsize=10)
        ax.set_ylabel(un)
        if ax is axs[0]:
            ax.set_yscale("log")
            ax.axhline(1, color=TEXTO2, linewidth=0.8)
        for i, v in enumerate(vals):
            ax.annotate(f"{v:.1f}", (i, v), ha="center", va="bottom", fontsize=8, color=TEXTO)
    fig.suptitle("Índices de apoio: ganho x custo de cada candidato (escalas próprias)", x=0.01, ha="left",
                 fontweight="bold", color=TEXTO)
    salva(fig, "05_ganho_overhead.png")


def g06(res):
    frio = agrupa(res, fase="base", cache="frio", variante="final")
    quente = agrupa(res, fase="base", cache="quente", variante="final")
    ids = [c for c in frio if c in quente]
    cats = [rotulo(c, frio[c][0]["filtro"]) for c in ids]
    fig, ax = plt.subplots(figsize=(13, 4.6))
    barras(ax, cats, [("a frio (restart + drop_caches)", AZUL, [mediana(frio[c], "execucao_ms") for c in ids]),
                      ("a quente (repetição)", LARANJA, [mediana(quente[c], "execucao_ms") for c in ids])])
    ax.set_title("Linha de base a frio x a quente: o cache esconde a leitura de disco", loc="left")
    salva(fig, "06_frio_quente.png")


def g07(res):
    bt = agrupa(res, fase="indices", variante="final")
    hs = agrupa(res, fase="hash", variante="final")
    # a frio as consultas pequenas variam dezenas de ms entre repetições;
    # por isso o gráfico mostra também as páginas lidas (iguais nos dois)
    ids = [c for c in ["i03_com", "i06_com"] if c in bt and c in hs]
    if not ids:
        return
    cats, sb, sh = [], [], []
    for c in ids:
        for cache in ["frio", "quente"]:
            cats.append(rotulo(c, bt[c][0]["filtro"]) + f" ({cache})")
            sb.append(mediana([l for l in bt[c] if l["cache"] == cache], "execucao_ms"))
            sh.append(mediana([l for l in hs[c] if l["cache"] == cache], "execucao_ms"))
    fig, ax = plt.subplots(figsize=(8, 4.2))
    barras(ax, cats, [("B-tree", AZUL, sb), ("hash", LARANJA, sh)])
    ax.set_title("Predicados só de igualdade: B-tree x hash", loc="left")
    salva(fig, "07_hash_btree.png")


def g08(res):
    """Item 12 a frio: cada série é uma forma de responder (DEC-035)."""
    it = [l for l in res if l["fase"] == "item12" and l["cache"] == "frio"]
    if not it:
        return
    def med(cid, var, cen):
        ls = [l for l in it if l["consulta"] == cid and l["variante"] == var and l["cenario"] == cen]
        return mediana(ls, "execucao_ms") if ls else float("nan")
    ids = ["i12_sem", "i12_peq", "i12_grd"]
    cats = ["sem filtro (k=10)", "filtro: Kick", "filtro: YouTube"]
    series = [("anterior (DEC-029)", AZUL, [med(c, "anterior", "sem_apoio") for c in ids]),
              ("final, sem índice de apoio", LARANJA, [med(c, "final", "sem_apoio") for c in ids]),
              ("final + índice de cobertura em Canal", AGUA, [med(c, "final", "final_item12") for c in ids]),
              ("final sobre V5 virtual", AMARELO, [med(c, "v5_virtual", "sem_apoio") for c in ids]),
              ("final sobre V5 materializada", MAGENTA, [med(c, "v5_mat", "sem_apoio") for c in ids])]
    fig, ax = plt.subplots(figsize=(10, 4.6))
    barras(ax, cats, series)
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=3, fontsize=8, borderaxespad=0.2)
    ax.set_title("Item 12 (desafio): formas de responder, a frio (mediana de 5)", loc="left", pad=40)
    salva(fig, "08_item12.png")


def main():
    res = le_resultados()
    g01_02(res)
    g03(res)
    g04(res)
    if (BENCH / "escrita.csv").exists():
        g05(res)
    g06(res)
    g07(res)
    g08(res)


if __name__ == "__main__":
    main()

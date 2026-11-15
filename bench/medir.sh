#!/usr/bin/env bash
# =====================================================================
# bench/medir.sh · uma medida com EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
#
# O que faz: roda UMA consulta e grava o plano em JSON. No modo "frio"
# esvazia antes os dois caches que distorcem a medida (P16, DEC-032):
#   1. shared_buffers do Postgres: some ao parar o processo (docker stop);
#   2. cache de páginas do SO: no Docker Desktop do Mac ele fica na VM
#      Linux e sobrevive ao restart do container; é limpo com
#      "echo 3 > /proc/sys/vm/drop_caches" num container privilegiado.
# A ordem é parar -> limpar -> subir, para que nada da execução anterior
# volte ao cache entre a limpeza e a medida.
#
# Uso: bench/medir.sh <banco> <arquivo.sql> <saida.json> [frio|quente]
#   <arquivo.sql>  a consulta, sem o EXPLAIN (ex.: SELECT * FROM f(1);)
#   frio (padrão)  reinicia o container e limpa o cache do SO antes
#   quente         roda direto (o chamador faz o aquecimento antes)
#
# Variáveis: CT (container, padrão stream-bench), PGUSER_BENCH (admin).
# Configuração fixa da sessão de medida (registrada na DEC-032):
#   jit = off                         (compilação JIT soma tempo variável)
#   max_parallel_workers_per_gather=0 (um processo só: tempo comparável)
# Cuidado:
#   * Precisa de Docker com permissão para --privileged. O drop_caches
#     vale para a VM inteira (não apaga dados; só esvazia o cache).
#   * O usuário autorizou reiniciar SÓ o container de aferição
#     (stream-bench), nunca o container do projeto.
#   * Usa a imagem postgres:17 (já presente) para o drop_caches, para não
#     baixar outra imagem.
# =====================================================================
set -euo pipefail

CT="${CT:-stream-bench}"
USR="${PGUSER_BENCH:-admin}"
DB="$1"; SQL="$2"; OUT="$3"; MODO="${4:-frio}"

if [ "$MODO" = "frio" ]; then
    docker stop -t 60 "$CT" >/dev/null                       # esvazia shared_buffers
    docker run --rm --privileged postgres:17 \
        sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'       # esvazia o cache da VM
    docker start "$CT" >/dev/null
    # espera o servidor aceitar conexão no banco medido
    until docker exec "$CT" pg_isready -U "$USR" -d "$DB" -q 2>/dev/null; do sleep 0.3; done
    # a primeira conexão logo após o start às vezes ainda pega o servidor
    # em recuperação; uma consulta trivial confirma que está pronto
    until docker exec "$CT" psql -U "$USR" -d "$DB" -Atqc 'SELECT 1' >/dev/null 2>&1; do sleep 0.3; done
fi

{
    echo "SET jit = off;"
    echo "SET max_parallel_workers_per_gather = 0;"
    echo "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)"
    cat "$SQL"
} | docker exec -i "$CT" psql -U "$USR" -d "$DB" -X -q -At -v ON_ERROR_STOP=1 > "$OUT"

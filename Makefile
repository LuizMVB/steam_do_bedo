# =====================================================================
# Projeto de Banco de Dados 2026/2 - Stream do Bedo
# Atalhos para subir o banco e executar os arquivos na ordem do trabalho.
#
# Ordem: ddl -> seed -> views -> functions -> triggers -> tests
#   make setup            sobe o banco e executa tudo, menos os testes
#   make tests            executa as chamadas das functions (tests.sql)
#   make setup ESCALA=0.1 carga reduzida (menos de 1 min) para teste rápido
# =====================================================================

DB_USER ?= admin
DB_NAME ?= steam-do-bedo-db
# Escala do seed: 1 = carga completa (~8,7 milhões de registros, 6 a 9 min).
ESCALA  ?= 1

# psql dentro do container; os arquivos estão montados em /workspace.
# ON_ERROR_STOP faz o psql parar (e o make falhar) no primeiro erro.
PSQL = docker compose exec -T db psql -U $(DB_USER) -d $(DB_NAME) -v ON_ERROR_STOP=1

.PHONY: help setup up ddl seed views functions triggers tests refresh psql down clean

help: ## lista os comandos
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

setup: up ddl seed views functions triggers ## sobe o banco e executa ddl, seed, views, functions e triggers
	@echo "Banco pronto. Rode \"make tests\" para chamar as functions."

up: ## sobe o container do PostgreSQL e espera ficar pronto
	docker compose up -d --wait

ddl: ## 1. recria o schema steam_do_bedo e as 20 tabelas (apaga os dados)
	$(PSQL) -f /workspace/ddl.sql

seed: ## 2. carrega os dados (exige o banco vazio, logo depois do ddl)
	$(PSQL) -v escala=$(ESCALA) -f /workspace/seed.sql

views: ## 3. cria as views virtuais e materializadas
	$(PSQL) -f /workspace/views.sql

functions: ## 4. cria as functions das 12 consultas e os índices de apoio
	$(PSQL) -f /workspace/functions.sql

triggers: ## 5. cria os triggers T1 a T11
	$(PSQL) -f /workspace/triggers.sql

tests: ## 6. chama as functions em vários cenários
	$(PSQL) -f /workspace/tests.sql

refresh: ## atualiza as views materializadas (V3 e V4)
	$(PSQL) -c "CALL steam_do_bedo.sp_refresh_views();"

psql: ## abre um psql interativo no banco
	docker compose exec db psql -U $(DB_USER) -d $(DB_NAME)

down: ## desliga o container (os dados ficam no volume)
	docker compose down

clean: ## desliga o container e apaga o volume com os dados
	docker compose down -v

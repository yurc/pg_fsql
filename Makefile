MODULE_big = pg_fsql
OBJS = src/pg_fsql.o src/render.o src/execute.o

EXTENSION = pg_fsql
DATA = pg_fsql--1.0.sql

PG_CPPFLAGS = -I$(srcdir)/src

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Assemble monolithic SQL from parts
pg_fsql--1.0.sql: $(wildcard sql/parts/*.sql)
	@echo "Assembling $@ from sql/parts/*.sql ..."
	@cat sql/parts/*.sql > $@
	@echo "-- Generated from sql/parts/ on $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $@

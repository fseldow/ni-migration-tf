# AKS network-isolated migration.
#
# This is a thin wrapper around scripts/migrate.sh, which is where all the
# logic lives. Use whichever you prefer:
#
#     make apply STAGE=1
#     ./scripts/migrate.sh apply 1
#
# Both enforce the same stage ordering. Stage 2 removes egress, and nodes that
# have not been reimaged in stage 1 lose the ability to pull images, so the
# ordering is not advisory.

SHELL := /usr/bin/env bash
DRIVER := ./scripts/migrate.sh

# Stage for plan/apply. Override on the command line: make apply STAGE=1
STAGE ?=

.DEFAULT_GOAL := help
.PHONY: help check pools bootstrap plan apply status verify \
        stage0 stage1 stage2 azapi-plan azapi-apply fmt clean

help:                ## show this help
	@$(DRIVER) help

check:               ## verify terraform, az, login, tfvars
	@$(DRIVER) check

pools:               ## list agent pools (verify your agentpool_names)
	@$(DRIVER) pools

bootstrap:           ## Step 0: generate + normalise cluster.tf from the live cluster
	@$(DRIVER) bootstrap

plan:                ## plan one stage:  make plan STAGE=0
	@$(if $(STAGE),,$(error STAGE is required, e.g. make plan STAGE=0))
	@$(DRIVER) plan $(STAGE)

apply:               ## apply one stage: make apply STAGE=1
	@$(if $(STAGE),,$(error STAGE is required, e.g. make apply STAGE=1))
	@$(DRIVER) apply $(STAGE)

stage0:              ## alias for: make apply STAGE=0
	@$(DRIVER) apply 0

stage1:              ## alias for: make apply STAGE=1
	@$(DRIVER) apply 1

stage2:              ## alias for: make apply STAGE=2
	@$(DRIVER) apply 2

status:              ## what has been applied, and live cluster state
	@$(DRIVER) status

verify:              ## post-apply checks (cluster, pools, nodes)
	@$(DRIVER) verify

azapi-plan:          ## route A: plan the single-apply azapi migration
	@$(DRIVER) azapi-plan

azapi-apply:         ## route A: apply it
	@$(DRIVER) azapi-apply

fmt:                 ## terraform fmt + validate both directories
	@$(DRIVER) fmt

clean:               ## remove .tfplan / generated.tf (state untouched)
	@$(DRIVER) clean

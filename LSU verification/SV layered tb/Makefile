# ==============================================================================
# Enterprise VCS Makefile for LSU Subsystem Verification
# ==============================================================================

RTL_SRCS  = ../../ls_unit.v \
            ../../hybrid_mem_interface.v \
            ../../Data_Memory.v \
            ../../axi_lite_dummy_slave.v

TB_SRCS   = lsu_pkg.sv \
            lsu_tb_top.sv

LOG_DIR   = logfiles
COV_DB    = $(LOG_DIR)/vcs_cov.vdb
COV_REP   = $(LOG_DIR)/vcs_coverage_report

VCS_FLAGS = -sverilog -full64 -ntb_opts uvm-1.2 -kdb -debug_access+all -timescale=1ns/1ps
COV_FLAGS = -cm line+cond+fsm+tgl+branch+assert -cm_dir $(COV_DB)
INCDIRS   = +incdir+../../

.PHONY: all compile run cov verdi dve clean

all: compile run cov

compile:
	@mkdir -p $(LOG_DIR)
	vcs $(VCS_FLAGS) $(COV_FLAGS) $(INCDIRS) -l $(LOG_DIR)/vcs_compile.log -o simv $(RTL_SRCS) $(TB_SRCS)

run:
	./simv $(COV_FLAGS) -cm_name lsu_sim_run -l $(LOG_DIR)/vcs_sim.log +vcs+lic+wait

cov:
	urg -dir $(COV_DB) -format html -report $(COV_REP) -log $(LOG_DIR)/urg.log

verdi:
	verdi -ssf $(LOG_DIR)/sim.fsdb &

dve:
	dve -full64 -covdir $(COV_DB) &

clean:
	rm -rf simv simv.daidir csrc ucli.key DVEfiles verdiLog logfiles/*.log *.vdb

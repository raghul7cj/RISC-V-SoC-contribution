#!/bin/bash
# ==============================================================================
# Full-Featured Synopsys VCS Compilation & Simulation Script
# Project : RISCFORGE 1TOPS — LSU Subsystem DV Environment
# Features: Full Code/Functional Coverage, SVA, FSDB Dumping, URG HTML Reports
# ==============================================================================

set -e

# Directories
WORK_DIR=$(pwd)
LOG_DIR="${WORK_DIR}/logfiles"
COV_DB="${LOG_DIR}/vcs_cov.vdb"
REPORT_DIR="${LOG_DIR}/vcs_coverage_report"

mkdir -p "${LOG_DIR}"

echo "================================================="
echo "  Starting VCS Compilation"
echo "================================================="

vcs -sverilog -full64 \
    -ntb_opts uvm-1.2 \
    -kdb -debug_access+all \
    -timescale=1ns/1ps \
    -cm line+cond+fsm+tgl+branch+assert \
    -cm_dir "${COV_DB}" \
    -l "${LOG_DIR}/vcs_compile.log" \
    -o simv \
    +incdir+../../ \
    ../../ls_unit.v \
    ../../hybrid_mem_interface.v \
    ../../Data_Memory.v \
    ../../axi_lite_dummy_slave.v \
    lsu_pkg.sv \
    lsu_tb_top.sv

echo "================================================="
echo "  Running VCS Simulation"
echo "================================================="

./simv -cm line+cond+fsm+tgl+branch+assert \
       -cm_dir "${COV_DB}" \
       -cm_name lsu_sim_run \
       -l "${LOG_DIR}/vcs_sim.log" \
       +vcs+lic+wait

echo "================================================="
echo "  Generating Coverage Report with URG"
echo "================================================="

urg -dir "${COV_DB}" \
    -format html \
    -report "${REPORT_DIR}" \
    -log "${LOG_DIR}/urg.log"

echo "================================================="
echo "  VCS Execution Finished Successfully!"
echo "  Simulation Log : ${LOG_DIR}/vcs_sim.log"
echo "  Coverage Report: ${REPORT_DIR}/dashboard.html"
echo "================================================="

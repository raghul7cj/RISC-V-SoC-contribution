# run_lsu_tb.ps1
# =========================================================================
# Vivado xvlog/xelab/xsim compile, simulate, and coverage for LSU Subsystem
# Run from the verif/tb_lsu/ directory
# =========================================================================

$env:PATH = "C:\Xilinx\Vivado\2022.2\bin;" + $env:PATH

$RTL = "../.."
$TB  = "."
$LOG = "logfiles"

# Create log directory
$null = New-Item -ItemType Directory -Path $LOG -Force

# Clean previous coverage artifacts
if (Test-Path "xsim.covdb") { Remove-Item -Recurse -Force "xsim.covdb" }
if (Test-Path "xsim.dir")   { Remove-Item -Recurse -Force "xsim.dir" }

Write-Host "=== Compiling RTL (Verilog) ===" -ForegroundColor Cyan

xvlog -log "$LOG/xvlog_rtl.log" `
    "$RTL/ls_unit.v" `
    "$RTL/hybrid_mem_interface.v" `
    "$RTL/Data_Memory.v" `
    "$RTL/axi_lite_dummy_slave.v"

if ($LASTEXITCODE -ne 0) { Write-Host "RTL compile FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== Compiling Testbench (SystemVerilog) ===" -ForegroundColor Cyan

xvlog --sv -log "$LOG/xvlog_tb.log" `
    "$TB/lsu_pkg.sv" `
    "$TB/lsu_tb_top.sv"

if ($LASTEXITCODE -ne 0) { Write-Host "TB compile FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== Elaborating ===" -ForegroundColor Cyan

xelab lsu_tb_top -log "$LOG/xelab.log" -debug typical --cov_db_dir "."

if ($LASTEXITCODE -ne 0) { Write-Host "Elaboration FAILED" -ForegroundColor Red; exit 1 }

# Create Tcl script for xsim batch run (write_xsim_coverage flushes coverage to disk)
@"
log_wave -r /
run -all
write_xsim_coverage
exit
"@ | Out-File -FilePath "$LOG/xsim_run.tcl" -Encoding ASCII

Write-Host "=== Running Simulation ===" -ForegroundColor Cyan

xsim lsu_tb_top -log "$LOG/xsim.log" -wdb "$LOG/sim.wdb" -cov_db_dir "." -tclbatch "$LOG/xsim_run.tcl"

# Generate coverage report — try common snapshot naming patterns
Write-Host "=== Generating Coverage Report ===" -ForegroundColor Cyan
$COV_DIR = $null
if (Test-Path "xsim.covdb") { $COV_DIR = "." }
elseif (Test-Path "$LOG/xsim.covdb") { $COV_DIR = "$LOG" }

if ($COV_DIR) {
    # Snapshot is work.lsu_tb_top (default xelab naming)
    xcrg -dir $COV_DIR -db_name work.lsu_tb_top -report_dir "$LOG/coverage_report" -report_format html
} else {
    Write-Host "Coverage data not saved (xsim may not support write_xsim_coverage in batch mode)." -ForegroundColor Yellow
    Write-Host "Try manually: xcrg -dir . -db_name lsu_tb_top -report_dir $LOG/coverage_report -report_format html" -ForegroundColor Yellow
}

Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Logs:             $LOG/" -ForegroundColor Green
Write-Host "Waves:            $LOG/sim.wdb" -ForegroundColor Green

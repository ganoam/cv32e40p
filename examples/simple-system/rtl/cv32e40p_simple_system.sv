// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * CV32E40P simple system
 *
 * This is a basic system consisting of an cv32e40p, a 1 MB sram for instruction/data
 * and a small memory mapped control module for outputting ASCII text and
 * controlling/halting the simulation from the software running on the ibex.
 *
 * It is designed to be used with verilator but should work with other
 * simulators, a small amount of work may be required to support the
 * simulator_ctrl module.
 */

module cv32e40p_simple_system (
  input IO_CLK,
  input IO_RST_N
);

  parameter bit          PULP_XPULP       = 1'b0;
  parameter bit          PULP_CLUSTER     = 1'b0;
  parameter bit          FPU              = 1'b0;
  parameter bit          PULP_ZFINX       = 1'b0;
  parameter int unsigned NUM_MHPMCOUNTERS = 10;
  parameter              SRAMInitFile     = "";

  logic clk_sys = 1'b0, rst_sys_n;

  typedef enum {
    CoreD
  } bus_host_e;

  typedef enum {
    Ram,
    SimCtrl,
    Timer
  } bus_device_e;

  localparam int NrDevices = 3;
  localparam int NrHosts = 1;

  // interrupts
  logic timer_irq;

  // host and device signals
  logic           host_req    [NrHosts];
  logic           host_gnt    [NrHosts];
  logic [31:0]    host_addr   [NrHosts];
  logic           host_we     [NrHosts];
  logic [ 3:0]    host_be     [NrHosts];
  logic [31:0]    host_wdata  [NrHosts];
  logic           host_rvalid [NrHosts];
  logic [31:0]    host_rdata  [NrHosts];
  logic           host_err    [NrHosts];

  // devices (slaves)
  logic           device_req    [NrDevices];
  logic [31:0]    device_addr   [NrDevices];
  logic           device_we     [NrDevices];
  logic [ 3:0]    device_be     [NrDevices];
  logic [31:0]    device_wdata  [NrDevices];
  logic           device_rvalid [NrDevices];
  logic [31:0]    device_rdata  [NrDevices];
  logic           device_err    [NrDevices];

  // Device address mapping
  logic [31:0] cfg_device_addr_base [NrDevices];
  logic [31:0] cfg_device_addr_mask [NrDevices];
  assign cfg_device_addr_base[Ram] = 32'h100000;
  assign cfg_device_addr_mask[Ram] = ~32'hFFFFF; // 1 MB
  assign cfg_device_addr_base[SimCtrl] = 32'h20000;
  assign cfg_device_addr_mask[SimCtrl] = ~32'h3FF; // 1 kB
  assign cfg_device_addr_base[Timer] = 32'h30000;
  assign cfg_device_addr_mask[Timer] = ~32'h3FF; // 1 kB

  // Instruction fetch signals
  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_err;

  assign instr_gnt = instr_req;
  assign instr_err = '0;

`ifdef VERILATOR
  assign clk_sys = IO_CLK;
  assign rst_sys_n = IO_RST_N;
`else
  function automatic void mhpmcounter_set(int index, int value);
    u_core.core_i.cs_registers_i.mhpmcounter_n[index] = value;
  endfunction

  function automatic longint mhpmcounter_get(int index);
    return u_core.core_i.cs_registers_i.mhpmcounter_q[index];
  endfunction

  string filename = "simple_system_pcount.csv";

  int f;

  initial begin

    rst_sys_n = 1'b0;
    #8
    // configure performance counters
    rst_sys_n = 1'b1;
    force u_core.core_i.cs_registers_i.mhpmevent_q[3] = 16'h0004; //hpm_events[2] - load hazard
    force u_core.core_i.cs_registers_i.mhpmevent_q[4] = 16'h0008; //hpm_events[2] - jump reg hazards
    force u_core.core_i.cs_registers_i.mhpmevent_q[5] = 16'h0010; //hpm_events[4] - fetch wait
    force u_core.core_i.cs_registers_i.mhpmevent_q[6] = 16'h0020; //hpm_events[5] - num of loads
    force u_core.core_i.cs_registers_i.mhpmevent_q[7] = 16'h0040; //hpm_events[6] - num of stores
    force u_core.core_i.cs_registers_i.mhpmevent_q[8] = 16'h0080; //hpm_events[7] - uncond jumps
    force u_core.core_i.cs_registers_i.mhpmevent_q[9] = 16'h0100; //hpm_events[8] - cond branches
    force u_core.core_i.cs_registers_i.mhpmevent_q[10] = 16'h0200; //hpm_events[9] - branches taken
    force u_core.core_i.cs_registers_i.mhpmevent_q[11] = 16'h0400; //hpm_events[10] - compressed instr
    force u_core.core_i.cs_registers_i.mhpmevent_q[12] = 16'h0800; //hpm_events[11] - stalls from elsw
    // enable counters
    // --- Done in SW
    // force u_core.core_i.cs_registers_i.mcountinhibit_q = 'b0;

  end
  always begin
    #1 clk_sys = 1'b0;
    #1 clk_sys = 1'b1;
  end

  string n;
  final begin
    // Read out Performance counters
    f=$fopen(filename, "w");
    $fwrite(f, "mcycle,%0d\n",mhpmcounter_get(0));
    $fwrite(f, "minstret,%0d\n",mhpmcounter_get(2));
    $fwrite(f, "LSU Busy,%0d\n",mhpmcounter_get(3));
    $fwrite(f, "IFetch wait,%0d\n",mhpmcounter_get(4));
    $fwrite(f, "Loads,%0d\n",mhpmcounter_get(5));
    $fwrite(f, "Stores,%0d\n",mhpmcounter_get(6));
    $fwrite(f, "Jumps,%0d\n",mhpmcounter_get(7));
    $fwrite(f, "Branches,%0d\n",mhpmcounter_get(8));
    $fwrite(f, "Taken Branches,%0d\n",mhpmcounter_get(9));
    $fwrite(f, "Compressed Instructions,%0d\n",mhpmcounter_get(10));
    $fwrite(f, "Stalls from elsw,%0d\n",mhpmcounter_get(11));
    $fclose(f);
  end


`endif

  // Tie-off unused error signals
  assign device_err[Ram] = 1'b0;
  assign device_err[SimCtrl] = 1'b0;

  bus #(
    .NrDevices    ( NrDevices ),
    .NrHosts      ( NrHosts   ),
    .DataWidth    ( 32        ),
    .AddressWidth ( 32        )
  ) u_bus (
    .clk_i               (clk_sys),
    .rst_ni              (rst_sys_n),

    .host_req_i          (host_req     ),
    .host_gnt_o          (host_gnt     ),
    .host_addr_i         (host_addr    ),
    .host_we_i           (host_we      ),
    .host_be_i           (host_be      ),
    .host_wdata_i        (host_wdata   ),
    .host_rvalid_o       (host_rvalid  ),
    .host_rdata_o        (host_rdata   ),
    .host_err_o          (host_err     ),

    .device_req_o        (device_req   ),
    .device_addr_o       (device_addr  ),
    .device_we_o         (device_we    ),
    .device_be_o         (device_be    ),
    .device_wdata_o      (device_wdata ),
    .device_rvalid_i     (device_rvalid),
    .device_rdata_i      (device_rdata ),
    .device_err_i        (device_err   ),

    .cfg_device_addr_base,
    .cfg_device_addr_mask
  );

  cv32e40p_wrapper #(
    .PULP_XPULP               (PULP_XPULP),
    .PULP_CLUSTER             (PULP_CLUSTER),
    .FPU                      (FPU),
    .PULP_ZFINX               (PULP_ZFINX),
    .NUM_MHPMCOUNTERS         (NUM_MHPMCOUNTERS)
  ) u_core (
    .clk_i                 (clk_sys),
    .rst_ni                (rst_sys_n),

    .pulp_clock_en_i (),
    .scan_cg_en_i('b0),

    .hart_id_i             (32'b0),
    // First instruction executed is at 0x0 + 0x80
    .boot_addr_i           (32'h00100080),

    .dm_halt_addr_i(32'h00100000),
    .dm_exception_addr_i(32'h00100000),
    .mtvec_addr_i(32'h00100001), // ??????

    .instr_req_o           (instr_req),
    .instr_gnt_i           (instr_gnt),
    .instr_rvalid_i        (instr_rvalid),
    .instr_addr_o          (instr_addr),
    .instr_rdata_i         (instr_rdata),

    .data_req_o            (host_req[CoreD]),
    .data_gnt_i            (host_gnt[CoreD]),
    .data_rvalid_i         (host_rvalid[CoreD]),
    .data_we_o             (host_we[CoreD]),
    .data_be_o             (host_be[CoreD]),
    .data_addr_o           (host_addr[CoreD]),
    .data_wdata_o          (host_wdata[CoreD]),
    .data_rdata_i          (host_rdata[CoreD]),

    .irq_i({24'h0, timer_irq, 7'h0}),
    .irq_ack_o(),
    .irq_id_o(),

    .debug_req_i           ('b0),

    .fetch_enable_i        ('b1),
    .core_sleep_o          ()
  );

  // SRAM block for instruction and data storage
  ram_2p #(
      .Depth(1024*1024/4),
      .MemInitFile(SRAMInitFile)
    ) u_ram (
      .clk_i       (clk_sys),
      .rst_ni      (rst_sys_n),

      .a_req_i     (device_req[Ram]),
      .a_we_i      (device_we[Ram]),
      .a_be_i      (device_be[Ram]),
      .a_addr_i    (device_addr[Ram]),
      .a_wdata_i   (device_wdata[Ram]),
      .a_rvalid_o  (device_rvalid[Ram]),
      .a_rdata_o   (device_rdata[Ram]),

      .b_req_i     (instr_req),
      .b_we_i      (1'b0),
      .b_be_i      (4'b0),
      .b_addr_i    (instr_addr),
      .b_wdata_i   (32'b0),
      .b_rvalid_o  (instr_rvalid),
      .b_rdata_o   (instr_rdata)
    );

  simulator_ctrl #(
    .LogName("cv32e40p_simple_system.log")
    ) u_simulator_ctrl (
      .clk_i     (clk_sys),
      .rst_ni    (rst_sys_n),

      .req_i     (device_req[SimCtrl]),
      .we_i      (device_we[SimCtrl]),
      .be_i      (device_be[SimCtrl]),
      .addr_i    (device_addr[SimCtrl]),
      .wdata_i   (device_wdata[SimCtrl]),
      .rvalid_o  (device_rvalid[SimCtrl]),
      .rdata_o   (device_rdata[SimCtrl])
    );

  timer #(
    .DataWidth    (32),
    .AddressWidth (32)
    ) u_timer (
      .clk_i          (clk_sys),
      .rst_ni         (rst_sys_n),

      .timer_req_i    (device_req[Timer]),
      .timer_we_i     (device_we[Timer]),
      .timer_be_i     (device_be[Timer]),
      .timer_addr_i   (device_addr[Timer]),
      .timer_wdata_i  (device_wdata[Timer]),
      .timer_rvalid_o (device_rvalid[Timer]),
      .timer_rdata_o  (device_rdata[Timer]),
      .timer_err_o    (device_err[Timer]),
      .timer_intr_o   (timer_irq)
    );

  export "DPI-C" function mhpmcounter_get;

  //function automatic longint mhpmcounter_get(int index);
   // return u_core.core_i.cs_registers_i.mhpmcounter_q[index];
  //endfunction

endmodule

// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module cv32e40p_clock_gate (
  input        clk_i,
  input        en_i,
  input        scan_cg_en_i,
  output logic clk_o
);

  BUFGCE u_bufgce (
    .I  (clk_i),
    .CE (en_i | scan_cg_en_i),
    .O  (clk_o)
  );

endmodule

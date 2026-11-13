`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import apb_pkg::*;

  logic pclk = 0;
  always #5 pclk = ~pclk;

  apb_if vif (pclk);

  apb_reg_slave dut (
    .pclk(pclk), .presetn(vif.presetn),
    .psel(vif.psel), .penable(vif.penable), .pwrite(vif.pwrite),
    .paddr(vif.paddr), .pwdata(vif.pwdata), .pstrb(vif.pstrb),
    .prdata(vif.prdata), .pready(vif.pready), .pslverr(vif.pslverr)
  );

  initial begin
    vif.presetn = 0;
    vif.psel = 0; vif.penable = 0; vif.pwrite = 0;
    vif.paddr = 0; vif.pwdata = 0; vif.pstrb = 0;
    repeat (5) @(posedge pclk);
    vif.presetn = 1;
  end

  initial begin
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule

interface apb_if (input logic pclk);
  logic        presetn;
  logic        psel, penable, pwrite;
  logic [7:0]  paddr;
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic [31:0] prdata;
  logic        pready, pslverr;

  clocking drv_cb @(posedge pclk);
    default input #1step output #1;
    output psel, penable, pwrite, paddr, pwdata, pstrb;
    input  prdata, pready, pslverr;
  endclocking

  clocking mon_cb @(posedge pclk);
    default input #1step;
    input psel, penable, pwrite, paddr, pwdata, pstrb, prdata, pready, pslverr;
  endclocking
endinterface

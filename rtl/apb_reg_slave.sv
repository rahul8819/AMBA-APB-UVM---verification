// APB4 register-file slave: 16 x 32-bit registers, byte strobes, PSLVERR
// Valid address: word-aligned (paddr[1:0]==0) and paddr < NUM_REGS*4
// Zero wait states (PREADY tied high). Error response is given in ACCESS phase.
module apb_reg_slave #(
  parameter int ADDR_W   = 8,
  parameter int NUM_REGS = 16
)(
  input  logic              pclk,
  input  logic              presetn,
  input  logic              psel,
  input  logic              penable,
  input  logic              pwrite,
  input  logic [ADDR_W-1:0] paddr,
  input  logic [31:0]       pwdata,
  input  logic [3:0]        pstrb,
  output logic [31:0]       prdata,
  output logic              pready,
  output logic              pslverr
);
  localparam int IDX_W = $clog2(NUM_REGS);

  logic [31:0]      regs [NUM_REGS];
  logic [IDX_W-1:0] idx;
  logic             addr_ok;

  assign idx     = paddr[IDX_W+1:2];
  assign addr_ok = (paddr[1:0] == 2'b00) && (paddr[ADDR_W-1:2] < NUM_REGS);

  assign pready  = 1'b1;
  assign pslverr = psel && penable && !addr_ok;

  // Write: performed in ACCESS phase, only for valid addresses, per byte lane
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      for (int i = 0; i < NUM_REGS; i++) regs[i] <= '0;
    end else if (psel && penable && pwrite && addr_ok) begin
      for (int b = 0; b < 4; b++)
        if (pstrb[b]) regs[idx][8*b +: 8] <= pwdata[8*b +: 8];
    end
  end

  // Read: returns 0 on invalid address
  always_comb begin
    prdata = '0;
    if (psel && !pwrite && addr_ok) prdata = regs[idx];
  end
endmodule

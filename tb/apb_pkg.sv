package apb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------------------------------------------------------------
  // Transaction
  // ---------------------------------------------------------------
  class apb_item extends uvm_sequence_item;
    rand bit        write;
    rand bit [7:0]  addr;
    rand bit [31:0] data;
    rand bit [3:0]  strb;
    rand bit        want_valid;
         bit [31:0] rdata;
         bit        slverr;
         bit        is_reset;

    `uvm_object_utils(apb_item)

    // ~80% valid addresses, ~20% out-of-range or misaligned
    constraint c_kind { want_valid dist {1 := 8, 0 := 2}; }
    constraint c_addr {
      if (want_valid) { addr <= 8'h3C; addr[1:0] == 2'b00; }
      else            { !(addr <= 8'h3C && addr[1:0] == 2'b00); }
    }
    constraint c_strb { strb dist {4'hF := 4, [4'h0:4'hE] :/ 6}; }

    function new(string name = "apb_item");
      super.new(name);
    endfunction

    function bit is_valid_addr();
      return (addr <= 8'h3C) && (addr[1:0] == 2'b00);
    endfunction

    function string convert2string();
      if (is_reset) return "RESET";
      return $sformatf("%s addr=0x%02h wdata=0x%08h strb=%04b rdata=0x%08h slverr=%0b",
                       write ? "WR" : "RD", addr, data, strb, rdata, slverr);
    endfunction
  endclass

  // ---------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------
  class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)
    virtual apb_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
      vif.drv_cb.psel    <= 0;
      vif.drv_cb.penable <= 0;
      forever begin
        seq_item_port.get_next_item(req);
        drive(req);
        seq_item_port.item_done();
      end
    endtask

    task drive(apb_item t);
      while (vif.presetn !== 1'b1) @(vif.drv_cb);
      // SETUP phase
      @(vif.drv_cb);
      vif.drv_cb.psel    <= 1;
      vif.drv_cb.penable <= 0;
      vif.drv_cb.pwrite  <= t.write;
      vif.drv_cb.paddr   <= t.addr;
      vif.drv_cb.pwdata  <= t.write ? t.data : '0;
      vif.drv_cb.pstrb   <= t.write ? t.strb : '0;
      // ACCESS phase
      @(vif.drv_cb);
      vif.drv_cb.penable <= 1;
      @(vif.drv_cb);
      while (!vif.drv_cb.pready) @(vif.drv_cb);
      t.rdata  = vif.drv_cb.prdata;
      t.slverr = vif.drv_cb.pslverr;
      // back to IDLE
      vif.drv_cb.psel    <= 0;
      vif.drv_cb.penable <= 0;
    endtask
  endclass

  // ---------------------------------------------------------------
  // Monitor
  // ---------------------------------------------------------------
  class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)
    virtual apb_if vif;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
      fork
        watch_reset();
        watch_transfers();
      join
    endtask

    task watch_reset();
      forever begin
        @(negedge vif.presetn);
        begin
          apb_item r = apb_item::type_id::create("rst");
          r.is_reset = 1;
          `uvm_info("MON", "reset asserted", UVM_MEDIUM)
          ap.write(r);
        end
      end
    endtask

    task watch_transfers();
      forever begin
        @(vif.mon_cb);
        if (vif.presetn && vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
          apb_item t = apb_item::type_id::create("t");
          t.write  = vif.mon_cb.pwrite;
          t.addr   = vif.mon_cb.paddr;
          t.data   = vif.mon_cb.pwdata;
          t.strb   = vif.mon_cb.pstrb;
          t.rdata  = vif.mon_cb.prdata;
          t.slverr = vif.mon_cb.pslverr;
          `uvm_info("MON", t.convert2string(), UVM_HIGH)
          ap.write(t);
        end
      end
    endtask
  endclass

  // ---------------------------------------------------------------
  // Agent
  // ---------------------------------------------------------------
  typedef uvm_sequencer #(apb_item) apb_sequencer;

  class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)
    apb_sequencer sqr;
    apb_driver    drv;
    apb_monitor   mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sqr = apb_sequencer::type_id::create("sqr", this);
      drv = apb_driver::type_id::create("drv", this);
      mon = apb_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ---------------------------------------------------------------
  // Scoreboard: reference model, error on invalid address, clears on reset
  // ---------------------------------------------------------------
  class apb_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(apb_scoreboard)
    uvm_analysis_imp #(apb_item, apb_scoreboard) imp;

    bit [31:0] model [16];
    int unsigned n_checks, n_errors;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      imp = new("imp", this);
      foreach (model[i]) model[i] = 0;
    endfunction

    function void write(apb_item t);
      bit        valid;
      bit [31:0] exp_rdata;

      if (t.is_reset) begin
        foreach (model[i]) model[i] = 0;
        return;
      end

      valid = t.is_valid_addr();
      n_checks++;

      if (t.slverr !== !valid) begin
        n_errors++;
        `uvm_error("SCB", $sformatf("PSLVERR mismatch exp=%0b got=%0b : %s", !valid, t.slverr, t.convert2string()))
      end

      if (t.write) begin
        if (valid)
          for (int b = 0; b < 4; b++)
            if (t.strb[b]) model[t.addr[5:2]][8*b +: 8] = t.data[8*b +: 8];
      end else begin
        exp_rdata = valid ? model[t.addr[5:2]] : 32'h0;
        if (t.rdata !== exp_rdata) begin
          n_errors++;
          `uvm_error("SCB", $sformatf("RDATA mismatch exp=0x%08h got=0x%08h : %s", exp_rdata, t.rdata, t.convert2string()))
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", $sformatf("checks=%0d errors=%0d  --> %s", n_checks, n_errors,
                (n_errors == 0 && n_checks > 0) ? "PASS" : "FAIL"), UVM_NONE)
    endfunction
  endclass

  // ---------------------------------------------------------------
  // Functional coverage
  // ---------------------------------------------------------------
  class apb_coverage extends uvm_subscriber #(apb_item);
    `uvm_component_utils(apb_coverage)
    apb_item t;

    covergroup cg;
      cp_dir  : coverpoint t.write { bins read = {0}; bins write = {1}; }
      cp_addr : coverpoint t.addr  {
        bins low     = {[8'h00:8'h1C]};
        bins high    = {[8'h20:8'h3C]};
        bins out_rng = {[8'h40:8'hFF]};
      }
      cp_align: coverpoint t.addr[1:0] { bins aligned = {0}; bins misaligned = {[1:3]}; }
      cp_strb : coverpoint t.strb iff (t.write) {
        bins single[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
        bins full     = {4'hF};
        bins none     = {4'h0};
        bins other    = default;
      }
      cp_err  : coverpoint t.slverr { bins ok = {0}; bins err = {1}; }
      x_dir_err  : cross cp_dir, cp_err;
      x_dir_addr : cross cp_dir, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction

    function void write(apb_item t);
      if (t.is_reset) return;
      this.t = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("functional coverage = %0.2f%%", cg.get_inst_coverage()), UVM_NONE)
    endfunction
  endclass

  // ---------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------
  class apb_env extends uvm_env;
    `uvm_component_utils(apb_env)
    apb_agent      agt;
    apb_scoreboard scb;
    apb_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agt = apb_agent::type_id::create("agt", this);
      scb = apb_scoreboard::type_id::create("scb", this);
      cov = apb_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agt.mon.ap.connect(scb.imp);
      agt.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  // ---------------------------------------------------------------
  // Sequences
  // ---------------------------------------------------------------
  class apb_base_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_base_seq)
    function new(string name = "apb_base_seq");
      super.new(name);
    endfunction

    task xfer(bit w, bit [7:0] a, bit [31:0] d = 0, bit [3:0] s = 4'hF);
      apb_item t = apb_item::type_id::create("t");
      start_item(t);
      t.write = w; t.addr = a; t.data = d; t.strb = s;
      finish_item(t);
    endtask
  endclass

  // Directed: write all regs, read all back
  class apb_wr_rd_seq extends apb_base_seq;
    `uvm_object_utils(apb_wr_rd_seq)
    function new(string name = "apb_wr_rd_seq"); super.new(name); endfunction
    task body();
      for (int i = 0; i < 16; i++) xfer(1, i*4, 32'hA5A50000 + i);
      for (int i = 0; i < 16; i++) xfer(0, i*4);
    endtask
  endclass

  // Directed: byte strobes
  class apb_strobe_seq extends apb_base_seq;
    `uvm_object_utils(apb_strobe_seq)
    function new(string name = "apb_strobe_seq"); super.new(name); endfunction
    task body();
      xfer(1, 8'h00, 32'h0000_0000, 4'hF);
      for (int b = 0; b < 4; b++) begin
        xfer(1, 8'h00, 32'hFFFF_FFFF, 4'b0001 << b);
        xfer(0, 8'h00);
      end
      xfer(1, 8'h04, 32'h1122_3344, 4'hF);
      xfer(1, 8'h04, 32'hAABB_CCDD, 4'b0000);  // no lanes enabled: must not change
      xfer(0, 8'h04);
      xfer(1, 8'h04, 32'hAABB_CCDD, 4'b0110);
      xfer(0, 8'h04);
    endtask
  endclass

  // Directed: invalid / out-of-range / misaligned accesses
  class apb_error_seq extends apb_base_seq;
    `uvm_object_utils(apb_error_seq)
    function new(string name = "apb_error_seq"); super.new(name); endfunction
    task body();
      xfer(1, 8'h3C, 32'hCAFE_F00D);           // last valid reg
      xfer(1, 8'h40, 32'hDEAD_BEEF);           // first out-of-range
      xfer(1, 8'hFC, 32'hDEAD_BEEF);
      xfer(0, 8'h40);
      xfer(0, 8'h80);
      xfer(1, 8'h01, 32'h1234_5678);           // misaligned
      xfer(0, 8'h3E);
      xfer(0, 8'h3C);                          // must still hold CAFEF00D
      xfer(0, 8'h00);                          // not corrupted by bad writes
    endtask
  endclass

  class apb_read_all_seq extends apb_base_seq;
    `uvm_object_utils(apb_read_all_seq)
    function new(string name = "apb_read_all_seq"); super.new(name); endfunction
    task body();
      for (int i = 0; i < 16; i++) xfer(0, i*4);
    endtask
  endclass

  // Constrained-random
  class apb_random_seq extends apb_base_seq;
    `uvm_object_utils(apb_random_seq)
    int unsigned n = 500;
    function new(string name = "apb_random_seq"); super.new(name); endfunction
    task body();
      repeat (n) begin
        apb_item t = apb_item::type_id::create("t");
        start_item(t);
        if (!t.randomize()) `uvm_fatal("SEQ", "randomize failed")
        finish_item(t);
      end
    endtask
  endclass

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  class apb_base_test extends uvm_test;
    `uvm_component_utils(apb_base_test)
    apb_env env;
    virtual apb_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = apb_env::type_id::create("env", this);
      if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
        `uvm_fatal("TEST", "virtual interface not set")
    endfunction

    task wait_reset_done();
      wait (vif.presetn === 1'b1);
      repeat (2) @(posedge vif.pclk);
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      wait_reset_done();
      run_test_body();
      #100ns;
      phase.drop_objection(this);
    endtask

    virtual task run_test_body(); endtask
  endclass

  class apb_directed_test extends apb_base_test;
    `uvm_component_utils(apb_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_test_body();
      apb_wr_rd_seq   s1 = apb_wr_rd_seq::type_id::create("s1");
      apb_strobe_seq  s2 = apb_strobe_seq::type_id::create("s2");
      apb_error_seq   s3 = apb_error_seq::type_id::create("s3");
      s1.start(env.agt.sqr);
      s2.start(env.agt.sqr);
      s3.start(env.agt.sqr);
    endtask
  endclass

  class apb_random_test extends apb_base_test;
    `uvm_component_utils(apb_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_test_body();
      apb_random_seq s = apb_random_seq::type_id::create("s");
      s.n = 1000;
      s.start(env.agt.sqr);
    endtask
  endclass

  // Write data, pulse reset mid-test, confirm all registers read back 0
  class apb_reset_test extends apb_base_test;
    `uvm_component_utils(apb_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_test_body();
      apb_wr_rd_seq    s1 = apb_wr_rd_seq::type_id::create("s1");
      apb_read_all_seq s2 = apb_read_all_seq::type_id::create("s2");
      s1.start(env.agt.sqr);
      @(posedge vif.pclk);
      vif.presetn <= 1'b0;
      repeat (3) @(posedge vif.pclk);
      vif.presetn <= 1'b1;
      repeat (2) @(posedge vif.pclk);
      s2.start(env.agt.sqr);
    endtask
  endclass
endpackage

# AMBA APB4 Register Slave: Design and UVM Verification

An APB4 register-file slave written in SystemVerilog and verified with a UVM environment
(driver, monitor, scoreboard with reference model, functional coverage, directed and
constrained-random tests). Built and simulated in **Xilinx Vivado (xsim)**.

![status](https://img.shields.io/badge/simulation-passing-brightgreen)
![tool](https://img.shields.io/badge/tool-Vivado%20xsim-blue)
![lang](https://img.shields.io/badge/SystemVerilog-UVM-orange)

---

## 1. What this project is

APB (Advanced Peripheral Bus) is the simple AMBA bus used to reach slow peripherals and
configuration registers. This project has two halves:

1. **DUT:** an APB4 slave with 16 x 32-bit registers.
2. **Testbench:** a UVM environment that drives the bus, predicts what should happen, and
   checks every transfer.

## 2. DUT behaviour

| Feature | Behaviour |
|---|---|
| Registers | 16 x 32-bit, word-aligned, addresses `0x00` to `0x3C` |
| Byte strobes | `PSTRB[n]` enables writing byte lane `n`; `PSTRB = 0000` changes nothing |
| Error response | `PSLVERR = 1` in the ACCESS phase for an out-of-range or misaligned address |
| On error | A write is ignored; a read returns `0` |
| Wait states | None (`PREADY` tied high) |
| Reset | Asynchronous, active-low; clears all registers |

**APB transfer timing used by the driver and DUT**

```
          SETUP        ACCESS
PCLK    _|‾|_|‾|_|‾|_|‾|_
PSEL    ____|‾‾‾‾‾‾‾‾‾‾|___
PENABLE _________|‾‾‾‾‾|___
PADDR   ----< valid >-----
PREADY  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾   (always 1: zero wait states)
```
The DUT writes registers and drives `PSLVERR` in the ACCESS phase (`PSEL && PENABLE`).

## 3. Testbench architecture

```
                    +-------------------- apb_env ---------------------+
  tests/sequences   |  +------------- apb_agent -------------+         |
  ----------------> |  | sequencer -> driver --(apb_if)--+   |         |
                    |  |                monitor <--(apb_if)-+|         |
                    |  +-----------------|-------------------+         |
                    |                    | analysis port               |
                    |         +----------+-----------+                 |
                    |         v                      v                 |
                    |   scoreboard            functional coverage      |
                    |  (reference model)           (covergroup)        |
                    +--------------------------------------------------+
                                      DUT: apb_reg_slave
```

| Component | Role |
|---|---|
| `apb_item` | Transaction: write/read, address, data, strobe. Constraints bias toward ~80% valid and ~20% invalid addresses |
| `apb_driver` | Converts items into APB SETUP and ACCESS phases using a clocking block |
| `apb_monitor` | Passively samples completed transfers and reset events; publishes them on an analysis port |
| `apb_scoreboard` | Reference model of the 16 registers (byte strobes, errors, reset); checks `PRDATA` and `PSLVERR` on every transfer |
| `apb_coverage` | Covergroup: direction, address region, alignment, strobe patterns, error flag, and crosses |

## 4. Test plan

| Test | What it checks |
|---|---|
| `apb_directed_test` | Write and read back all 16 registers; each single byte strobe, full strobe and zero strobe; out-of-range and misaligned accesses; valid registers not corrupted by bad writes |
| `apb_random_test` | 1000 constrained-random transfers mixing valid and invalid accesses |
| `apb_reset_test` | Writes data, applies reset mid-test, confirms every register reads `0` afterwards |

## 5. Results

Run in Vivado xsim. All three tests report:

| Test | Checks | Errors | Result | Functional coverage |
|---|---|---|---|---|
| `apb_directed_test` | `<N>` | 0 | PASS | `<xx.xx>`% |
| `apb_random_test` | `<N>` | 0 | PASS | `<xx.xx>`% |
| `apb_reset_test` | `<N>` | 0 | PASS | `<xx.xx>`% |

Screenshots in [`docs/`](docs/): a write/read waveform, a `PSLVERR` waveform, and the PASS log.

### Bug-injection check
To confirm the testbench can actually fail, I temporarily broke the DUT and confirmed
the scoreboard caught it:

| Injected bug | Result |
|---|---|
| Ignore `PSTRB` (write all bytes always) | `RDATA mismatch` errors, test FAIL |
| Never raise `PSLVERR` | `PSLVERR mismatch` errors, test FAIL |

## 6. How to run (Vivado)

1. Create an RTL project (no sources). Add `rtl/apb_reg_slave.sv` as a design source.
2. Add `tb/apb_if.sv`, `tb/apb_pkg.sv`, `tb/tb_top.sv` as simulation sources. Set `tb_top` as the top.
3. **Settings → Simulation:**
   - `xsim.compile.xvlog.more_options` = `-L uvm`
   - `xsim.elaborate.xelab.more_options` = `-L uvm`
   - `xsim.simulate.runtime` = `all`
   - `xsim.simulate.xsim.more_options` = `-testplusarg UVM_TESTNAME=apb_directed_test`
4. **Run Simulation → Run Behavioral Simulation.**
5. Look for `checks=N errors=0 --> PASS` and the coverage line in the Tcl console.
6. To run another test, change `UVM_TESTNAME` to `apb_random_test` or `apb_reset_test`.

## 7. Repository layout

```
rtl/   apb_reg_slave.sv                       design
tb/    apb_if.sv  apb_pkg.sv  tb_top.sv       interface, UVM package, top
docs/  waveforms and logs
```

## 8. Design decisions and limitations

- **Zero wait states.** `PREADY` is tied high to keep the design simple. The driver already
  waits on `PREADY`, so wait-state support would only need a change in the DUT.
- **Error in the ACCESS phase.** `PSLVERR` is only valid when `PSEL && PENABLE`, as in the APB4 spec.
- **Reset in the scoreboard.** The monitor publishes a reset event so the reference model
  clears in step with the DUT.
- **Possible extensions:** wait states, `PPROT`, SVA assertions bound to the bus, a register
  abstraction layer (RAL), and an AXI-to-APB bridge as a follow-on project.

## 9. Skills demonstrated

SystemVerilog RTL design, APB4 protocol, UVM (sequence items, sequences, driver, monitor,
agent, scoreboard, subscriber, env, tests), constrained-random stimulus, functional
coverage, reference-model checking, Vivado xsim flow.

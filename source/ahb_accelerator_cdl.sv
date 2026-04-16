`timescale 1ns / 10ps

module ahb_accelerator_cdl (
    input  logic clk, n_rst, hsel, hwrite,
    input  logic [1:0] htrans, hsize, 
    input  logic [9:0] haddr,
    input  logic [63:0] hwdata, 
    output logic hready, hresp,
    output logic [63:0] hrdata
);

    logic busy, data_ready, start_inference, load_weights, write_input, write_weight, read_result, 
          select, sram_wen, sram_ren, load, vec_done, inf_err, nan_err;
    logic [1:0] buf_select, sram_state;
    logic [2:0] weight_count, activation_mode;
    logic [6:0] input_count, output_count;
    logic [9:0] addr;
    logic [63:0] ahb_wdata, ahb_rdata, sram_wdata, sram_rdata, inputs, outputs, activations, bias;

    ahb_subordinate_cdl ahb_sub(.*);
    activation_cdl activation(.*);
    bias_adder_cdl bias_adder(.*);
    controller_cdl controller(.*);
    systolic_array_cdl sys_array(.*);
    sram1024x32_wrapper sram(.*);

endmodule


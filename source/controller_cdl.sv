`timescale 1ns / 10ps

module controller_cdl (
    input logic clk, n_rst,
    
    input logic start_inference, load_weights, write_input, write_weight, read_result,
    input logic [63:0] ahb_wdata,
    output logic busy, data_ready, 
    output logic [6:0] input_count, output_count, 
    output logic [2:0] weight_count,
    output logic [63:0] ahb_rdata,

    output logic [63:0] inputs,
    output logic load,

    input logic [1:0] sram_state,
    input logic [63:0] sram_rdata,
    output logic sram_wen, sram_ren,
    output logic [1:0] select, buf_select, out_select, 
    output logic [9:0] addr, out_addr,
    output logic [63:0] sram_wdata
);
    /*
    address map

    10'd0, 10'd1: weights, across four banks

    10'd2 - 10'd33: inputs, across four banks

    10'd0 - 10'd31: outputs, four output banks
    */

    localparam sys_cycles = 19; //the time used for counter to know when the first input given to sys. is finished compute

    typedef enum logic[4:0] { 
        IDLE,
        WEIGHT_BUSY, WEIGHT_ACCESS, WEIGHT_INCR,
        INPUT_BUSY, INPUT_ACCESS, INPUT_INCR,
        LOADW_BUSY, LOADW_ACCESS, LOADW_INCR,        
        RESULT_BUSY, RESULT_ACCESS, RESULT_INCR,
        FETCH_INPUT, PIPE0,
        DRAIN0, DRAIN1, DRAIN2, DRAIN3
    } state_t;

    state_t state, state_n;

    logic [6:0] input_ptr, output_ptr;
    logic [2:0] weight_ptr;

    logic input_count_en, input_ptr_en, output_count_en, output_ptr_en, weight_count_en, weight_ptr_en;

    always_ff @(posedge clk or negedge n_rst) begin : FSM_RTL
        if (!n_rst) begin
            state <= IDLE;
        end else begin
            state <= state_n;
        end
    end

    logic run_input, run_output; //used in pipeline stages to determine whether select = 01 or 11
    logic input_ptr_clear, output_count_clear;

    flex_counter #(.SIZE(7)) f0 (.clk(clk), .n_rst(n_rst), .clear(),
                    .count_enable(input_count_en), .rollover_val(7'd127), .count_out(input_count), .rollover_flag());
    flex_counter #(.SIZE(7)) f1 (.clk(clk), .n_rst(n_rst), .clear(input_ptr_clear),
                    .count_enable(input_ptr_en), .rollover_val(7'd127), .count_out(input_ptr), .rollover_flag());
    flex_counter #(.SIZE(7)) f2 (.clk(clk), .n_rst(n_rst), .clear(output_count_clear),
                    .count_enable(output_count_en), .rollover_val(7'd127), .count_out(output_count), .rollover_flag());
    flex_counter #(.SIZE(7)) f3 (.clk(clk), .n_rst(n_rst), .clear(),
                    .count_enable(output_ptr_en), .rollover_val(7'd127), .count_out(output_ptr), .rollover_flag());
    flex_counter #(.SIZE(3)) f4 (.clk(clk), .n_rst(n_rst), .clear(),
                    .count_enable(weight_count_en), .rollover_val(3'd7), .count_out(weight_count), .rollover_flag());
    flex_counter #(.SIZE(3)) f5 (.clk(clk), .n_rst(n_rst), .clear(),
                    .count_enable(weight_ptr_en), .rollover_val(3'd7), .count_out(weight_ptr), .rollover_flag());

    //cycler for inference pipeline
    logic cycler_clear, cycler_en;
    logic [7:0] cycle_count; 
    flex_counter #(.SIZE(8)) cycler (.clk(clk), .n_rst(n_rst), .clear(cycler_clear),
                    .count_enable(cycler_en), .rollover_val(8'(input_count) + 8'(sys_cycles)), 
                    .count_out(cycle_count), .rollover_flag());

    always_comb begin : NEXTSATE
        state_n = state;
        case (state)
            IDLE : begin
                if (write_weight) state_n = WEIGHT_BUSY;
                if (write_input) state_n = INPUT_BUSY;
                if (load_weights) state_n = LOADW_BUSY;
                if (start_inference) state_n = FETCH_INPUT;     
                if (read_result) state_n = RESULT_BUSY;           
            end

            WEIGHT_BUSY: if (sram_state == 2'b10) state_n = WEIGHT_ACCESS;
            WEIGHT_ACCESS: state_n = WEIGHT_INCR;
            WEIGHT_INCR: state_n = IDLE;

            INPUT_BUSY: if (sram_state == 2'b10) state_n = INPUT_ACCESS;
            INPUT_ACCESS: state_n = INPUT_INCR;
            INPUT_INCR: state_n = IDLE;

            LOADW_BUSY: if (sram_state == 2'b10) state_n = LOADW_ACCESS;
            LOADW_ACCESS: state_n = LOADW_INCR;
            LOADW_INCR: state_n = IDLE;     

            RESULT_BUSY: if (sram_state == 2'b10) state_n =  RESULT_ACCESS;
            RESULT_ACCESS: state_n = RESULT_INCR;
            RESULT_INCR: state_n = IDLE;    

            FETCH_INPUT: if (sram_state == 2'b10) state_n = PIPE0;

            PIPE0: begin
            if (cycle_count < (8'(input_count) + 8'(sys_cycles))) 
                state_n = PIPE0;
            else state_n = DRAIN0;
            end 

            DRAIN0: state_n = DRAIN1;
            DRAIN1: state_n = DRAIN2;
            DRAIN2: state_n = DRAIN3;
            DRAIN3: state_n = IDLE; //infernce complete here         
        endcase
    end

    always_comb begin : DEFAULT
        busy = 1;
        data_ready = 0;
        ahb_rdata = 64'hBAD1BAD1;
        inputs = 64'hBAD2BAD2;
        load = 0;

        sram_wen = 0; sram_ren = 0; select = 2'b0; buf_select = 2'b0; out_select = 2'b0; 
        addr = '1; out_addr = '1; sram_wdata = 64'hBAD3BAD3;

        input_count_en =0; input_ptr_en =0; output_count_en =0;
        output_ptr_en=0; weight_count_en=0; weight_ptr_en=0;

        run_input = 0; run_output = 0;
        cycler_en = 0;

        input_ptr_clear = 0;
        output_count_clear = 0;
        cycler_clear = 0;

        case (state)
            IDLE : busy = 0;
            WEIGHT_BUSY,WEIGHT_ACCESS,WEIGHT_INCR : begin
                sram_wdata = ahb_wdata;
                addr = 10'd0 + 10'(weight_count >> 2);
                buf_select = weight_count[1:0];
                select = 2'b01;

                weight_count_en = (state == WEIGHT_INCR);
                sram_wen = (state != WEIGHT_INCR);
            end 

            INPUT_BUSY,INPUT_ACCESS,INPUT_INCR : begin
                sram_wdata = ahb_wdata;
                addr = 10'd2 + 10'(input_count >> 2);
                buf_select = input_count[1:0];
                select = 2'b01;

                input_count_en = (state == INPUT_INCR);
                sram_wen = (state != INPUT_INCR);
            end 

            LOADW_BUSY,LOADW_ACCESS,LOADW_INCR : begin
                inputs = sram_rdata;
                addr = 10'd0 + 10'(weight_ptr >> 2);
                buf_select = weight_ptr[1:0];
                select = 2'b01;

                weight_ptr_en = (state == LOADW_INCR);
                sram_ren = (state != LOADW_INCR);
                load = (state != LOADW_BUSY);
            end    

            RESULT_BUSY,RESULT_BUSY,RESULT_INCR : begin
                ahb_rdata = sram_rdata;
                addr = 10'd0 + 10'(output_ptr >> 2); //use normal address bus even for read result, data buffer take care of this
                buf_select = output_ptr[1:0];
                select = 2'b10;

                output_ptr_en = (state == RESULT_INCR);
                sram_ren = (state != RESULT_INCR);
            end    

            FETCH_INPUT : begin
                inputs = sram_rdata;
                addr = 10'd2 + 10'(input_ptr >> 2);
                buf_select = input_ptr[1:0];
                select = 2'b01;
                sram_ren = 1'b1;

                //clear counters used in inference
                cycler_clear = 1; 
                output_count_clear = 1;
                input_ptr_clear = 1;
            end 

            DRAIN3 : data_ready = 1;  
 
            PIPE0 : begin
                //counter for piplining:
                //cycle count start when we first reach pipe0, stays high while in pipeline stage
                //when this counter reach systolic_cyclces, run_output goes high
                //when this counter exceed input count AND systolic cycles, means all inputs loaded in, run_input hit low
                //sram_ren depend on input_ptr <= input_count  
                //sram_wen = run_output
                //select = {run_output, run_input}
                //when this counter hit systolic_cycles + input_count, this mean outputs are finished writing in, run_output goes low, we enter drain states
                cycler_en = 1;
                run_output = (cycle_count >= sys_cycles) && (cycle_count < (8'(sys_cycles) + 8'(input_count))); 
                run_input = (cycle_count <= input_count);

                if (input_ptr <= input_count) begin
                    input_ptr_en = 1; sram_ren = 1; inputs = sram_rdata;
                end

                if (run_output) begin 
                    sram_wen = 1; output_count_en = 1; 
                end

                select = {run_input, run_output};
                addr = 10'd2 + 10'(input_ptr >> 2);
                buf_select = input_ptr[1:0];
                out_addr = 10'd0 + 10'(output_count >> 2);
                out_select = output_count[1:0];
            end   
        endcase
    end
endmodule

module flex_counter #(
    parameter SIZE = 8
) (
    input logic clk, n_rst, clear, count_enable,
    input logic [SIZE-1:0] rollover_val,
    output logic [SIZE-1:0] count_out,
    output logic rollover_flag
);
    logic [SIZE-1:0] count;
    logic rollover_flag_n;

    always_ff @(posedge clk or negedge n_rst) begin : dddddd
        if (!n_rst) begin
            count_out <= '0;
            rollover_flag <= '0;
        end
        else begin
            count_out <= count;

            rollover_flag <= rollover_flag_n; //rollover flag ff
        end
    end

    always_comb begin : THING
        count = '0;
        if (clear) count = '0;
        else begin
            // else begin
                if (count_enable) begin 
                    if (count_out >= rollover_val) begin
                        count = 0;
                    end else 
                    count = count_out + 1;
                end
                else begin 
                    count = count_out;
                end
            // end
        end
    end
    assign rollover_flag_n = (count >= rollover_val)? 1'b1 : 1'b0;
endmodule


`timescale 1ns / 10ps

module ahb_subordinate_cdl (
    input  logic clk, n_rst, hwrite, hsel, 
    input  logic busy, data_ready, 
    input  logic input_count, weight_count, output_count,
    input  logic nan_err, inf_err,
    input  logic inference_complete, load_complete,
    input  logic [1:0] hsize, htrans
    input  logic [9:0] haddr,
    input  logic [63:0] hwdata, ahb_rdata
    output logic hready, hresp, start_inference, load_weights, read_result,
    output logic write_input, write_weight,
    output logic [2:0] activation_mode
    output logic [63:0] hrdata, bias, ahb_wdata, 
);

    typedef enum logic [1:0] {
        OKAY, ERR_1, ERR_2
    } err_state_e;

    typedef enum logic [2:0] {
        IDLE, STALL_1, STALL_2, STALL_3, STALL_4
    } output_state_e;

    logic prev_hwrite, prev_valid, trans_err, next_trans_err, hready_err, hready_out, read_output;
    logic [1:0] prev_hsize, valid;
    logic [7:0] control, next_control, activation_ctrl, next_activation_ctrl,
    logic [9:0] prev_haddr;
    logic [15:0] error, next_error;
    logic [63:0] next_bias, next_hrdata;
    err_state_e err_state, next_err_state;
    output_state_e output_state, next_output_state;

    assign valid = hsel && htrans == 2;

    // prev_trans
    always_ff @(posedge clk, negedge rst) begin : prev_trans_reg
        if (~n_rst) begin
            prev_hsize <= 0;
            prev_haddr <= 0;
            prev_hwrite <= 0;
            prev_valid <= 0;
        end
        else begin
            prev_hsize <= hsize;
            prev_haddr <= haddr;
            prev_hwrite <= hwrite;
            prev_valid <= valid;
        end
    end

    // ahb_wdata
    always_comb begin : ahb_wdata_logic
        if (prev_valid && prev_hwrite && (prev_haddr[9:4] == 0)) begin
            case (prev_hsize) 
                0: bytes = 1 << prev_haddr[2:0];
                1: bytes = 3 << prev_haddr[2:0];
                2: bytes = 8'h0F << prev_haddr[2:0];
                3: bytes = 8'hFF;
                default: bytes = 0;
            endcase

            ahb_wdata = bytes[0] ? hwdata[7:0] : 8'b0;
            ahb_wdata = bytes[1] ? hwdata[15:8] : 8'b0;
            ahb_wdata = bytes[2] ? hwdata[23:16] : 8'b0;
            ahb_wdata = bytes[3] ? hwdata[31:24] : 8'b0;
            ahb_wdata = bytes[4] ? hwdata[39:32] : 8'b0;
            ahb_wdata = bytes[5] ? hwdata[47:40] : 8'b0;
            ahb_wdata = bytes[6] ? hwdata[55:48] : 8'b0;
            ahb_wdata = bytes[7] ? hwdata[63:56] : 8'b0;
        end else 
            ahb_wdata = 0;
    end

    /*
    =======================
    ERRORS
    =======================
    */

    // buf_occ_err
    assign buf_occ_err = 
        (input_count == 128 && haddr[9:3] == 1 && valid && hwrite) ||
        (weight_count == 128 && haddr[9:3] == 0 && valid && hwrite) ||
        (output_count == 0 && haddr[9:3] == 3 && valid && ~hwrite);

    // busy_err
    assign busy_err = busy && valid && 
        (hwrite && haddr >= 8'h00 && haddr <= 8'h0F || ~hwrite && haddr[9:3] == 3);

    // overrun_err
    assign overrun_err = data_ready && prev_valid && prev_hwrite 
        && prev_haddr == 8'h22 && hwdata[16];

    // next_error
    always_ff @(posedge clk, negedge rst) begin : next_error_reg
        if (~n_rst) begin
            error <= 0;
        end
        else begin
            error <= next_error;
        end
    end
    always_comb begin : next_error_logic
        if (prev_valid && ~prev_hwrite && prev_haddr == 8'h20)
            next_error = 0;
        if (buf_occ_err)
            next_error = error | 1;
        if (overrun_err)
            next_error = error | 1 << 1;
        if (busy_err)
            next_error = error | 1 << 3;
        if (nan_err)
            next_error = error | 1 << 8;
        if (inf_err)
            next_error = error | 1 << 9;
    end

    // trans_err
    always_ff @(posedge clk, negedge rst) begin : trans_err_reg
        if (~n_rst) begin
            trans_err <= 0;
        end
        else begin
            trans_err <= next_trans_err;
        end
    end
    always_comb begin : next_trans_err_logic
        trans_err = 0
        if (valid) begin
            if (hwrite == 1) begin
                if (haddr >= 8'h18 && haddr <= 8'h21)
                    trans_err = 1;
                else if (haddr == 8'h23)
                    trans_err = 1;
            end
            else if (haddr >= 8'h00 && haddr <= 8'h0F)
                    trans_err = 1;
            if (haddr > 8'h24)
                trans_err = 1;
            if (hsize > 1 && haddr == 8'h20 || 
                hsize > 0 && haddr >= 8'h21 && haddr <= 8'h24)
                trans_err = 1;
        end
    end

    // busy and buf_occ reg
    always_ff @(posedge clk, negedge rst) begin : busy_buf_occ_reg
        if (~n_rst) begin
            prev_buf_occ_err <= 0;
            prev_busy_err <= 0;
        end
        else begin
            prev_buf_occ_err <= buf_occ_err;
            prev_busy_err <= busy_err;
        end
    end

    // err fsm
    always_ff @(posedge clk, negedge rst) begin : err_fsm_reg
        if (~n_rst) begin
            err_state <= OKAY;
        end
        else begin
            err_state <= next_err_state;
        end
    end
    always_comb begin : next_err_state_logic
        case (err_state)
            OKAY: trans_err ? next_err_state = ERR_1 : next_err_state = OKAY
            ERR_1: next_err_state = ERR_2;
            ERR_2: next_err_state = OKAY;
            default: next_err_state = IDLE;
        endcase
    end
    always_comb begin : err_fsm_output_logic
        case (err_state)
            OKAY: begin
                hready_err = 1;
                hresp = 0;
            end
            ERR_1: begin
                hready_err = 0;
                hresp = 1;
            end
            ERR_2: begin
                hready_err = 1;
                hresp = 1;
            end
            default: begin
                hready_err = 0;
                hresp = 0;
            end
        endcase
    end

    assign read_output = valid && ~hwrite && haddr[9:3] == 3;
    assign block_trans = err_state != OKAY || prev_busy_err || prev_buf_occ_err;

    // output fsm
    always_ff @(posedge clk, negedge rst) begin : output_state_fsm
        if (~n_rst) begin
            output_state <= OKAY;
        end
        else begin
            output_state <= next_output_state;
        end
    end
    always_comb begin : next_output_state_logic
        case (output_state)
            IDLE: read_output ? next_output_state = STALL_1;
            STALL_1: next_output_state = STALL_2;
            STALL_2: next_output_state = STALL_3;
            STALL_3: next_output_state = STALL_4;
            STALL_4: next_output_state = IDLE;
            default: next_output_state = IDLE;
        endcase
    end
    always_comb begin : output_fsm_output_logic
        if (output_state == IDLE) hready_out = 1;
        else hready_out = 0;
    end

    assign hready = hready_err && hready_out;

    /*
    =======================
    WRITE
    =======================
    */

    // bias
    always_ff @(posedge clk, negedge rst) begin : bias_reg
        if (~n_rst) begin
            bias <= 0;
        end
        else begin
            bias <= next_bias;
        end
    end
    always_comb begin : next_bias_logic
        if (prev_valid && prev_hwrite && prev_haddr[9:3] == 2 && ~block_trans) begin
            case (prev_hsize)
                0: bytes = 1 << prev_haddr[2:0];
                1: bytes = 3 << prev_haddr[2:0];
                2: bytes = 8'h0F << prev_haddr[2:0];
                3: bytes = 8'hFF;
            endcase

            next_bias = bytes[0] ? hwdata[7:0] : bias[7:0];
            next_bias = bytes[1] ? hwdata[15:8] : bias[15:8];
            next_bias = bytes[2] ? hwdata[23:16] : bias[23:16];
            next_bias = bytes[3] ? hwdata[31:24] : bias[31:24];
            next_bias = bytes[4] ? hwdata[39:32] : bias[39:32];
            next_bias = bytes[5] ? hwdata[47:40] : bias[47:40];
            next_bias = bytes[6] ? hwdata[55:48] : bias[55:48];
            next_bias = bytes[7] ? hwdata[63:56] : bias[63:56];
        end
        else
            next_bias = bias;
    end

    // control
    always_ff @(posedge clk, negedge rst) begin : control_reg
        if (~n_rst) begin
            control <= 0;
        end
        else begin
            control <= next_control;
        end
    end
    always_comb begin : next_control_logic
        if (prev_valid && prev_hwrite && prev_haddr == 8'h22 && prev_hsize == 0 && ~block_trans)
            next_control = hwdata[23:16];
        else
            next_control = control;
        if (inference_complete) next_control[0] = 0;
        if (load_complete) next_control[1] = 0;
    end

    assign start_inference = control[0];
    assign load_weights = control[1];

    // activation_ctrl
    always_ff @(posedge clk, negedge rst) begin : activation_ctrl_reg
        if (~n_rst) begin
            activation_ctrl <= 0;
        end
        else begin
            activation_ctrl <= next_activation_ctrl;
        end
    end
    always_comb begin : next_activation_ctrl_logic
        if (prev_valid && prev_hwrite && prev_haddr == 8'h24 && prev_hsize == 0 && ~block_trans)
            next_activation_ctrl = hwdata[39:32];
        else
            next_activation_ctrl = activation_ctrl;
    end

    assign activation_mode = activation_ctrl[1:0];

    always_comb begin : write_logic
        write_input = prev_valid && prev_hwrite && 
            prev_haddr[9:3] && == 1 && ~block_trans;
        write_weight = prev_valid && prev_hwrite && 
            prev_haddr[9:3] && == 0 && ~block_trans;
    end

    // raw hazard
    always_comb begin : raw_haz_logic
        raw_haz = prev_haddr == haddr && prev_valid && valid && prev_hwrite && 
            ~hwrite && (haddr[9:3] == 2 || haddr == 0x22 || haddr == 0x24);
        if (prev_haddr == haddr && prev_valid && valid && prev_hwrite && ~hwrite && haddr[9:3] == 2)
            case (prev_hsize)
                0: raw_haz_bias = 1 << prev_haddr[2:0];
                1: raw_haz_bias = 3 << prev_haddr[2:0];
                2: raw_haz_bias = 8'h0F << prev_haddr[2:0];
                3: raw_haz_bias = 8'hFF;
            endcase
        else raw_haz_bias = 0;
    end

    // read_result
    assign read_result = prev_valid && ~prev_hwrite && prev_haddr[9:3] == 3 && 
        ~block_trans && output_state == STALL_2;

    // hrdata
    always_ff @(posedge clk, negedge rst) begin : blockName
        if (~n_rst) begin
            hrdata <= 0;
        end
        else begin
            hrdata <= next_hrdata;
        end
    end
    always_comb begin : blockName
        next_hrdata = 0;
        if (valid && ~hwrite)
            case (haddr[9:3])
                2: 
                    next_hrdata[7:0] = raw_haz_bias[0] ? hwdata[7:0] : bias[7:0];
                    next_hrdata[15:8] = raw_haz_bias[1] ? hwdata[15:8] : bias[15:8];
                    next_hrdata[23:16] = raw_haz_bias[2] ? hwdata[23:16] : bias[23:16];
                    next_hrdata[31:24] = raw_haz_bias[3] ? hwdata[31:24] : bias[31:24];
                    next_hrdata[39:32] = raw_haz_bias[4] ? hwdata[39:32] : bias[39:32];
                    next_hrdata[47:40] = raw_haz_bias[5] ? hwdata[47:40] : bias[47:40];
                    next_hrdata[55:48] = raw_haz_bias[6] ? hwdata[55:48] : bias[55:48];
                    next_hrdata[63:56] = raw_haz_bias[7] ? hwdata[63:56] : bias[63:56];
                3: next_hrdata = ahb_rdata;
                4: 
                    next_hrdata[15:0] = error;
                    next_hrdata[23:16] = raw_haz ? hwdata[23:16] : control;
                    next_hrdata[31:24] = {6'b0, busy, data_ready};
                    next_hrdata[39:32] = raw_haz ? hwdata[39:32] : activation_ctrl;
                default: next_hrdata = 0;
            endcase
    end


    // template
    always_ff @(posedge clk, negedge rst) begin : blockName
        if (~n_rst) begin
        end
        else begin
        end
    end
    always_comb begin : blockName
        
    end


    // template
    always_ff @(posedge clk, negedge rst) begin : blockName
        if (~n_rst) begin
        end
        else begin
        end
    end
    always_comb begin : blockName
        
    end

endmodule


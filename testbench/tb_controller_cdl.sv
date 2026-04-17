`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_controller_cdl ();

    localparam CLK_PERIOD = 10ns;

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars;
    end

    logic clk, n_rst;

     logic start_inference, load_weights, write_input, write_weight, read_result;
     logic [63:0] ahb_wdata;
     logic busy, data_ready; 
     logic [6:0] input_count, output_count; 
     logic [2:0] weight_count;
     logic [63:0] ahb_rdata;

     logic [63:0] inputs;
     logic load;

     logic [1:0] sram_state;
     logic [63:0] sram_rdata;
     logic sram_wen, sram_ren;
     logic [1:0] select, buf_select, out_select; 
     logic [9:0] addr, out_addr;
     logic [63:0] sram_wdata;

    // clockgen
    always begin
        clk = 0;
        #(CLK_PERIOD / 2.0);
        clk = 1;
        #(CLK_PERIOD / 2.0);
    end

    task reset_dut;
    begin
        n_rst = 0;
        start_inference = 0;
        load_weights = 0;
        write_input = 0;
        write_weight = 0;
        read_result = 0;
        ahb_wdata = 0;
        sram_state = 2'b00; //idle
        sram_rdata = 64'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1;
        @(posedge clk);
        @(posedge clk);
    end
    endtask

    controller_cdl #() DUT (.*);

    task simulate_sram_latency;
    begin
        sram_state = 2'b01; //BUSY
        repeat(3) @(negedge clk);
        sram_state = 2'b10; //ACCESS
        repeat (3) @ (negedge clk);
    end
    endtask

    initial begin
        n_rst = 1;
        reset_dut();

   // write wieght
    @(negedge clk);
    write_weight = 1;
    ahb_wdata = 64'hAAAA_AAAA_AAAA_AAAA; 
    @(negedge clk);
    write_weight = 0;
    simulate_sram_latency(); 

    //write 14 input
    for (int i = 0; i < 14; i++) begin
        @(negedge clk);
        write_input = 1;
        ahb_wdata = {16{4'(i)}}; 
        @(negedge clk);
        write_input = 0;
        simulate_sram_latency(); 
    end

    //write 4 weight
    for (int i = 0; i < 4; i++) begin
        @(negedge clk);
        write_weight = 1;
        ahb_wdata = {16{4'(i)}}; 
        @(negedge clk);
        write_weight = 0;
        simulate_sram_latency(); 
    end

    //load weight
    @(negedge clk);
    load_weights = 1;
    @(negedge clk);
    load_weights = 0;
    simulate_sram_latency(); 

    //inference block
    repeat (5) @(negedge clk);
    @(negedge clk);
    start_inference = 1;
    @(negedge clk);
    start_inference = 0;

    while (!data_ready) begin
        @(negedge clk);
        if (sram_ren) begin
            sram_rdata = 64'hDDDD_0000_0000_0000 | addr; 
        end else begin
            sram_rdata = '0;
        end
    end
    sram_rdata = '0; 
    
    repeat(10) @(negedge clk);

    //read 4 results
    for (int i = 0; i < 4; i++) begin
        @(negedge clk);
        read_result = 1;
        @(negedge clk);
        read_result = 0;
        simulate_sram_latency(); 
    end

    //write 14 input
    for (int i = 0; i < 14; i++) begin
        @(negedge clk);
        write_input = 1;
        ahb_wdata = {16{4'(i)}}; 
        @(negedge clk);
        write_input = 0;
        simulate_sram_latency(); 
    end

    repeat (5) @(negedge clk);
    //start inference
    @(negedge clk);
    start_inference = 1;
    @(negedge clk);
    start_inference = 0;
    simulate_sram_latency(); 

    repeat(70) @(negedge clk);

    $finish;
    end
endmodule

/* verilator coverage_on */


`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_ahb_subordinate_cdl ();

    localparam CLK_PERIOD = 10ns;
    localparam TIMEOUT = 1000;

    localparam BURST_SINGLE = 3'd0;
    localparam BURST_INCR   = 3'd1;
    localparam BURST_WRAP4  = 3'd2;
    localparam BURST_INCR4  = 3'd3;
    localparam BURST_WRAP8  = 3'd4;
    localparam BURST_INCR8  = 3'd5;
    localparam BURST_WRAP16 = 3'd6;
    localparam BURST_INCR16 = 3'd7;

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars;
    end

    logic clk, n_rst;

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
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
        @(negedge clk);
    end
    endtask

    logic hsel;
    logic [9:0] haddr;
    logic [2:0] hsize;
    logic [2:0] hburst;
    logic [1:0] htrans;
    logic hwrite;
    logic [63:0] hwdata;
    logic [63:0] hrdata;
    logic hresp;
    logic hready;

    // bus model connections
    ahb_model_updated #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(8)
    ) BFM ( .clk(clk),
        // AHB-Subordinate Side
        .hsel(hsel),
        .haddr(haddr),
        .hsize(hsize),
        .htrans(htrans),
        .hburst(hburst),
        .hwrite(hwrite),
        .hwdata(hwdata),
        .hrdata(hrdata),
        .hresp(hresp),
        .hready(hready)
    );

    // Supporting Tasks
    task reset_model;
        BFM.reset_model();
    endtask

    // Read from a register without checking the value
    task enqueue_poll ( input logic [9:0] addr, input logic [1:0] size );
    logic [63:0] data [];
        begin
            data = new [1];
            data[0] = {64'hXXXX};
            //              Fields: hsel,  R/W, addr, data, exp err,         size, burst, chk prdata or not
            BFM.enqueue_transaction(1'b1, 1'b0, addr, data,    1'b0, {1'b0, size},  3'b0,            1'b0);
        end
    endtask

    // Read from a register until a requested value is observed
    task poll_until ( input logic [9:0] addr, input logic [1:0] size, input logic [63:0] data);
        int iters;
        begin
            for (iters = 0; iters < TIMEOUT; iters++) begin
                enqueue_poll(addr, size);
                execute_transactions(1);
                if(BFM.get_last_read() == data) break;
            end
            if(iters >= TIMEOUT) begin
                $error("Bus polling timeout hit.");
            end
        end
    endtask

    // Write Transaction Intended for a different subordinate from yours
    task enqueue_fakewrite ( input logic [9:0] addr, input logic [1:0] size, input logic [63:0] wdata );
        logic [63:0] data [];
        begin
            data = new [1];
            data[0] = wdata;
            BFM.enqueue_transaction(1'b0, 1'b1, addr, data, 1'b0, {1'b0, size}, 3'b0, 1'b0);
        end
    endtask

    // Read Transaction, verifying a specific value is read
    task enqueue_read ( input logic [9:0] addr, input logic [1:0] size, input logic [63:0] exp_read, input logic exp_err, input logic check = 1);
        logic [63:0] data [];
        begin
            data = new [1];
            data[0] = exp_read;
            BFM.enqueue_transaction(1'b1, 1'b0, addr, data, exp_err, {1'b0, size}, 3'b0, check);
        end
    endtask

    // Write Transaction
    task enqueue_write ( input logic [9:0] addr, input logic [1:0] size, input logic [63:0] wdata, input logic exp_err);
        logic [63:0] data [];
        begin
            data = new [1];
            data[0] = wdata;
            BFM.enqueue_transaction(1'b1, 1'b1, addr, data, exp_err, {1'b0, size}, 3'b0, 1'b0);
        end
    endtask

    // Create a burst read of size based on the burst type.
    // If INCR, burst size dependent on dynamic array size
    task enqueue_burst_read ( input logic [9:0] base_addr, input logic [1:0] size, input logic [2:0] burst, input logic [63:0] data [] );
        BFM.enqueue_transaction(1'b1, 1'b0, base_addr, data, 1'b0, {1'b0, size}, burst, 1'b1);
    endtask

    // Create a burst write of size based on the burst type.
    task enqueue_burst_write ( input logic [9:0] base_addr, input logic [1:0] size, input logic [2:0] burst, input logic [63:0] data [] );
        BFM.enqueue_transaction(1'b1, 1'b1, base_addr, data, 1'b0, {1'b0, size}, burst, 1'b1);
    endtask

    // Run n transactions, where a k-beat burst counts as k transactions.
    task execute_transactions (input int num_transactions);
        BFM.run_transactions(num_transactions);
    endtask

    // Finish the current transaction
    task finish_transactions();
        BFM.wait_done();
    endtask

    logic [63:0] data [];
    int test;
    logic busy, data_ready, inf_err, nan_err, inference_complete, load_complete;
    logic start_inference, load_weights, write_input, write_weight, read_result;
    logic [1:0] activation_mode;
    logic [2:0] size;
    logic [3:0] width;
    logic [7:0] input_count, weight_count, output_count;
    logic [9:0] addr;
    logic [63:0] ahb_wdata, bias;
    logic [7:0] [7:0] ahb_rdata;
    logic check_pulse;

    task check_wdata(input logic [63:0] exp);
        check_pulse = 1;
        #(0.1);
        check_pulse = 0;
        if (exp == ahb_wdata)
            $display("No error with ahb_wdata.");
        else
            $display("Error with ahb_wdata. Expected: %h, Output: %h", exp, ahb_wdata);
    endtask 

    ahb_subordinate_cdl DFT (.hsize(hsize[1:0]), .*);

    initial begin
        n_rst = 1;
        test = 0;
        busy = 0;
        data_ready = 0;
        output_count = 0;
        inf_err = 0;
        nan_err = 0;
        width = 0;
        ahb_rdata = 0;
        check_pulse = 0;

        reset_model();
        reset_dut();

        // Write to weights and inputs
        test = 1;
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 0; addr <= 8 - width; addr += width) begin
                enqueue_write(addr, size, 64'hAB, 0);
                fork
                    execute_transactions(1);
                    begin
                        @(negedge clk);
                        @(negedge clk);
                        @(negedge clk);
                        check_wdata(8'hAB << (addr * 8));
                    end
                join
                enqueue_read(addr, size, 0, 1);
                execute_transactions(1);
                finish_transactions();
            end
        end
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 8; addr <= 16 - width; addr += width) begin
                enqueue_write(addr, size, 64'hBA, 0);
                fork
                    execute_transactions(1);
                    begin
                        @(negedge clk);
                        @(negedge clk);
                        @(negedge clk);
                        check_wdata(8'hBA << (addr[2:0] * 8));
                    end
                join
                enqueue_read(addr, size, 0, 1);
                execute_transactions(1);
                finish_transactions();
            end
        end

        // Read from outputs
        test = 2;
        ahb_rdata = 64'hFEDC_BA98_7654_3210;
        output_count = 1;
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 8'h18; addr <= 8'h20 - width; addr += width) begin
                enqueue_read(addr, size, ahb_rdata[addr - 8'h18], 0);
                execute_transactions(1);
                finish_transactions();
            end
        end
        output_count = 0;

        // Read/write to non-SRAM registers
        test = 3;
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 8'h10; addr <= 8'h18 - width; addr += width) begin
                enqueue_write(addr, size, addr, 0);
                enqueue_read(addr, size, addr, 0);
                execute_transactions(2);
                finish_transactions();
            end
        end
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 8'h20; addr <= 8'h25 - width; addr += width) begin
                // write
                if (addr == 8'h20 || addr == 8'h21 || addr == 8'h23) begin // read-only
                    enqueue_write(addr, size, addr, 1);
                end
                else if (addr == 8'h22)
                    enqueue_write(addr, size, 1, size > 0); // read/write
                else // addr 8'h24
                    enqueue_write(addr, size, 3, size > 0); // read/write
                execute_transactions(1);
                finish_transactions();
                @(negedge clk);

                // read
                if (addr == 8'h20) begin // read-only
                    enqueue_read(addr, size, 64'h00, size > 1);
                end
                else if (addr == 8'h21) begin // read-only
                    inf_err = 1;
                    nan_err = 1;
                    enqueue_read(addr, size, 64'h03, size > 0);
                end
                else if (addr == 8'h22) // read/write
                    enqueue_read(addr, size, size == 0 ? 64'h01 : 0, size > 0);
                else if (addr == 8'h23) begin // read-only
                    busy = 1;
                    enqueue_read(addr, size, 64'h02, size > 0);
                end
                else // read/write
                    enqueue_read(addr, size, 64'h03, 0);
                execute_transactions(1);
                finish_transactions();

                check_pulse = 1;
                #(0.1);
                check_pulse = 0;

                inf_err = 0;
                nan_err = 0;
                busy = 0;
            end
            n_rst = 0;
            @(negedge clk);
            n_rst = 1;
        end

        // Overrun error detection
        test = 4;
        data_ready = 1;
        enqueue_write(8'h22, 0, 1, 0);
        execute_transactions(1);
        finish_transactions();
        enqueue_read(8'h20, 0, 1 << 1, 0);
        execute_transactions(1);
        finish_transactions();
        enqueue_write(8'h22, 0, 0, 0);
        execute_transactions(1);
        finish_transactions();
        
        data_ready = 0;

        // Busy error detection
        test = 5;
        busy = 1;
        output_count = 1;
        enqueue_read(8'h18, 0, 0, 0, 0);
        execute_transactions(1);
        finish_transactions();
        enqueue_read(8'h20, 0, 1 << 3, 0);
        execute_transactions(1);
        finish_transactions();
        busy = 0;
        
        // Buf occ error detection
        test = 6;
        output_count = 0;
        enqueue_read(8'h18, 0, 0, 0, 0);
        execute_transactions(1);
        finish_transactions();
        
        enqueue_read(8'h20, 0, 1 << 0, 0);
        execute_transactions(1);
        finish_transactions();

        // Error clear on read
        test = 7;
        inf_err = 1;
        nan_err = 1;
        @(negedge clk);
        inf_err = 0;
        nan_err = 0;
        // buf occ
        output_count = 0;
        enqueue_read(8'h18, 0, 0, 0, 0);
        execute_transactions(1);
        finish_transactions();
        // busy err
        busy = 1;
        output_count = 1;
        enqueue_read(8'h18, 0, 0, 0, 0);
        execute_transactions(1);
        finish_transactions();
        busy = 0;
        output_count = 0;
        // overrun err
        data_ready = 1;
        enqueue_write(8'h22, 0, 1, 0);
        execute_transactions(1);
        finish_transactions();
        data_ready = 0;
        
        enqueue_read(8'h20, 1, 16'b1100001011, 0);
        execute_transactions(1);
        finish_transactions();
        
        enqueue_read(8'h20, 1, 0, 0);
        execute_transactions(1);
        finish_transactions();

        // RAW Hazard
        test = 8;
        for (size = 0; size <= 3; size++) begin
            width = 1 << size;
            for (addr = 8'h10; addr <= 8'h18 - width; addr += width) begin
                enqueue_write(addr, size, addr, 0);
                enqueue_read(addr, size, addr, 0);
                execute_transactions(2);
                finish_transactions();
            end
        end

        n_rst = 0;
        @(negedge clk);
        n_rst = 1;

        // write to two bytes, read from upper byte
        enqueue_write(8'h10, 1, 16'hABCD, 0);
        enqueue_read(8'h11, 0, 8'hAB, 0);
        execute_transactions(2);
        finish_transactions();

        // write to upper byte, read from two bytes
        enqueue_write(8'h11, 0, 8'hEE, 0);
        enqueue_read(8'h10, 1, 16'hEECD, 0);
        execute_transactions(2);
        finish_transactions();

        enqueue_write(8'h22, 0, 8'hCC, 0);
        enqueue_read(8'h22, 0, 8'hCC, 0);
        execute_transactions(2);
        finish_transactions();

        enqueue_write(8'h24, 0, 8'hCC, 0);
        enqueue_read(8'h24, 0, 8'hCC, 0);
        execute_transactions(2);
        finish_transactions();
        
        n_rst = 0;
        @(negedge clk);
        n_rst = 1;

        // Fake write
        test = 9;
        enqueue_fakewrite(8'h22, 0, 1);
        enqueue_read(8'h22, 0, 0, 0);
        execute_transactions(2);
        finish_transactions();
        repeat(4) @(negedge clk);

        // Burst transfers
        test = 10;

        // INCR
        data = new [3];
        data = {8'hAA, 8'hBB, 8'hCC};
        enqueue_burst_write(8'h10, 0, BURST_INCR, data);
        enqueue_burst_read(8'h10, 0, BURST_INCR, data);
        execute_transactions(6);
        finish_transactions();

        // WRAP4
        data = new [4];
        data = {8'hAB, 8'hBC, 8'hCD, 8'hDE};
        enqueue_burst_write(8'h12, 0, BURST_WRAP4, data);
        enqueue_burst_read(8'h12, 0, BURST_WRAP4, data);
        execute_transactions(8);
        finish_transactions();

        // INCR4
        data = {8'h12, 8'h23, 8'h34, 8'h45};
        enqueue_burst_write(8'h10, 0, BURST_INCR4, data);
        enqueue_burst_write(8'h10, 0, BURST_INCR4, data);
        execute_transactions(8);
        finish_transactions();

        // WRAP8
        data = new [8];
        data = {8'h01, 8'h12, 8'h23, 8'h34, 8'h45, 8'h56, 8'h67, 8'h78};
        enqueue_burst_write(8'h14, 0, BURST_WRAP8, data);
        enqueue_burst_read(8'h14, 0, BURST_WRAP8, data);
        execute_transactions(16);
        finish_transactions();

        // INCR8
        data = {8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17, 8'h18};
        enqueue_burst_write(8'h10, 0, BURST_INCR8, data);
        enqueue_burst_read(8'h10, 0, BURST_INCR8, data);
        execute_transactions(16);
        finish_transactions();

        // WRAP16
        data = new [16];
        foreach (data[i]) data[i] = i;
        enqueue_burst_write(8'h08, 0, BURST_WRAP16, data);
        fork
            execute_transactions(16);
            begin
                repeat(2) @(negedge clk);
                foreach (data[i]) begin
                    @(negedge clk);
                    check_wdata(data[i] << (8*(i%8)));
                    if (i < 8 && ~write_input ||
                        i >= 8 && ~write_weight)
                        $display("Error with input/weight detection.");
                        check_pulse = 1;
                        #(0.1);
                        check_pulse = 0;
                        #(0.1);
                        check_pulse = 1;
                        #(0.1);
                        check_pulse = 0;
                end
            end
        join
        finish_transactions();

        // INCR16
        enqueue_burst_write(8'h0, 0, BURST_INCR16, data);
        fork
            execute_transactions(16);
            begin
                repeat(2) @(negedge clk);
                foreach (data[i]) begin
                    @(negedge clk);
                    check_wdata(data[i] << (8*(i%8)));
                    if (i < 8 && ~write_weight ||
                        i >= 8 && ~write_input)
                        $display("Error with input/weight detection.");
                end
            end
        join
        finish_transactions();

        // Create a burst read of size based on the burst type.
        // If INCR, burst size dependent on dynamic array size
        // task enqueue_burst_read ( input logic [3:0] base_addr, input logic [1:0] size, input logic [2:0] burst, input logic [31:0] data [] );
        //     BFM.enqueue_transaction(1'b1, 1'b0, base_addr, data, 1'b0, {1'b0, size}, burst, 1'b1);
        // endtask

        // // Create a burst write of size based on the burst type.
        // task enqueue_burst_write ( input logic [3:0] base_addr, input logic [1:0] size, input logic [2:0] burst, input logic [31:0] data [] );
        //     BFM.enqueue_transaction(1'b1, 1'b1, base_addr, data, 1'b0, {1'b0, size}, burst, 1'b1);
        // endtask

        /****** EXAMPLE CODE ******/
        // Always put data LSB-aligned. The model will automagically move bytes to their proper position.
        // enqueue_read(3'h1, 1'b0, 63'h00BB);
        // enqueue_write(3'h2, 1'b1, 63'h00BB);
        
        // // Example Burst Setup - Dynamic Array Required
        // data = new [8];
        // data = {64'h8888_8888, 64'h7777_7777,64'h6666_6666,64'h5555_5555,64'h4444_4444,64'h3333_3333,64'h2222_2222,64'h1111_1111};
        // enqueue_burst_read(4'hC, 1'b1, BURST_WRAP8, data);
        // execute_transactions(10); // Burst counts as 8 transactions for 8 beats
        // finish_transactions();
        /****** EXAMPLE CODE ******/

        $finish;
    end
endmodule

/* verilator coverage_on */

// MazeSolver Bot: Task 2A - DHT11 Interface
/*
# Team ID:          eYRC#4816
# Theme:            MazeSolver Bot
# Author List:      U.V. Rishitha Priya, B. Ravi Kiran Varma
# Filename:         t2a_dht.v
# File Description: DHT11 Temperature & Humidity Sensor Reader (40-bit data capture + checksum)
# Global variables: state, cnt, bit_cnt, shift, sensor_dir, sensor_out
*/

module t2a_dht(
    input  clk_50M,
    input  reset,           // **Active LOW reset**
    inout  sensor,          // DHT11 data pin (bidirectional)

    output reg [7:0] T_integral,
    output reg [7:0] RH_integral,
    output reg [7:0] T_decimal,
    output reg [7:0] RH_decimal,
    output reg [7:0] Checksum,
    output reg data_valid
);

// -----------------------------------------------------------------------------
//  Bidirectional SENSOR pin
//  sensor_dir = 1 → FPGA drives line
//  sensor_dir = 0 → FPGA releases line (sensor drives it)
// -----------------------------------------------------------------------------
reg sensor_dir;
reg sensor_out;
assign sensor = sensor_dir ? sensor_out : 1'bz;
wire sensor_in = sensor;     // Read sensor value

// -----------------------------------------------------------------------------
// FSM States
// -----------------------------------------------------------------------------
localparam S_IDLE        = 4'd0,   // Drive low for start signal
           S_START_LOW   = 4'd1,   // 18 ms LOW
           S_START_HIGH  = 4'd2,   // 40 us HIGH
           S_WAIT_RL     = 4'd3,   // Wait for sensor response LOW
           S_WAIT_RH     = 4'd4,   // Wait for sensor response HIGH
           S_BITLOW      = 4'd5,   // 50 us LOW bit start
           S_BITHIGH     = 4'd6,   // Measure HIGH pulse to identify 0/1
           S_WAIT_LATCH  = 4'd7,   // Extra 1-cycle delay (e-Yantra TB requirement)
           S_LATCH       = 4'd8,   // Store data + checksum verify
           S_WAITNEXT    = 4'd9;   // Wait before next cycle

reg [3:0] state;

// -----------------------------------------------------------------------------
// Timing constants (50 MHz → 20ns period)
// -----------------------------------------------------------------------------
localparam START_LOW_CYC   = 900000;  // 18 ms
localparam START_HIGH_CYC  = 2000;    // 40 us
localparam RESP_MIN_CYC    = 3000;    // Expected ~80 us response
localparam BIT_LOW_MIN     = 2000;    // ~40 us minimum low time for each bit
localparam BIT_ONE_TH      = 2400;    // HIGH pulse >48us = logic '1'

// -----------------------------------------------------------------------------
// Internal registers
// -----------------------------------------------------------------------------
reg [19:0] cnt;            // General timing counter
reg [5:0]  bit_cnt;        // Counts received bits 0–39
reg [39:0] shift;          // Shift register for 40-bit DHT data

// -----------------------------------------------------------------------------
// Main FSM
// -----------------------------------------------------------------------------
always @(posedge clk_50M) begin

    if (!reset) begin
        // Reset all registers
        state <= S_IDLE;
        cnt <= 0;
        bit_cnt <= 0;
        shift <= 0;
        sensor_dir <= 0;
        sensor_out <= 1;

        RH_integral <= 0;
        RH_decimal  <= 0;
        T_integral  <= 0;
        T_decimal   <= 0;
        Checksum    <= 0;
        data_valid  <= 0;
    end

    else begin
        data_valid <= 0;   // Default every cycle

        case (state)

        // ---------------------------------------------------------
        // Send start signal → pull LOW for 18 ms
        // ---------------------------------------------------------
        S_IDLE: begin
            sensor_dir <= 1;
            sensor_out <= 0;
            cnt <= 1;
            state <= S_START_LOW;
        end

        S_START_LOW: begin
            sensor_dir <= 1;
            sensor_out <= 0;
            if (cnt < START_LOW_CYC)
                cnt <= cnt + 1;
            else begin
                cnt <= 1;
                sensor_out <= 1;   // Pull HIGH
                state <= S_START_HIGH;
            end
        end

        // ---------------------------------------------------------
        // After LOW, keep HIGH for 40us, then release line
        // ---------------------------------------------------------
        S_START_HIGH: begin
            sensor_dir <= 1;
            sensor_out <= 1;
            if (cnt < START_HIGH_CYC)
                cnt <= cnt + 1;
            else begin
                sensor_dir <= 0;   // Release line, sensor will answer
                cnt <= 0;
                state <= S_WAIT_RL;
            end
        end

        // ---------------------------------------------------------
        // Sensor first pulls line LOW (~80us)
        // ---------------------------------------------------------
        S_WAIT_RL: begin
            if (!sensor_in)
                cnt <= cnt + 1;

            if (sensor_in && cnt > 0) begin   // LOW → HIGH transition
                cnt <= 1;
                state <= S_WAIT_RH;
            end
        end

        // ---------------------------------------------------------
        // Sensor then pulls HIGH (~80us)
        // ---------------------------------------------------------
        S_WAIT_RH: begin
            if (sensor_in)
                cnt <= cnt + 1;
            else begin
                // HIGH → LOW transition = start of bit sequence
                cnt <= 0;
                bit_cnt <= 0;
                shift <= 0;
                state <= S_BITLOW;
            end
        end

        // ---------------------------------------------------------
        // Start of each bit (sensor LOW ~50us)
        // ---------------------------------------------------------
        S_BITLOW: begin
            if (!sensor_in)
                cnt <= cnt + 1;
            else begin
                // LOW complete
                if (cnt >= BIT_LOW_MIN) begin
                    cnt <= 1;
                    state <= S_BITHIGH;
                end
                else begin
                    cnt <= 0;   // Noise/invalid low pulse
                end
            end
        end

        // ---------------------------------------------------------
        // HIGH pulse determines value:
        // HIGH < BIT_ONE_TH → '0'
        // HIGH > BIT_ONE_TH → '1'
        // ---------------------------------------------------------
        S_BITHIGH: begin
            if (sensor_in)
                cnt <= cnt + 1;
            else begin
                // HIGH complete → store bit
                shift <= {shift[38:0], (cnt > BIT_ONE_TH)};
                bit_cnt <= bit_cnt + 1;
                cnt <= 0;

                if (bit_cnt == 6'd39)
                    state <= S_WAIT_LATCH;
                else
                    state <= S_BITLOW;
            end
        end

        // ---------------------------------------------------------
        // Extra 1-clock delay for e-Yantra testbench alignment
        // ---------------------------------------------------------
        S_WAIT_LATCH: begin
            if (cnt < 1)
                cnt <= cnt + 1;
            else begin
                cnt <= 0;
                state <= S_LATCH;
            end
        end

        // ---------------------------------------------------------
        // LATCH DATA → Checksum validation
        // ---------------------------------------------------------
        S_LATCH: begin
            if ((shift[39:32] + shift[31:24] + shift[23:16] + shift[15:8])
                == shift[7:0]) begin

                RH_integral <= shift[39:32];
                RH_decimal  <= shift[31:24];
                T_integral  <= shift[23:16];
                T_decimal   <= shift[15:8];
                Checksum    <= shift[7:0];
                data_valid  <= 1;   // Output is valid
            end

            // Prepare for next reading
            cnt <= 0;
            bit_cnt <= 0;
            shift <= 0;
            state <= S_WAITNEXT;
        end

        // ---------------------------------------------------------
        // Wait until sensor pulls LOW again → Restart cycle
        // ---------------------------------------------------------
        S_WAITNEXT: begin
            if (!sensor_in)
                state <= S_IDLE;
        end

        endcase
    end
end

endmodule

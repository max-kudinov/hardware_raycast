`include "fixp_pkg.svh"
`include "tex_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module render
    import fixp_pkg::*;
    import tex_pkg::*;
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::FRAME_WIDTH;
    import dvi_pkg::FRAME_HEIGHT;
    import dvi_pkg::W_COLOR;
(
    input  var logic                 clk,
    input  var logic                 rst,

    // DVI
    input  var logic [W_H_RES-1:0]   px_x_i,
    input  var logic [W_V_RES-1:0]   px_y_i,
    input  var logic                 in_range_i,
    input  var logic                 new_frame_i,
    output var logic [W_COLOR-1:0]   red_o,
    output var logic [W_COLOR-1:0]   green_o,
    output var logic [W_COLOR-1:0]   blue_o,

    // Map coordinates to check for a wall
    output var logic [POS_W_INT-1:0] lookup_map_x_o,
    output var logic [POS_W_INT-1:0] lookup_map_y_o,
    input  var logic                 wall_hit_i,

    // Camera coordinates
    input  var pos_fixp_t            pos_x_i,
    input  var pos_fixp_t            pos_y_i,
    // Camera direction
    input  var ray_fixp_t            dir_x_i,
    input  var ray_fixp_t            dir_y_i,
    // Camera plane
    input  var ray_fixp_t            plane_x_i,
    input  var ray_fixp_t            plane_y_i
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned    W_BUF_DATA    = 1                                +  // tex_shade
                                           W_TEX_SIDE                       +  // tex_x
                                           TEX_STEP_W_INT + TEX_STEP_W_FRAC +  // tex_step
                                           (W_V_RES - 1);                      // tex_height (LSB is not used)

localparam int unsigned    BUF_DEPTH     = FRAME_WIDTH * 2;
localparam int unsigned    W_BUF_ADDR    = $clog2(BUF_DEPTH);
localparam tex_step_fixp_t TEX_SCALE_EXT = `FIXP_CAST(TEX_SCALE, tex_step_fixp_t);
localparam int unsigned    FRAC_PADDING  = TEX_STEP_W_FRAC - (W_TEX_SIDE - TEX_STEP_W_INT);

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef logic [-1:-signed'(TEX_STEP_W_FRAC)] temp_fixp_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

// Buffer with data for each screen column
logic [W_BUF_DATA-1:0] frame_buffer [BUF_DEPTH];
logic                  buf_write;
logic                  buf_read;
logic                  buf_toggle;
logic [W_BUF_ADDR-1:0] buf_rd_addr;
logic [W_BUF_ADDR-1:0] buf_wr_addr;
logic [W_BUF_DATA-1:0] buf_wr_data;
logic [W_BUF_DATA-1:0] buf_rd_data;

// Calculated texture data to be written to the buffer
// verilator lint_off UNUSEDSIGNAL
logic [W_V_RES-1:0]    wr_tex_height;  // LSB is not used
// verilator lint_on UNUSEDSIGNAL
logic                  wr_tex_shade;
logic [W_TEX_SIDE-1:0] wr_tex_x;
tex_step_fixp_t        wr_tex_step;

// Calculation control signals
logic                  calc_start;
logic                  calc_done;
logic [W_H_RES-1:0]    calc_px_x;
logic                  calc_active;

// Stage 0
logic                  valid_0;
logic [W_V_RES-1:0]    px_y_0;
logic [W_H_RES-1:0]    px_x_0;

// Texture data from the buffer
logic [W_V_RES-2:0]    rd_tex_height;
logic                  rd_tex_shade;
logic [W_TEX_SIDE-1:0] rd_tex_x;
tex_step_fixp_t        rd_tex_step;


// Stage 1
logic                  valid_1;
logic [W_TEX_SIDE-1:0] tex_align_next_1;
logic [W_TEX_SIDE-1:0] tex_align_ff_1;
logic [W_V_RES-1:0]    tex_start_next_1;
logic [W_V_RES-1:0]    tex_start_ff_1;
logic [W_V_RES-1:0]    tex_end_1;
logic                  in_texture_next_1;
logic                  in_texture_ff_1;
logic                  tex_shade_1;
logic [W_TEX_SIDE-1:0] tex_x_1;
tex_step_fixp_t        tex_step_1;

tex_start_fixp_t y_zoom_offset_next_1;
tex_start_fixp_t y_zoom_offset_ff_1;

temp_fixp_t step_frac;
temp_fixp_t height_ext;
temp_fixp_t temp_mult;

// Stage 2
logic                  valid_2;
tex_step_fixp_t tex_align_ext;
tex_step_fixp_t tex_align_scaled;
tex_pos_fixp_t  y_pos;

logic [TEX_POS_W_INT-1:0] tex_y_next_2;
logic [TEX_POS_W_INT-1:0] tex_y_ff_2;
logic                  in_texture_ff_2;
logic [W_TEX_SIDE-1:0] tex_x_2;
logic                  tex_shade_2;

// Stage 3
logic [W_COLOR-1:0]   red_next;
logic [W_COLOR-1:0]   green_next;
logic [W_COLOR-1:0]   blue_next;

logic [TEX_SIDE-1:0] texture [TEX_SIDE];

always_ff @(posedge clk)
    if (rst)
        buf_toggle <= '0;
    else if (new_frame_i)
        buf_toggle <= !buf_toggle;

// Simple dual-port block RAM with read-first behavior
always_ff @(posedge clk) begin
    if (buf_write)
        frame_buffer[buf_wr_addr] <= buf_wr_data;

    if (buf_read)
        buf_rd_data <= frame_buffer[buf_rd_addr];
end

column_calc column_calc (
    .clk            (clk           ),
    .rst            (rst           ),

    .start_i        (calc_start    ),
    .px_x_i         (calc_px_x     ),

    .pos_x_i        (pos_x_i       ),
    .pos_y_i        (pos_y_i       ),
    .dir_x_i        (dir_x_i       ),
    .dir_y_i        (dir_y_i       ),
    .plane_x_i      (plane_x_i     ),
    .plane_y_i      (plane_y_i     ),

    .lookup_map_x_o (lookup_map_x_o),
    .lookup_map_y_o (lookup_map_y_o),
    .wall_hit_i     (wall_hit_i    ),

    .done_o         (calc_done     ),
    .ray_hit_side_o (wr_tex_shade  ),
    .tex_x_o        (wr_tex_x      ),
    .tex_step_o     (wr_tex_step   ),
    .height_o       (wr_tex_height )
);

always_ff @(posedge clk) begin
    if (rst) begin
        calc_px_x  <= '0;
    end else if (calc_done) begin
        if (calc_px_x == (FRAME_WIDTH - 1)) begin
            calc_px_x <= '0;
        end else begin
            calc_px_x <= calc_px_x + 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst)
        calc_active <= '0;
    else if (new_frame_i)
        calc_active <= '1;
    else if (calc_start && (calc_px_x == (FRAME_WIDTH - 1)))
        calc_active <= '0;
end

always_ff @(posedge clk)
    if (rst)
        calc_start <= '0;
    else if (new_frame_i)
        calc_start <= '1;
    else
        calc_start <= calc_active && calc_done;

// Height divided in half is used for calculations, so we don't need LSB
assign buf_wr_data = { wr_tex_shade, wr_tex_x, wr_tex_step, wr_tex_height[W_V_RES-1:1] };
assign buf_write   = calc_done;
assign buf_wr_addr = W_BUF_ADDR'(calc_px_x) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { buf_toggle } });

// ----------------------------------------------------------------------------
// Pipeline that calculates pixel values based on coordinates and data that is
// read from the texture buffer
// Stage 0
// Buffer read control signals, register inputs for next stage
// ----------------------------------------------------------------------------

assign buf_read    = in_range_i;
assign buf_rd_addr = W_BUF_ADDR'(px_x_i) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { buf_toggle } });

// Read data is available in the next clock cycle
always_ff @(posedge clk)
    if (rst)
        valid_0 <= '0;
    else
        valid_0 <= buf_read;

always_ff @(posedge clk)
    px_y_0 <= px_y_i;

// TODO: temp, remove
always_ff @(posedge clk)
    px_x_0 <= px_x_i;

// ----------------------------------------------------------------------------
// Stage 1
// Get values from the buffer, calculate texture start and end coordinates
// based on height, calculate texture zoom offset (y_start) and intermediate
// value for y coordinate in the texture
// ----------------------------------------------------------------------------

assign { rd_tex_shade, rd_tex_x, rd_tex_step, rd_tex_height } = buf_rd_data;

always_comb begin
    tex_start_next_1  = (FRAME_HEIGHT >> 1) - W_V_RES'(rd_tex_height);
    tex_end_1         = (FRAME_HEIGHT >> 1) + W_V_RES'(rd_tex_height);
    in_texture_next_1 = (px_y_0 >= tex_start_next_1) && (px_y_0 <= tex_end_1);

    step_frac         = rd_tex_step[-1:$right(rd_tex_step)];
    height_ext        = { FRAME_HEIGHT[W_V_RES-1:1], { TEX_START_W_FRAC {1'b0} } };
    temp_mult         = `FIXP_MULT(height_ext, step_frac);

    if (rd_tex_step < TEX_SCALE_EXT)
        y_zoom_offset_next_1 = { TEX_START_W_INT'(TEX_SIDE >> 1), { TEX_START_W_FRAC {1'b0} } } -
                               { temp_mult }[$size(y_zoom_offset_next_1)-1:0];
    else
        y_zoom_offset_next_1 = '0;

    tex_align_next_1 = W_TEX_SIDE'(px_y_0 - tex_start_next_1);
end

always_ff @(posedge clk)
    if (valid_0) begin
        tex_start_ff_1     <= tex_start_next_1;
        in_texture_ff_1    <= in_texture_next_1;
        y_zoom_offset_ff_1 <= y_zoom_offset_next_1;
        tex_align_ff_1     <= tex_align_next_1;
        tex_shade_1        <= rd_tex_shade;
        tex_x_1            <= rd_tex_x;
        tex_step_1         <= rd_tex_step;
     end

always_ff @(posedge clk)
    valid_1 <= valid_0;

// ----------------------------------------------------------------------------
// Stage 2
// Calculate texture y coordinate
// ----------------------------------------------------------------------------

always_comb begin
    tex_align_ext    = { tex_align_ff_1, { FRAC_PADDING {1'b0} } };
    tex_align_scaled = `FIXP_MULT(tex_align_ext, tex_step_1);
    y_pos            = tex_start_fixp_t'(y_zoom_offset_ff_1) +
                       tex_start_fixp_t'(tex_align_scaled[$left(tex_align_scaled) -: $size(y_pos)]);
    tex_y_next_2     = y_pos[TEX_POS_W_INT-1:0];
end

always_ff @(posedge clk)
    if (valid_1) begin
        in_texture_ff_2 <= in_texture_ff_1;
        tex_shade_2     <= tex_shade_1;
        tex_x_2         <= tex_x_1;
        tex_y_ff_2      <= tex_y_next_2;
    end

always_ff @(posedge clk)
    valid_2 <= valid_1;

// ----------------------------------------------------------------------------
// Stage 3
// Get texel from the texture and apply shade if necessary
// ----------------------------------------------------------------------------

always_comb begin
    red_next   = '0;
    green_next = '0;
    blue_next  = '0;

    if (in_texture_ff_2) begin
        if (tex_shade_2) begin
            if (!texture[tex_y_ff_2][tex_x_2])
                red_next = 255 >> 1;
        end else begin
            if (!texture[tex_y_ff_2][tex_x_2])
                red_next = 255;
        end
    end
end

always_ff @(posedge clk)
    if (valid_2) begin
        red_o   <= red_next;
        green_o <= green_next;
        blue_o  <= blue_next;
    end

initial begin
    for (int unsigned i = 0; i < TEX_SIDE; i++)
        for (int unsigned j = 0; j < TEX_SIDE; j++)
            texture[i][j] = (i == j) || (j == TEX_SIDE - i);
end


endmodule

`resetall

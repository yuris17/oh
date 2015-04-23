module erx (/*AUTOARG*/
   // Outputs
   rxo_wr_wait_p, rxo_wr_wait_n, rxo_rd_wait_p, rxo_rd_wait_n,
   rxwr_access, rxwr_packet, rxrd_access, rxrd_packet, rxrr_access,
   rxrr_packet, mi_dout, mi_rx_edma_dout, mi_rx_emmu_dout,
   mi_rx_cfg_dout, mi_rx_mailbox_dout, mailbox_full,
   mailbox_not_empty,
   // Inputs
   reset, rxi_lclk_p, rxi_lclk_n, rxi_frame_p, rxi_frame_n,
   rxi_data_p, rxi_data_n, rxwr_clk, rxwr_wait, rxrd_clk, rxrd_wait,
   rxrr_clk, rxrr_wait, mi_clk, mi_en, mi_we, mi_addr, mi_din
   );

   parameter AW   = 32;
   parameter DW   = 32;
   parameter PW   = 104;
   parameter RFAW = 13;
   parameter MW   = 44; //width of MMU lookup table
   
   //reset
   input           reset;

   //FROM IO Pins
   input 	  rxi_lclk_p,  rxi_lclk_n;     //link rx clock input
   input 	  rxi_frame_p,  rxi_frame_n;   //link rx frame signal
   input [7:0] 	  rxi_data_p,   rxi_data_n;    //link rx data
   output 	  rxo_wr_wait_p,rxo_wr_wait_n; //link rx write pushback output
   output 	  rxo_rd_wait_p,rxo_rd_wait_n; //link rx read pushback output

   //Master write
   input 	   rxwr_clk;   
   output 	   rxwr_access;		
   output [PW-1:0] rxwr_packet;
   input 	   rxwr_wait;

   //Master read request
   input 	   rxrd_clk;   
   output 	   rxrd_access;		
   output [PW-1:0] rxrd_packet;
   input 	   rxrd_wait;

   //Slave read response
   input 	   rxrr_clk;   
   output 	   rxrr_access;		
   output [PW-1:0] rxrr_packet;
   input 	   rxrr_wait;
  
   //Register Access Interface
   input 	   mi_clk;
   input 	   mi_en; 
   input 	   mi_we;
   input [19:0]    mi_addr;
   input [31:0]    mi_din;
   output [31:0]   mi_dout;
   output [DW-1:0] mi_rx_edma_dout;
   output [DW-1:0] mi_rx_emmu_dout;
   output [DW-1:0] mi_rx_cfg_dout;
   output [DW-1:0] mi_rx_mailbox_dout;	// From emailbox of emailbox.v

   //Mailbox signals
   output 	   mailbox_full;
   output 	   mailbox_not_empty;

   /*AUTOOUTPUT*/
   /*AUTOINPUT*/

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [8:0]		ecfg_rx_datain;		// From erx_io of erx_io.v
   wire			ecfg_rx_enable;		// From ecfg_rx of ecfg_rx.v
   wire			ecfg_rx_mmu_enable;	// From ecfg_rx of ecfg_rx.v
   wire			edma_access;		// From edma of edma.v
   wire [103:1]		edma_packet;		// From edma of edma.v, ...
   wire			edma_wait;		// From erx_disty of erx_disty.v
   wire			emmu_access;		// From emmu of emmu.v
   wire [PW-1:0]	emmu_packet;		// From emmu of emmu.v
   wire			erx_access;		// From erx_protocol of erx_protocol.v
   wire [PW-1:0]	erx_packet;		// From erx_protocol of erx_protocol.v
   wire [63:0]		rx_data_par;		// From erx_io of erx_io.v
   wire [7:0]		rx_frame_par;		// From erx_io of erx_io.v
   wire			rx_lclk_div4;		// From erx_io of erx_io.v
   wire			rx_rd_wait;		// From erx_disty of erx_disty.v
   wire			rx_wr_wait;		// From erx_disty of erx_disty.v
   wire			rxrd_fifo_access;	// From erx_disty of erx_disty.v
   wire [PW-1:0]	rxrd_fifo_packet;	// From erx_disty of erx_disty.v
   wire			rxrd_fifo_wait;		// From rxrd_fifo of fifo_async.v
   wire			rxrr_fifo_access;	// From erx_disty of erx_disty.v
   wire [PW-1:0]	rxrr_fifo_packet;	// From erx_disty of erx_disty.v
   wire			rxrr_fifo_wait;		// From rxrr_fifo of fifo_async.v
   wire			rxwr_fifo_access;	// From erx_disty of erx_disty.v
   wire [PW-1:0]	rxwr_fifo_packet;	// From erx_disty of erx_disty.v
   wire			rxwr_fifo_wait;		// From rxwr_fifo of fifo_async.v
   // End of automatics

   //regs
   reg [15:0] 	ecfg_rx_debug;
   wire 	emrq_full;
   wire 	emwr_full;
   wire 	emrr_full;

   /************************************************************/
   /* ERX CONFIGURATION                                        */
   /************************************************************/
   ecfg_rx ecfg_rx (.mi_dout	        (mi_rx_cfg_dout[31:0]),
		     /*AUTOINST*/
		    // Outputs
		    .ecfg_rx_enable	(ecfg_rx_enable),
		    .ecfg_rx_mmu_enable	(ecfg_rx_mmu_enable),
		    // Inputs
		    .reset		(reset),
		    .mi_clk		(mi_clk),
		    .mi_en		(mi_en),
		    .mi_we		(mi_we),
		    .mi_addr		(mi_addr[19:0]),
		    .mi_din		(mi_din[31:0]),
		    .ecfg_rx_datain	(ecfg_rx_datain[8:0]),
		    .ecfg_rx_debug	(ecfg_rx_debug[15:0]));
    
   
   /************************************************************/
   /*FIFOs                                                     */
   /*(for AXI 1. read request, 2. write, and 3. read response) */
   /************************************************************/

   /*fifo_async   AUTO_TEMPLATE ( 
 			       // Outputs
			       
			       .dout       (@"(substring vl-cell-name  0 4)"_packet[PW-1:0]),
			       .empty	   (@"(substring vl-cell-name  0 4)"_empty),
			       .full	   (@"(substring vl-cell-name  0 4)"_fifo_full),
			       .prog_full  (@"(substring vl-cell-name  0 4)"_fifo_wait),
			       // Inputs
			       .rd_clk	   (@"(substring vl-cell-name  0 4)"_clk),
                               .wr_clk	   (rx_lclk_div4),
                               .wr_en      (@"(substring vl-cell-name  0 4)"_fifo_access),
                               .rd_en      (~@"(substring vl-cell-name  0 4)"_wait),
			       .reset	   (reset),
                               .din	   (@"(substring vl-cell-name  0 4)"_fifo_packet[PW-1:0]),
    );
   */
   
   assign rxrd_access=~rxrd_empty;
      
   //Read request fifo (from Epiphany)
   fifo_async #(.DW(104), .AW(5)) 
   rxrd_fifo   (.full			(rxrd_fifo_full),
		.empty			(rxrd_empty),
		/*AUTOINST*/
		// Outputs
		.prog_full		(rxrd_fifo_wait),	 // Templated
		.dout			(rxrd_packet[PW-1:0]),	 // Templated
		// Inputs
		.reset			(reset),		 // Templated
		.wr_clk			(rx_lclk_div4),		 // Templated
		.rd_clk			(rxrd_clk),		 // Templated
		.wr_en			(rxrd_fifo_access),	 // Templated
		.din			(rxrd_fifo_packet[PW-1:0]), // Templated
		.rd_en			(~rxrd_wait));		 // Templated

   assign rxwr_access=~rxwr_empty;

   //Write fifo (from Epiphany)
   fifo_async #(.DW(104), .AW(5)) 
   rxwr_fifo(.full			(rxwr_fifo_full),
	     .empty			(rxwr_empty),
	     /*AUTOINST*/
	     // Outputs
	     .prog_full			(rxwr_fifo_wait),	 // Templated
	     .dout			(rxwr_packet[PW-1:0]),	 // Templated
	     // Inputs
	     .reset			(reset),		 // Templated
	     .wr_clk			(rx_lclk_div4),		 // Templated
	     .rd_clk			(rxwr_clk),		 // Templated
	     .wr_en			(rxwr_fifo_access),	 // Templated
	     .din			(rxwr_fifo_packet[PW-1:0]), // Templated
	     .rd_en			(~rxwr_wait));		 // Templated
   
   assign rxrr_access=~rxrr_empty;

   //Read response fifo (for host)
   fifo_async #(.DW(104), .AW(5))  
   rxrr_fifo(.full			(rxrr_fifo_full),
	     .empty			(rxrr_empty),
	     /*AUTOINST*/
	     // Outputs
	     .prog_full			(rxrr_fifo_wait),	 // Templated
	     .dout			(rxrr_packet[PW-1:0]),	 // Templated
	     // Inputs
	     .reset			(reset),		 // Templated
	     .wr_clk			(rx_lclk_div4),		 // Templated
	     .rd_clk			(rxrr_clk),		 // Templated
	     .wr_en			(rxrr_fifo_access),	 // Templated
	     .din			(rxrr_fifo_packet[PW-1:0]), // Templated
	     .rd_en			(~rxrr_wait));		 // Templated
   
   
   /***********************************************************/
   /*GENERAL PURPOSE MAILBOX                                  */
   /***********************************************************/
   /*emailbox AUTO_TEMPLATE ( 
	                .mi_dout    (mi_rx_mailbox_dout[]),
                      );
   */
   
   emailbox emailbox(.clk		(s_axi_aclk),
		     /*AUTOINST*/
		     // Outputs
		     .mi_dout		(mi_rx_mailbox_dout[DW-1:0]), // Templated
		     .mailbox_full	(mailbox_full),
		     .mailbox_not_empty	(mailbox_not_empty),
		     // Inputs
		     .reset		(reset),
		     .mi_en		(mi_en),
		     .mi_we		(mi_we),
		     .mi_addr		(mi_addr[19:0]),
		     .mi_din		(mi_din[DW-1:0]));



   /************************************************************/
   /*ELINK RECEIVE DISTRIBUTOR ("DEMUX")                       */
   /*(figures out who RX transaction belongs to)               */
   /********************1***************************************/
   /*erx_disty AUTO_TEMPLATE ( 
                        //Inputs
                        .mmu_en		(ecfg_rx_mmu_enable),
                        .clk		(rx_lclk_div4),
    )
    */
   
   erx_disty erx_disty (
			/*AUTOINST*/
			// Outputs
			.rx_rd_wait	(rx_rd_wait),
			.rx_wr_wait	(rx_wr_wait),
			.edma_wait	(edma_wait),
			.rxwr_fifo_access(rxwr_fifo_access),
			.rxwr_fifo_packet(rxwr_fifo_packet[PW-1:0]),
			.rxrd_fifo_access(rxrd_fifo_access),
			.rxrd_fifo_packet(rxrd_fifo_packet[PW-1:0]),
			.rxrr_fifo_access(rxrr_fifo_access),
			.rxrr_fifo_packet(rxrr_fifo_packet[PW-1:0]),
			// Inputs
			.clk		(rx_lclk_div4),		 // Templated
			.mmu_en		(ecfg_rx_mmu_enable),	 // Templated
			.emmu_access	(emmu_access),
			.emmu_packet	(emmu_packet[PW-1:0]),
			.edma_access	(edma_access),
			.edma_packet	(edma_packet[PW-1:0]),
			.rxwr_fifo_wait	(rxwr_fifo_wait),
			.rxrd_fifo_wait	(rxrd_fifo_wait),
			.rxrr_fifo_wait	(rxrr_fifo_wait));


   /************************************************************/
   /*ELINK DMA                                                 */
   /************************************************************/
   
   /*edma AUTO_TEMPLATE (.clk		(rx_lclk_div4),
                         .edma_access	(edma_access),   
                         .mi_dout       (mi_rx_edma_dout[DW-1:0]),
                         .edma_access	(edma_access),
                         .edma_write	(edma_packet[1]),
	                 .edma_datamode	(edma_packet[3:2]),
	                 .edma_ctrlmode	(edma_packet[7:4]),
	                 .edma_dstaddr	(edma_packet[39:8]),
	                 .edma_data	(edma_packet[71:40]),
	                 .edma_srcaddr	(edma_packet[103:72]),
                               );
   */

   edma edma(/*AUTOINST*/
	     // Outputs
	     .mi_dout			(mi_rx_edma_dout[DW-1:0]), // Templated
	     .edma_access		(edma_access),		 // Templated
	     .edma_write		(edma_packet[1]),	 // Templated
	     .edma_datamode		(edma_packet[3:2]),	 // Templated
	     .edma_ctrlmode		(edma_packet[7:4]),	 // Templated
	     .edma_dstaddr		(edma_packet[39:8]),	 // Templated
	     .edma_data			(edma_packet[71:40]),	 // Templated
	     .edma_srcaddr		(edma_packet[103:72]),	 // Templated
	     // Inputs
	     .reset			(reset),
	     .clk			(rx_lclk_div4),		 // Templated
	     .mi_en			(mi_en),
	     .mi_we			(mi_we),
	     .mi_addr			(mi_addr[19:0]),
	     .mi_din			(mi_din[31:0]),
	     .edma_wait			(edma_wait));
   
           
   /************************************************************/
   /*ELINK MEMORY MANAGEMENT UNIT                              */
   /************************************************************/
   /*emmu AUTO_TEMPLATE ( 
                        .emmu_packet_out	(emmu_packet[PW-1:0]),
                        .emmu_\(.*\)_out	(emmu_\1[]),   
                         //Inputs
                        .emesh_\(.*\)_in	(erx_\1[]),   
                        .mmu_en			(ecfg_rx_mmu_enable),
                        .clk			(rx_lclk_div4),
                        .mi_dout   	        (mi_rx_emmu_dout[DW-1:0]),
                           );
   */

   emmu emmu (.emmu_packet_hi_out	(),
	      /*AUTOINST*/
	      // Outputs
	      .mi_dout			(mi_rx_emmu_dout[DW-1:0]), // Templated
	      .emmu_access_out		(emmu_access),		 // Templated
	      .emmu_packet_out		(emmu_packet[PW-1:0]),	 // Templated
	      // Inputs
	      .clk			(rx_lclk_div4),		 // Templated
	      .reset			(reset),
	      .mmu_en			(ecfg_rx_mmu_enable),	 // Templated
	      .mi_clk			(mi_clk),
	      .mi_en			(mi_en),
	      .mi_we			(mi_we),
	      .mi_addr			(mi_addr[15:0]),
	      .mi_din			(mi_din[DW-1:0]),
	      .emesh_access_in		(erx_access),		 // Templated
	      .emesh_packet_in		(erx_packet[PW-1:0]));	 // Templated
   

   /**************************************************************/
   /*ELINK PROTOCOL LOGIC                                        */
   /**************************************************************/
   
   erx_protocol erx_protocol (/*AUTOINST*/
			      // Outputs
			      .erx_access	(erx_access),
			      .erx_packet	(erx_packet[PW-1:0]),
			      // Inputs
			      .reset		(reset),
			      .ecfg_rx_enable	(ecfg_rx_enable),
			      .rx_lclk_div4	(rx_lclk_div4),
			      .rx_frame_par	(rx_frame_par[7:0]),
			      .rx_data_par	(rx_data_par[63:0]));

   
   /***********************************************************/
   /*ELINK TRANSMIT I/O LOGIC                                 */
   /***********************************************************/

   erx_io erx_io (
		    /*AUTOINST*/
		  // Outputs
		  .rxo_wr_wait_p	(rxo_wr_wait_p),
		  .rxo_wr_wait_n	(rxo_wr_wait_n),
		  .rxo_rd_wait_p	(rxo_rd_wait_p),
		  .rxo_rd_wait_n	(rxo_rd_wait_n),
		  .rx_lclk_div4		(rx_lclk_div4),
		  .rx_frame_par		(rx_frame_par[7:0]),
		  .rx_data_par		(rx_data_par[63:0]),
		  .ecfg_rx_datain	(ecfg_rx_datain[8:0]),
		  // Inputs
		  .reset		(reset),
		  .rxi_lclk_p		(rxi_lclk_p),
		  .rxi_lclk_n		(rxi_lclk_n),
		  .rxi_frame_p		(rxi_frame_p),
		  .rxi_frame_n		(rxi_frame_n),
		  .rxi_data_p		(rxi_data_p[7:0]),
		  .rxi_data_n		(rxi_data_n[7:0]),
		  .rx_wr_wait		(rx_wr_wait),
		  .rx_rd_wait		(rx_rd_wait));

   /************************************************************/
   /*Debug signals                                             */
   /************************************************************/
   always @ (posedge rx_lclk_div4)
     begin
	ecfg_rx_debug[15:0] <= {2'b0,                     //15:14
				rx_rd_wait,               //13
				rx_wr_wait,               //12
				rxrr_wait,                //11
				rxrr_fifo_wait,           //10
				rxrr_fifo_access,         //9			
				rxrd_wait,                //8
				rxrd_fifo_wait,           //7
				rxrd_fifo_access,         //6		 
				rxwr_wait,                //5
				rxwr_fifo_wait,           //4
				rxwr_fifo_access,         //3
				rxrr_fifo_full,           //2
				rxrd_fifo_full,           //1
				rxwr_fifo_full	          //0	
				};
     end

   
endmodule // erx
// Local Variables:
// verilog-library-directories:("." "../../emmu/hdl" "../../edma/hdl" "../../memory/hdl" "../../emailbox/hdl")
// End:

/*
 Copyright (C) 2014 Adapteva, Inc.
  
 Contributed by Andreas Olofsson <andreas@adapteva.com>

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.This program is distributed in the hope 
 that it will be useful,but WITHOUT ANY WARRANTY; without even the implied 
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details. You should have received a copy 
 of the GNU General Public License along with this program (see the file 
 COPYING).  If not, see <http://www.gnu.org/licenses/>.
 */


`timescale 1ns/1ps
// Experimental C128 v0. Public fixture lifecycle is not the framed G1 host/reset path.
module g2_c128 #(parameter integer IMAGE_BYTES=128)(
 input wire clk, clear_execution, stop,
 input wire begin_load,image_we,input wire [7:0] image_address,image_data,
 input wire seal,tx_we,input wire [3:0] tx_address,input wire [7:0] tx_data,
 input wire arm,input wire [4:0] arm_tx_count,arm_rx_capacity,
 input wire start,input wire [3:0] entry_row,
 input wire [7:0] initial_value,initial_oe,drive_allow,open_drain,observed_pins,
 input wire rx_re,input wire [3:0] rx_read_address,
 output wire [7:0] rx_read_data,output wire rx_read_valid,
 output wire [7:0] pin_value,pin_oe,
 output reg running,done,fault,output reg [7:0] reason,
 output wire [4:0] consumed_tx,rx_count,output reg [20:0] run_ticks,
 output wire reject_now,fire
);
 reg armed;
 reg [4:0] armed_rx_capacity;
 reg [7:0] pc;
 reg [20:0] E,D,L;
 reg due_valid,limit_valid;
 reg [18:0] gate_wait_limit;
 reg wait_busy_reason,F;
 reg [7:0] CMask,CValue;
 reg [4:0] L0,L1;
 reg [13:0] wait_count;
 reg wait_seen;
 reg [20:0] B,O;
 reg [4:0] remaining;
 reg phase,gate_seen,started;
 reg [2:0] byte_step;
 wire [21:0] Now={1'b0,run_ticks}+22'd1;
 wire held_valid,executable_valid,loading,busy,response_valid;
 wire [127:0] held_record;
 wire [8:0] loaded_count;
 wire [4:0] issued_count,assembled_count;
 wire [3:0] response_lane,assemble_lane;
 wire [7:0] read_address;
 wire read_issued,assemble_event,fetch_accepted,consume_accepted,fetch_error;
 wire fetch_reject,request_ready;
 wire [3:0] kind=held_record[127:124];
 wire [3:0] next_row=held_record[123:120],alt_row=held_record[119:116];
 wire [4:0] op=held_record[115:111];
 wire stamp=held_record[110];
 wire [19:0] arg=held_record[109:90];
 wire [7:0] shift_data,tx_response_data,rx_pending_data;
 wire driven,shift_valid,collect,tx_response_valid,tx_pending,rx_pending_valid;
 wire [3:0] nbit,tx_pending_addr,rx_pending_addr;
 wire [4:0] initialized_tx_count,rx_capacity;
 wire proposed_driven,data_illegal,data_tx_empty,data_rx_full,data_fault;
 wire [7:0] data_reason;
 wire data_fire,tx_response_fire,rx_commit_fire;
 wire [7:0] gvalue,goe,allow_q,od_q,proposed_value,proposed_oe;
 wire [2:0] route_pin;
 wire [1:0] route_mode;
 wire route_active,pin_illegal,pin_policy,pin_fault,pin_fire;
 wire [7:0] pin_reason;
 wire scalar_illegal,scalar_bounds,timer_bypass,is_wait,is_end,is_fault;
 wire condition_value,scalar_shift_bit;
 wire [5:0] scalar_next,branch_row,successor_row;
 reg static_illegal,static_bounds,dynamic_illegal;
 reg action_intent,retire_intent,activation,entering,transition,phase_finish;
 reg gate_predicate,gate_recognize,gate_expired,phase_missed;
 reg phase_select;
 reg [47:0] selected_phase;
 reg [21:0] selected_origin,selected_entry;
 reg [21:0] old_origin;
 reg old_gate_open,selected_gate_open;
 reg [7:0] successor;
 reg load_literal,tx_request,tx_load,serial_drive,serial_shift,rx_push,serial_drop;
 reg serial_dir,serial_bit,load_collect;
 reg [7:0] literal_data;
 reg gpio_write,gpio_value,gpio_oe,profile_write,profile_active;
 reg [2:0] gpio_pin,profile_pin;
 reg [1:0] profile_mode,route_cmd;
 reg phase_capture,phase_capture_bit,stamp_event;
 reg wait_success;
 reg [21:0] timer_target;
 reg [7:0] independent_reason,reject_reason;
 reg [2:0] next_byte_step;
 wire [3:0] command_count={3'd0,begin_load}+{3'd0,image_we}+{3'd0,seal}
     +{3'd0,tx_we}+{3'd0,arm}+{3'd0,start};
 wire start_policy_bad=(((initial_value|initial_oe|open_drain)&~drive_allow)!=0)
     ||((initial_value&open_drain)!=0);
 wire host_illegal=(command_count>1)||((command_count!=0)&&running)||(running&&rx_re)
     ||(image_we&&!loading)||(seal&&!loading)
     ||((start||arm)&&(fault||reason==8'h03))
     ||(tx_we&&(!loading||armed||initialized_tx_count>=16||{1'b0,tx_address}!=initialized_tx_count))
     ||(arm&&(!executable_valid||arm_tx_count!=initialized_tx_count||arm_tx_count>16||arm_rx_capacity>16))
     ||(start&&(!executable_valid||!armed));
 wire start_bounds=start&&(({1'b0,entry_row,4'b0}+9'd16)>loaded_count);
 wire start_accept=start&&!running&&!host_illegal&&!start_bounds&&!start_policy_bad&&!stop&&!clear_execution;
 wire accepted_begin_load=begin_load&&!running&&(command_count==1)&&!stop&&!clear_execution;
 wire end_intent=running&&held_valid&&(kind==0)&&is_end&&action_intent;
 wire independent_fault=(independent_reason!=0);
 wire external_cancel=stop||independent_fault||end_intent;
 wire global_veto=clear_execution||stop||reject_now||end_intent;
 wire terminal_cancel=stop||reject_now||end_intent;
 wire fetch_request=running&&!busy&&!response_valid&&!held_valid;
 wire consume_record=running&&retire_intent;
 wire eligible=running&&held_valid&&(!due_valid||timer_bypass&&kind==0||Now=={1'b0,D});
 assign reject_now=!clear_execution&&(reject_reason!=0);
 assign fire=running&&action_intent&&!clear_execution&&!stop&&!reject_now;

 function automatic cond_value;
 input [4:0] code;
 begin
  case(code)
   0:cond_value=0;1:cond_value=1;
   2,3,4,5,6,7,8,9:cond_value=observed_pins[code-2];
   10:cond_value=F;11:cond_value=(L0==0);12:cond_value=(L1==0);
   13:cond_value=(consumed_tx<initialized_tx_count);14:cond_value=(rx_count<rx_capacity);
   15:cond_value=((observed_pins&CMask)==CValue);
   16:cond_value=(L0==1);17:cond_value=(L1==1);18:cond_value=(nbit==8)&&collect;
   default:cond_value=1'bx;
  endcase
 end
 endfunction
 function automatic source_value;
 input [3:0] code;
 begin
  case(code)
   0:source_value=0;1:source_value=1;
   2,3,4,5,6,7,8,9:source_value=observed_pins[code-2];
   10:source_value=F;default:source_value=1'bx;
  endcase
 end
 endfunction
 function automatic phase_bad;
 input [47:0] p;
 begin
  phase_bad=(p[47:32]==0)||(p[1:0]!=0)||(p[10:8]>4)||(p[3:2]==3)
    ||(p[10:8]==0&&p[7])||(p[23:16]==255&&p[6:5]!=0)
    ||(p[31:24]!=255&&{8'd0,p[31:24]}>=p[47:32])
    ||(p[23:16]!=255&&{8'd0,p[23:16]}>=p[47:32]);
 end
 endfunction
 function automatic phase_gate;
 input [47:0] p;
 reg tail;
 begin
  tail=cond_value(held_record[106:102])^held_record[101];
  case(p[10:8])
   0:phase_gate=1;1:phase_gate=!observed_pins[p[15:13]];
   2:phase_gate=observed_pins[p[15:13]];3:phase_gate=tail;4:phase_gate=!tail;
   default:phase_gate=1'bx;
  endcase
 end
 endfunction

 g2_record_fetch #(.STORE_BYTES(IMAGE_BYTES),.RECORD_BYTES(16)) fetch_unit(
  .clk(clk),.clear_control(clear_execution),.execution_active(running),
  .begin_load(begin_load),.write_enable(image_we),.write_address(image_address),
  .write_data(image_data),.seal(seal),.fetch_request(fetch_request),.fetch_address(pc),
  .consume_record(consume_record),.cancel(external_cancel),.request_ready(request_ready),
  .reject_now(fetch_reject),.fetch_accepted(fetch_accepted),.consume_accepted(consume_accepted),
  .error(fetch_error),.record_valid(held_valid),.record_data(held_record),
  .executable_valid(executable_valid),.loading(loading),.loaded_count(loaded_count),
  .busy(busy),.issued_count(issued_count),.assembled_count(assembled_count),
  .response_valid(response_valid),.response_lane(response_lane),.read_issued(read_issued),
  .read_address(read_address),.assemble_event(assemble_event),.assemble_lane(assemble_lane));
 g2_ac_scalar_decode #(.C_SCALAR(1),.STORE_BYTES(IMAGE_BYTES)) scalar_decode(
  .op(op),.arg(arg),.stamp(stamp),.next_row({2'b0,next_row}),.alt_row(alt_row),
  .committed_bytes(loaded_count),.observed(observed_pins),.flag(F),.loop0(L0),.loop1(L1),
  .cmask(CMask),.cvalue(CValue),.tx_consumed(consumed_tx),.tx_initialized(initialized_tx_count),
  .rx_count(rx_count),.rx_capacity(rx_capacity),.nbit(nbit),.collect(collect),
  .static_illegal(scalar_illegal),.static_bounds(scalar_bounds),.is_timer_bypass(timer_bypass),
  .is_wait(is_wait),.is_end(is_end),.is_programmed_fault(is_fault),
  .condition_value(condition_value),.shift_bit(scalar_shift_bit),.next_row_wire(scalar_next),
  .branch_row(branch_row),.successor_row(successor_row));
 g2_ac_serial_payload data_unit(
  .clk(clk),.clear(clear_execution||accepted_begin_load),.run_start(start_accept),.cancel(terminal_cancel),
  .running(running),.action_accept(fire),.global_veto(global_veto),
  .tx_begin(begin_load),.tx_we(tx_we),.tx_addr(tx_address),.tx_data(tx_data),
  .start_tx_count(initialized_tx_count),.start_rx_capacity(armed_rx_capacity),
  .rx_re(rx_re),.rx_addr(rx_read_address),.rx_read_valid(rx_read_valid),.rx_read_data(rx_read_data),
  .load_literal(load_literal),.tx_req(tx_request),.tx_load(tx_load),.drive(serial_drive),
  .shift(serial_shift),.rx_push(rx_push),.drop(serial_drop),.dir(serial_dir),.bit_in(serial_bit),
  .load_collect(load_collect),.literal_data(literal_data),.shift_data(shift_data),
  .driven(driven),.shift_valid(shift_valid),.nbit(nbit),.collect(collect),
  .initialized_tx_count(initialized_tx_count),.consumed(consumed_tx),.rx_capacity(rx_capacity),
  .rx_count(rx_count),.tx_response_data(tx_response_data),.tx_response_valid(tx_response_valid),
  .tx_pending(tx_pending),.tx_pending_addr(tx_pending_addr),.rx_pending_data(rx_pending_data),
  .rx_pending_valid(rx_pending_valid),.rx_pending_addr(rx_pending_addr),.proposed_driven(proposed_driven),
  .raw_illegal(data_illegal),.raw_tx_empty(data_tx_empty),.raw_rx_full(data_rx_full),
  .raw_fault(data_fault),.raw_reason(data_reason),.action_fire(data_fire),
  .tx_response_fire(tx_response_fire),.rx_commit_fire(rx_commit_fire));
 g2_ac_pins pin_unit(
  .clk(clk),.clear(clear_execution),.run_start(start_accept),.cancel(terminal_cancel),
  .running(running),.action_accept(fire),.global_veto(global_veto),
  .start_allow(drive_allow),.start_od(open_drain),.start_value(initial_value),.start_oe(initial_oe),
  .gpio_write(gpio_write),.gpio_pin(gpio_pin),.gpio_value(gpio_value),.gpio_oe(gpio_oe),
  .profile_write(profile_write),.profile_pin(profile_pin),.profile_mode(profile_mode),
  .profile_active(profile_active),.route_cmd(route_cmd),.serial_drive(serial_drive),
  .proposed_driven(proposed_driven),.driven(driven),.gvalue(gvalue),.goe(goe),
  .drive_allow(allow_q),.open_drain(od_q),.route_pin(route_pin),.route_mode(route_mode),
  .route_active(route_active),.requested_value(pin_value),.requested_oe(pin_oe),
  .proposed_value(proposed_value),.proposed_oe(proposed_oe),.raw_illegal(pin_illegal),
  .raw_policy(pin_policy),.raw_fault(pin_fault),.raw_reason(pin_reason),.action_fire(pin_fire));

 always @* begin
  static_illegal=0;static_bounds=0;
  if(running&&held_valid) begin
   static_bounds=({1'b0,next_row,4'b0}+9'd16>loaded_count)
                ||({1'b0,alt_row,4'b0}+9'd16>loaded_count);
   case(kind)
    0:begin static_illegal=scalar_illegal||(|held_record[89:0]);static_bounds=static_bounds||scalar_bounds;end
    1:static_illegal=phase_bad(held_record[95:48])||phase_bad(held_record[47:0])
       ||held_record[110:107]>10||held_record[106:102]>18;
    2:static_illegal=(|held_record[101:0])||(alt_row!=next_row)
       ||held_record[114:113]==3||(!held_record[115]&&held_record[114:113]==0)
       ||(held_record[111]&&held_record[114:113]==0)
       ||(held_record[114:113]!=2&&held_record[109:102]!=0)
       ||(held_record[114:113]==0&&held_record[112])
       ||(!held_record[111]&&held_record[110]);
    default:static_illegal=1;
   endcase
  end
 end

 always @* begin
  action_intent=0;retire_intent=0;activation=0;entering=0;transition=0;phase_finish=0;
  gate_predicate=0;gate_recognize=0;gate_expired=0;phase_missed=0;
  phase_select=phase;selected_phase=phase?held_record[47:0]:held_record[95:48];
  selected_origin={1'b0,O};selected_entry={1'b0,B};old_origin={1'b0,O};
  old_gate_open=0;selected_gate_open=0;
  successor={next_row,4'b0};dynamic_illegal=0;
  load_literal=0;tx_request=0;tx_load=0;serial_drive=0;serial_shift=0;rx_push=0;serial_drop=0;
  serial_dir=0;serial_bit=0;load_collect=0;literal_data=0;
  gpio_write=0;gpio_pin=0;gpio_value=0;gpio_oe=0;
  profile_write=0;profile_pin=0;profile_mode=0;profile_active=0;route_cmd=0;
  phase_capture=0;phase_capture_bit=0;stamp_event=0;
  wait_success=0;timer_target={2'b0,arg};next_byte_step=byte_step;
  if(running&&held_valid) begin
   if(kind==0&&eligible) begin
    successor={successor_row[3:0],4'b0};
    action_intent=1;retire_intent=1;
    case(op)
     5'h01:begin gpio_write=1;gpio_pin=arg[2:0];gpio_value=arg[3];gpio_oe=arg[4];end
     5'h02:begin profile_write=1;profile_pin=arg[2:0];profile_mode=arg[4:3];profile_active=arg[5];end
     5'h03:begin load_literal=1;literal_data=arg[7:0];load_collect=arg[8];end
     5'h04:tx_request=1;
     5'h05:begin tx_load=1;load_collect=arg[0];end
     5'h06:begin serial_drive=1;serial_dir=arg[0];end
     5'h07:begin serial_shift=1;serial_dir=arg[4];serial_bit=scalar_shift_bit;end
     5'h08:rx_push=1;
     5'h09:serial_drop=1;
     5'h0d:dynamic_illegal=(arg[0]?L1:L0)==0;
     5'h0f,5'h10,5'h11,5'h12:begin
      if(op==5'h10||op==5'h12) timer_target={1'b0,E}+{2'b0,arg};
      dynamic_illegal=(timer_target<=Now)||(timer_target>=22'd2000000)
        ||((op==5'h0f||op==5'h10)&&due_valid);
     end
     5'h14:begin
      dynamic_illegal=!limit_valid||due_valid;
      wait_success=condition_value&&(!wait_seen?(arg[19:6]==0):(wait_count>=arg[19:6]-1'b1));
      retire_intent=wait_success;
     end
     5'h17:dynamic_illegal=limit_valid&&(arg[0]!=wait_busy_reason);
     default:begin end
    endcase
   end else if(kind==1) begin
    activation=!started&&eligible;
    if(started) begin
     gate_predicate=phase_gate(selected_phase);
     gate_recognize=!gate_seen&&(selected_phase[10:8]!=0)&&gate_predicate;
     stamp_event=selected_phase[4]&&gate_recognize;
     old_gate_open=(selected_phase[10:8]==0)||gate_seen||gate_recognize;
     if(!gate_seen&&selected_phase[10:8]!=0) begin
      gate_expired=Now>=({1'b0,B}+{3'b0,gate_wait_limit});
      if(selected_phase[7]&&gate_recognize) old_origin=Now;
      if(!selected_phase[7]) begin
       phase_missed=((selected_phase[31:24]!=255)&&Now>({1'b0,B}+{14'd0,selected_phase[31:24]}))
        ||((selected_phase[23:16]!=255)&&Now>({1'b0,B}+{14'd0,selected_phase[23:16]}))
        ||(Now>({1'b0,B}+{6'd0,selected_phase[47:32]}));
      end
     end
     phase_finish=old_gate_open&&(Now==(old_origin+{6'd0,selected_phase[47:32]}));
     if(phase_finish) begin
      if(phase&&remaining==1) begin
       action_intent=1;retire_intent=1;
       successor={(cond_value(held_record[106:102])^held_record[101])?alt_row:next_row,4'b0};
       gpio_pin=held_record[100:98];
       if(held_record[97:96]!=0) begin
        gpio_write=1;gpio_value=(held_record[97:96]==2);gpio_oe=(held_record[97:96]!=3);
       end
      end else begin transition=1;entering=1;phase_select=!phase;end
     end
    end
    if(activation) begin entering=1;phase_select=0;end
    if(entering) begin
     selected_phase=phase_select?held_record[47:0]:held_record[95:48];
     selected_entry=Now;selected_origin=Now;
     selected_gate_open=selected_phase[10:8]==0;
     gpio_pin=selected_phase[15:13];route_cmd=selected_phase[3:2];
     if(selected_phase[12:11]!=0) begin
      gpio_write=1;gpio_value=selected_phase[12:11]==2;gpio_oe=selected_phase[12:11]!=3;
     end
     if(selected_phase[10:8]!=0) dynamic_illegal=(gate_wait_limit==0)
       ||((Now+{3'b0,gate_wait_limit})>=22'd2097152);
     stamp_event=stamp_event||(selected_phase[4]&&(selected_phase[10:8]==0));
     action_intent=1;
    end else if(started&&!phase_finish) begin
     selected_origin=old_origin;selected_gate_open=old_gate_open;
     stamp_event=selected_phase[4]&&gate_recognize;
     action_intent=1;
    end
    if(action_intent&&!retire_intent&&selected_gate_open) begin
     serial_dir=held_record[111];
     serial_drive=(selected_phase[31:24]!=255)&&(Now==selected_origin+{14'd0,selected_phase[31:24]});
     if((selected_phase[23:16]!=255)&&(Now==selected_origin+{14'd0,selected_phase[23:16]})) begin
      phase_capture_bit=source_value(held_record[110:107]);
      if(selected_phase[6:5]==3) phase_capture=1;
      else begin
       serial_shift=1;
       serial_bit=(selected_phase[6:5]==1)?1'b0:(selected_phase[6:5]==2)?1'b1:phase_capture_bit;
      end
     end
    end
   end else if(kind==2&&(started||eligible)) begin
    action_intent=1;activation=!started;
    serial_dir=held_record[110];load_collect=held_record[112];literal_data=held_record[109:102];
    if(!started) begin
     if(held_record[115]) begin rx_push=1;next_byte_step=1;end
     else if(held_record[114:113]==1) begin tx_request=1;next_byte_step=3;end
     else begin load_literal=1;next_byte_step=held_record[111]?5:6;end
    end else case(byte_step)
     1:next_byte_step=2;
     2:begin
      if(rx_pending_valid||collect) dynamic_illegal=1;
      if(held_record[114:113]==0) retire_intent=1;
      else if(held_record[114:113]==1) begin tx_request=1;next_byte_step=3;end
      else begin load_literal=1;next_byte_step=held_record[111]?5:6;end
     end
     3:next_byte_step=4;
     4:begin tx_load=1;next_byte_step=held_record[111]?5:6;end
     5:begin serial_drive=1;next_byte_step=6;end
     6:retire_intent=1;
     default:dynamic_illegal=1;
    endcase
   end
  end
 end

 always @* begin
  // Descending assignment gives the specified minimum hexadecimal reason.
  independent_reason=0;
  if(data_rx_full) independent_reason=8'h17;
  if(data_tx_empty) independent_reason=8'h16;
  if(pin_policy||start&&start_policy_bad) independent_reason=8'h15;
  if(start_bounds||static_bounds) independent_reason=8'h14;
  if(host_illegal||static_illegal||dynamic_illegal||data_illegal||pin_illegal
      ||(running&&due_valid&&Now>{1'b0,D})
      ||(running&&held_valid&&kind==0&&is_wait&&due_valid)||phase_missed) independent_reason=8'h13;
  if(running&&held_valid&&kind==0&&eligible&&is_fault&&!static_illegal) begin
   if(independent_reason==0||arg[7:0]<independent_reason) independent_reason=arg[7:0];
  end
  if(running&&((limit_valid&&Now>={1'b0,L})||gate_expired))
   if(independent_reason==0||(wait_busy_reason?8'h12:8'h11)<independent_reason)
    independent_reason=wait_busy_reason?8'h12:8'h11;
  if(running&&Now>=22'd2000000) independent_reason=8'h10;
  reject_reason=independent_reason;
  if(fetch_reject&&(reject_reason==0||reject_reason>(running?8'h14:8'h13)))
   reject_reason=running?8'h14:8'h13;
 end

 always @(posedge clk) begin
  if(clear_execution) begin
   running<=0;done<=0;fault<=0;reason<=0;armed<=0;armed_rx_capacity<=0;
   run_ticks<=0;pc<=0;E<=0;D<=0;L<=0;due_valid<=0;limit_valid<=0;
   gate_wait_limit<=0;wait_busy_reason<=0;F<=0;CMask<=0;CValue<=0;L0<=0;L1<=0;
   wait_count<=0;wait_seen<=0;B<=0;O<=0;remaining<=0;phase<=0;gate_seen<=0;started<=0;byte_step<=0;
  end else begin
   if(running) run_ticks<=Now[20:0];
   if(stop) begin
    running<=0;armed<=0;due_valid<=0;limit_valid<=0;started<=0;wait_seen<=0;wait_count<=0;
    if(running||(!done&&!fault&&reason==0)) begin done<=0;fault<=0;reason<=8'h03;end
   end else if(reject_now) begin
    running<=0;armed<=0;due_valid<=0;limit_valid<=0;started<=0;wait_seen<=0;wait_count<=0;
    if(running||(!done&&!fault&&reason==0)) begin done<=0;fault<=1;reason<=reject_reason;end
   end else if(start_accept) begin
    running<=1;done<=0;fault<=0;reason<=0;armed<=0;run_ticks<=0;pc<={entry_row,4'b0};
    E<=0;D<=0;L<=0;due_valid<=0;limit_valid<=0;gate_wait_limit<=0;wait_busy_reason<=0;
    F<=0;CMask<=0;CValue<=0;L0<=0;L1<=0;wait_count<=0;wait_seen<=0;
    B<=0;O<=0;remaining<=0;phase<=0;gate_seen<=0;started<=0;byte_step<=0;
   end else if(!running) begin
    if(accepted_begin_load) begin armed<=0;done<=0;fault<=0;reason<=0;end
    if(arm) begin armed<=1;armed_rx_capacity<=arm_rx_capacity;end
   end else if(end_intent) begin
    running<=0;done<=1;fault<=0;reason<=arg[7:0];
    if(stamp) E<=Now[20:0];
    due_valid<=0;limit_valid<=0;started<=0;wait_count<=0;wait_seen<=0;
   end else if(fire) begin
    if(activation||kind==0&&!timer_bypass) due_valid<=0;
    if(kind==0) begin
     if(stamp&&op!=5'h14) E<=Now[20:0];
     case(op)
      5'h0a:F<=condition_value;
      5'h0b:begin CMask<=arg[7:0];CValue<=arg[15:8];end
      5'h0c:if(arg[0]) L1<=arg[5:1];else L0<=arg[5:1];
      5'h0d:if(arg[0]) L1<=L1-1'b1;else L0<=L0-1'b1;
      5'h0f,5'h10:begin D<=timer_target[20:0];due_valid<=1;end
      5'h11,5'h12:begin L<=timer_target[20:0];limit_valid<=1;end
      5'h13:begin if(arg[0])due_valid<=0;if(arg[1])limit_valid<=0;end
      5'h14:begin
       if(!condition_value) begin wait_seen<=0;wait_count<=0;end
       else if(!wait_seen) begin wait_seen<=1;wait_count<=0;if(stamp)E<=Now[20:0];end
       else if(!wait_success) wait_count<=wait_count+1'b1;
      end
      5'h15:begin running<=0;done<=1;fault<=0;reason<=arg[7:0];end
      5'h17:begin gate_wait_limit<=arg[19:1];wait_busy_reason<=arg[0];end
      default:begin end
     endcase
    end else if(kind==1) begin
     if(activation) remaining<={1'b0,held_record[115:112]}+1'b1;
     if(transition&&phase) remaining<=remaining-1'b1;
     if(entering) begin
      started<=1;phase<=phase_select;B<=Now[20:0];O<=Now[20:0];
      gate_seen<=selected_phase[10:8]==0;
     end else if(gate_recognize) begin
      gate_seen<=1;if(selected_phase[7]) O<=Now[20:0];
     end
     if(stamp_event) E<=Now[20:0];
     if(phase_capture) F<=phase_capture_bit;
    end else if(kind==2) begin started<=1;byte_step<=next_byte_step;end
    if(retire_intent) begin
     pc<=successor;started<=0;byte_step<=0;wait_count<=0;wait_seen<=0;
    end
   end
  end
 end
endmodule

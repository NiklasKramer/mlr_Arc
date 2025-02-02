-- mlr
-- v2.2.4 @tehn
-- llllllll.co/t/21145
-- adding support for Arc
--
-- /////////
-- ////
-- ////////////
-- //////////
-- ///////
-- /
-- ////
-- //
-- /////////
-- ///
-- /
--
-- ////
-- /
--
-- /
--
--
function rerun()
  norns.script.load(norns.state.script)
end
--
--ARC
alt_mode_active={false, false, false, false}
alt_mode_reverse= false

local g = grid.connect()
local a = arc.connect(1)

local encoder_loop_sens = 500
local encoder_scrub_sens = 200
local encoder_speed_sens = 100
local encoder_value_sens = 10

local fileselect = require 'fileselect'
local textentry = require 'textentry'
local pattern_time = require 'pattern_time'

local tau = math.pi * 2

local TRACKS = 6
local FADE = 0.1

-- softcut has ~350s per buffer
local CLIP_LEN_SEC = 45
local MAX_CLIPS = 7

local vREC = 1
local vCUT = 2
local vCLIP = 3
local vTIME = 15

-- events
local eCUT = 1
local eSTOP = 2
local eSTART = 3
local eLOOP = 4
local eSPEED = 5
local eREV = 6
local ePATTERN = 7

local quantize = 0

local quantizer

local function update_tempo()
  local t = params:get("clock_tempo")
  local d = params:get("quant_div")
  local interval = (60/t) / d
  print("q > "..interval)
  quantizer.time = interval
  for i=1,TRACKS do
    if track[i].tempo_map == 1 then
      update_rate(i)
    end
  end
end

local prev_tempo = params:get("clock_tempo")
function clock_update_tempo ()
  while true do
    clock.sync(1/24)
    local curr_tempo = params:get("clock_tempo")
    if prev_tempo ~= curr_tempo then
      prev_tempo = curr_tempo
      update_tempo()
    end
  end
end

function event_record(e)
  for i=1,4 do
    pattern[i]:watch(e)
  end
  recall_watch(e)
end


function event(e)
  if quantize == 1 then
    event_q(e)
  else
    if e.t ~= ePATTERN then event_record(e) end
    event_exec(e)
  end
end

local quantize_events = {}

function event_q(e)
  table.insert(quantize_events,e)
end

function event_q_clock()
  if #quantize_events > 0 then
    for k,e in pairs(quantize_events) do
      if e.t ~= ePATTERN then event_record(e) end
      event_exec(e)
    end
    quantize_events = {}
  end
end


function event_exec(e)
  if e.t==eCUT then
    if track[e.i].loop == 1 then
      track[e.i].loop = 0
      softcut.loop_start(e.i,clip[track[e.i].clip].s)
      softcut.loop_end(e.i,clip[track[e.i].clip].e)
    end
    local cut = (e.pos/16)*clip[track[e.i].clip].l + clip[track[e.i].clip].s
    softcut.position(e.i,cut)
    --softcut.reset(e.i)
    if track[e.i].play == 0 then
      track[e.i].play = 1
      ch_toggle(e.i,1)
    end
    local q = calc_quant(e.i)
    local off = calc_quant_off(e.i, q)
    set_phase_quant(e.i, q, e.i)
  elseif e.t==eSTOP then
    track[e.i].play = 0
    track[e.i].pos_grid = -1
    ch_toggle(e.i,0)
    dirtygrid=true
  elseif e.t==eSTART then
    track[e.i].play = 1
    ch_toggle(e.i,1)
    dirtygrid=true
  elseif e.t==eLOOP then
    track[e.i].loop = 1
    track[e.i].loop_start = e.loop_start
    track[e.i].loop_end = e.loop_end
    --print("LOOP "..track[e.i].loop_start.." "..track[e.i].loop_end)
    local lstart = clip[track[e.i].clip].s + (track[e.i].loop_start-1)/16*clip[track[e.i].clip].l
    local lend = clip[track[e.i].clip].s + (track[e.i].loop_end)/16*clip[track[e.i].clip].l
    --print(">>>> "..lstart.." "..lend)
    softcut.loop_start(e.i,lstart)
    softcut.loop_end(e.i,lend)
    if view == vCUT then dirtygrid=true end
  elseif e.t==eSPEED then
    track[e.i].speed = e.speed
    track[e.i].speed_no_normalize = e.speed
    update_rate(e.i)
    --n = math.pow(2,track[e.i].speed + params:get("speed_mod"..e.i))
    --if track[e.i].rev == 1 then n = -n end
    --engine.rate(e.i,n)
    if view == vREC then dirtygrid=true end
  elseif e.t==eREV then
    track[e.i].rev = e.rev
    track[e.i].rev_no_normalize = e.rev
    update_rate(e.i)
    --n = math.pow(2,track[e.i].speed + params:get("speed_mod"..e.i))
    --if track[e.i].rev == 1 then n = -n end
    --engine.rate(e.i,n)
    if view == vREC then dirtygrid=true end
  elseif e.t==ePATTERN then
    if e.action=="stop" then pattern[e.i]:stop()
    elseif e.action=="start" then pattern[e.i]:start()
    elseif e.action=="rec_stop" then pattern[e.i]:rec_stop()
    elseif e.action=="rec_start" then pattern[e.i]:rec_start()
    elseif e.action=="clear" then pattern[e.i]:clear()
    end
  end
  arc_redraw()
end


------ patterns
pattern = {}
for i=1,4 do
  pattern[i] = pattern_time.new()
  pattern[i].process = event_exec
end

------ recalls
recall = {}
for i=1,4 do
  recall[i] = {}
  recall[i].recording = false
  recall[i].has_data = false
  recall[i].active = false
  recall[i].event = {}
end

function recall_watch(e)
  for i=1,4 do
    if recall[i].recording == true then
      --print("recall: event rec")
      table.insert(recall[i].event, e)
      recall[i].has_data = true
    end
  end
end

function recall_exec(i)
  for _,e in pairs(recall[i].event) do
    event_exec(e)
  end
end

view = vREC
view_prev = view

v = {}
v.key = {}
v.enc = {}
v.redraw = {}
v.gridkey = {}
v.gridredraw = {}

viewinfo = {}
viewinfo[vREC] = 1
viewinfo[vCUT] = 0
viewinfo[vTIME] = 0

focus = 1
alt = 0

track = {}
for i=1,TRACKS do
  track[i] = {}
  track[i].head = (i-1)%4+1
  track[i].play = 0
  track[i].rec = 0
  track[i].rec_level = 1
  track[i].pre_level = 0
  track[i].loop = 0
  track[i].loop_start = 0
  track[i].loop_end = 16
  track[i].clip = i
  track[i].pos = 0
  track[i].pos_grid = -1
  track[i].speed = 0
  track[i].rev = 0
  track[i].tempo_map = 0
  track[i].pos_arc = 0
  track[i].speed_no_normalize = 0
  track[i].rev_no_normalize = 0
end


set_clip_length = function(i, len)
  clip[i].l = len
  clip[i].e = clip[i].s + len
  local bpm = 60 / len
  while bpm < 60 do
    bpm = bpm * 2
    print("bpm > "..bpm)
  end
  clip[i].bpm = bpm
end

clip_reset = function(i, length)
  set_clip_length(i, length)
  clip[i].name = "-"
end

clip = {}
for i=1,16 do
  clip[i] = {}
  clip[i].s = 2 + (i-1)*CLIP_LEN_SEC
  clip[i].name = "-"
  set_clip_length(i,4)
end



calc_quant = function(i)
  local q = (clip[track[i].clip].l/16)
  print("q > "..q)
  return q
end

calc_quant_off = function(i, q)
  local off = q
  while off < clip[track[i].clip].s do
    off = off + q
  end
  off = off - clip[track[i].clip].s
  print("off > "..off)
  return off
end

set_phase_quant = function(i,q, focus)
  if i==focus then
    softcut.phase_quant(i,0,0.001)
  else
    softcut.phase_quant(i,q)
  end
end


set_clip = function(i, x)
  print("setClip")
  --track[i].play = 0
  --ch_toggle(i,0)
  track[i].clip = x
  softcut.loop_start(i,clip[track[i].clip].s)
  softcut.loop_end(i,clip[track[i].clip].e)
  local q = calc_quant(i)
  local off = calc_quant_off(i, q)
  set_phase_quant(i, q, focus)
  softcut.phase_offset(i,off)

end

set_rec = function(n)
  if track[n].rec == 1 then
    softcut.pre_level(n,track[n].pre_level)
    softcut.rec_level(n,track[n].rec_level)
  else
    softcut.pre_level(n,1)
    softcut.rec_level(n,0)
  end
end

held = {}
heldmax = {}
done = {}
first = {}
second = {}
for i = 1,8 do
  held[i] = 0
  heldmax[i] = 0
  done[i] = 0
  first[i] = 0
  second[i] = 0
end


key = function(n,z) _key(n,z) end
enc = function(n,d)
  if n==1 then params:delta("output_level",d)
  else _enc(n,d) end
end
redraw = function() _redraw() end
g.key = function(x,y,z) _gridkey(x,y,z) end

set_view = function(x)
  --print("set view: "..x)
  if x == -1 then x = view_prev end
  view_prev = view
  view = x
  _key = v.key[x]
  _enc = v.enc[x]
  _redraw = v.redraw[x]
  _gridkey = v.gridkey[x]
  _gridredraw = v.gridredraw[x]
  redraw()
  dirtygrid=true
end

gridredraw = function()
  if not g then return end
  if dirtygrid == true then
    _gridredraw()
    dirtygrid = false
  end
end


function ch_toggle(i,x)
  softcut.play(i,x)
  softcut.rec(i,x)
end


UP1 = controlspec.new(0, 1, 'lin', 0, 1, "")
UP2 = controlspec.new(0, 20000, 'lin', 0, 20000, "")
UP0 = controlspec.new(0, 1, 'lin', 0, 0, "")
cs_PAN = controlspec.new(-1, 1, 'lin', 0, 0, "")
BI1 = controlspec.new(-1, 1, 'lin', 0, 0, "")

-------------------- init
init = function()
  params:set_action("clock_tempo", function() update_tempo() end)
  params:add_number("quant_div", "quant div", 1, 32, 4)
  params:set_action("quant_div",function() update_tempo() end)

  p = {}

	audio.level_cut(1)
	audio.level_adc_cut(1)

  for i=1,TRACKS do
    params:add_separator()

    softcut.enable(i,1)

  	softcut.level_input_cut(1, i, 1.0)
  	softcut.level_input_cut(2, i, 1.0)

    softcut.play(i,0)
    softcut.rec(i,0)

    softcut.level(i,1)
    softcut.pan(i,0)
    softcut.buffer(i,1)

    softcut.pre_level(i,1)
    softcut.rec_level(i,0)

    softcut.fade_time(i,FADE)
    softcut.level_slew_time(i,0.1)
    softcut.rate_slew_time(i,0)

    softcut.loop_start(i,clip[track[i].clip].s)
    softcut.loop_end(i,clip[track[i].clip].e)
    softcut.loop(i,1)
    softcut.position(i, clip[track[i].clip].s)

    params:add_control(i.."vol", i.."vol", UP1)
    params:set_action(i.."vol", function(x) softcut.level(i,x) end)
    params:add_control(i.."pan", i.."pan", cs_PAN)
    params:set_action(i.."pan", function(x) softcut.pan(i,x) end)
    params:add_control(i.."rec", i.."rec", UP1)
    params:set_action(i.."rec",
      function(x)
        track[i].rec_level = x
        set_rec(i)
      end)
    params:add_control(i.."pre", i.."pre", controlspec.UNIPOLAR)
    params:set_action(i.."pre",
      function(x)
        track[i].pre_level = x
        set_rec(i)
      end)
    params:add_control(i.."speed_mod", i.."speed_mod", controlspec.BIPOLAR)
    params:set_action(i.."speed_mod", function() update_rate(i) end)

    params:add_control(i.."rate_slew", i.."rate_slew", UP0)
    params:set_action(i.."rate_slew", function(x) softcut.rate_slew_time(i,x) end)

    params:add_control(i.."level_slew", i.."level_slew", controlspec.new(0.0,10.0,"lin",0.1,0.1,""))
    params:set_action(i.."level_slew", function(x) softcut.level_slew_time(i,x) end)
    params:add_file(i.."file", i.."file", "")
    params:set_action(i.."file",
      --function(n) print("FILESELECT > "..i.." "..n) end)
      function(n) fileselect_callback(n,i) end)

    update_rate(i)
    set_clip(i,i)
    --softcut.phase_quant(i,calc_quant(i))
  end

  quantizer = metro.init()
  quantizer.time = 0.125
  quantizer.count = -1
  quantizer.event = event_q_clock
  quantizer:start()
  --pattern_init()
  set_view(vREC)

  update_tempo()

  gridredrawtimer = metro.init(function() gridredraw() end, 0.02, -1)
  gridredrawtimer:start()
  dirtygrid = true

  grid.add = draw_grid_connected

  screenredrawtimer = metro.init(function() redraw() end, 0.1, -1)
  screenredrawtimer:start()

  params:bang()

  softcut.event_phase(phase)
  softcut.poll_start_phase()

  clock.run(clock_update_tempo)

  local arc_redraw_timer = metro.init()
  arc_redraw_timer.time = 1/60
  arc_redraw_timer.event = function() arc_redraw() end
  arc_redraw_timer:start()
end

-- poll callback
phase = function(n, x)
  --if n == 1 then print(x) end
  local pp = ((x - clip[track[n].clip].s) / clip[track[n].clip].l)-- * 16 --TODO 16=div
  --x = math.floor(track[n].pos*16)
  --if n==1 then print("> "..x.." "..pp) end
  track[n].pos_arc = pp
  x = math.floor(pp * 16)
  if x ~= track[n].pos_grid then
    track[n].pos_grid = x
    if view == vCUT then dirtygrid=true end
  end
end



update_rate = function(i)
  local n = math.pow(2,track[i].speed + params:get(i.."speed_mod"))
  if track[i].rev == 1 then n = -n end
  if track[i].tempo_map == 1 then
    local bpmmod = params:get("clock_tempo") / clip[track[i].clip].bpm
    --print("bpmmod: "..bpmmod)
    n = n * bpmmod
  end
  softcut.rate(i,n)
end


gridkey_arc = function(x,z)
  if z==1 then
    if x==1 then
      for i=1,4 do
        alt_mode_active[i]= not alt_mode_active[i]
      end
      alt_mode_reverse= not alt_mode_reverse
    end
    alt_mode_active[x-12]= not alt_mode_active[x-12]
  end
  dirtygrid=true
end


gridkey_nav = function(x,z)
  if z==1 then
    if x==1 then
      if alt == 1 then softcut.buffer_clear() end
      set_view(vREC)
    elseif x==2 then set_view(vCUT)
    elseif x==3 then set_view(vCLIP)
    elseif x>4 and x<9 then
      local i = x - 4
      if alt == 1 then
        local e={t=ePATTERN,i=i,action="rec_stop"} event(e)
        local e={t=ePATTERN,i=i,action="stop"} event(e)
        local e={t=ePATTERN,i=i,action="clear"} event(e)
      elseif pattern[i].rec == 1 then
        local e={t=ePATTERN,i=i,action="rec_stop"} event(e)
        local e={t=ePATTERN,i=i,action="start"} event(e)
      elseif pattern[i].count == 0 then
        local e={t=ePATTERN,i=i,action="rec_start"} event(e)
      elseif pattern[i].play == 1 then
        local e={t=ePATTERN,i=i,action="stop"} event(e)
      else
        local e={t=ePATTERN,i=i,action="start"} event(e)
      end
    elseif x>8 and x<13 then
      local i = x-8
      if alt == 1 then
        --print("recall: clear "..i)
        recall[i].event = {}
        recall[i].recording = false
        recall[i].has_data = false
        recall[i].active = false
      elseif recall[i].recording == true then
        --print("recall: stop")
        recall[i].recording = false
      elseif recall[i].has_data == false then
        --print("recall: rec")
        recall[i].recording = true
      elseif recall[i].has_data == true then
        --print("recall: exec")
        recall_exec(i)
        recall[i].active = true
      end
    elseif x==15 and alt == 0 then
      quantize = 1 - quantize
      if quantize == 0 then quantizer:stop()
      else quantizer:start()
      end
    elseif x==15 and alt == 1 then
      set_view(vTIME)
    elseif x==16 then alt = 1
    end
  elseif z==0 then
    if x==16 then alt = 0
    elseif x==15 and view == vTIME then set_view(-1)
    elseif x>8 and x<13 then recall[x-8].active = false end
  end
  dirtygrid=true
end

gridredraw_nav = function()
  -- indicate view
  g:led(view,1,15)
  if alt==1 then g:led(16,1,9) end
  if quantize==1 then g:led(15,1,9) end
  for i=1,4 do
    -- patterns
    if pattern[i].rec == 1 then g:led(i+4,1,15)
    elseif pattern[i].play == 1 then g:led(i+4,1,9)
    elseif pattern[i].count > 0 then g:led(i+4,1,5)
    else g:led(i+4,1,3) end
    -- recalls
    local b = 2
    if recall[i].recording == true then b=15
    elseif recall[i].active == true then b=11
    elseif recall[i].has_data == true then b=5 end
    g:led(i+8,1,b)
  end

  if alt_mode_reverse then
    g:led(1,8,15)
  else
    g:led(1,8,2)
  end

  for i=13,16 do
    if alt_mode_active[i-12]==false then
      g:led(i,8,2)
    else
      g:led(i,8,8)
    end
  end

  --arc_redraw()
end

-------------------- REC
v.key[vREC] = function(n,z)
  if n==2 and z==1 then
    viewinfo[vREC] = 1 - viewinfo[vREC]
    redraw()
  end
end

v.enc[vREC] = function(n,d)
  if viewinfo[vREC] == 0 then
    if n==2 then
      params:delta(focus.."vol",d)
    elseif n==3 then
      params:delta(focus.."speed_mod",d)
    end
  else
    if n==2 then
      params:delta(focus.."rec",d)
    elseif n==3 then
      params:delta(focus.."pre",d)
    end
  end
  redraw()
end

v.redraw[vREC] = function()
  screen.clear()
  screen.level(15)
  screen.move(10,16)
  screen.text("REC > "..focus)
  local sel = viewinfo[vREC] == 0

  screen.level(sel and 15 or 4)
  screen.move(10,32)
  screen.text(params:string(focus.."vol"))
  screen.move(70,32)
  screen.text(params:string(focus.."speed_mod"))
  screen.level(3)
  screen.move(10,40)
  screen.text("volume")
  screen.move(70,40)
  screen.text("speed mod")

  screen.level(not sel and 15 or 4)
  screen.move(10,52)
  screen.text(params:string(focus.."rec"))
  screen.move(70,52)
  screen.text(params:string(focus.."pre"))
  screen.level(3)
  screen.move(10,60)
  screen.text("rec level")
  screen.move(70,60)
  screen.text("overdub")

  screen.update()
end

v.gridkey[vREC] = function(x, y, z)
  if y == 8 then gridkey_arc(x,z) end
  if y == 1 then gridkey_nav(x,z)
  elseif y == 8 then return
  else
    if z == 1 then
      i = y-1
      if x>2 and x<8 then
        if alt == 1 then
          track[i].tempo_map = 1 - track[i].tempo_map
          update_rate(i)
        elseif focus ~= i then
          local q = calc_quant(i)
          local off = calc_quant_off(i, q)
          print("Focus:"..focus)
          set_phase_quant(focus, q, focus)
          softcut.phase_offset(i,off)
          focus = i
          redraw()
        end
      elseif x==1 and y<TRACKS+2 then
        track[i].rec = 1 - track[i].rec
        print("REC "..track[i].rec)
        set_rec(i)
      elseif x==16 and y<TRACKS+2 then
        if track[i].play == 1 then
          e = {}
          e.t = eSTOP
          e.i = i
          event(e)
        else
          e = {}
          e.t = eSTART
          e.i = i
          event(e)
        end
      elseif x>8 and x<16 and y<TRACKS+2 then
        local n = x-12
        e = {} e.t = eSPEED e.i = i e.speed = n
        event(e)
      elseif x==8 and y<TRACKS+2 then
        local n = 1 - track[i].rev
        e = {} e.t = eREV e.i = i e.rev = n
        event(e)
      end
      dirtygrid=true
    end
  end
end

v.gridredraw[vREC] = function()
  g:all(0)
  g:led(3,focus+1,7)
  g:led(4,focus+1,7)
  for i=1,TRACKS do
    local y = i+1
    g:led(1,y,3)--rec
    if track[i].rec == 1 then g:led(1,y,9) end
    if track[i].tempo_map == 1 then g:led(5,y,7) end -- tempo.map
    g:led(8,y,3)--rev
    g:led(16,y,3)--stop
    g:led(12,y,3)--speed=1
    g:led(12+track[i].speed,y,9)
    if track[i].rev == 1 then g:led(8,y,7) end
    if track[i].play == 1 then g:led(16,y,15) end
  end
  gridredraw_nav()
  g:refresh();
end

--------------------CUT
v.key[vCUT] = function(n,z)
  print("CUT key")
end

v.enc[vCUT] = function(n,d)
  if n==2 then
    params:delta(focus.."vol",d)
  end
  redraw()
end

v.redraw[vCUT] = function()
  screen.clear()
  screen.level(15)
  screen.move(10,16)
  screen.text("CUT > "..focus)
  if viewinfo[vCUT] == 0 then
    screen.move(10,32)
    screen.text(params:string(focus.."vol"))
    --screen.move(70,50)
    --screen.text(params:get("loop_mod"..focus))
    screen.level(3)
    screen.move(10,40)
    screen.text("volume")
    --screen.move(70,60)
    --screen.text("speed mod")
  else
    screen.move(10,50)
    screen.text(params:get(focus.."rec"))
    screen.move(70,50)
    screen.text(params:get(focus.."pre"))
    screen.level(3)
    screen.move(10,60)
    screen.text("rec level")
    screen.move(70,60)
    screen.text("overdub")
  end
  screen.update()
end

v.gridkey[vCUT] = function(x, y, z)
  if y == 8 then gridkey_arc(x,z) end
  if z==1 and held[y] then heldmax[y] = 0 end
  held[y] = held[y] + (z*2-1)
  if held[y] > heldmax[y] then heldmax[y] = held[y] end
  --print(held[y])

  if y == 1 then gridkey_nav(x,z)
  elseif y == 8 then return
  else
    i = y-1
    if z == 1 then
      if focus ~= i then
        focus = i
        redraw()
      end
      if alt == 1 and y<TRACKS+2 then
        if track[i].play == 1 then
          e = {} e.t = eSTOP e.i = i
        else
          e = {} e.t = eSTART e.i = i
        end
        event(e)
      elseif y<TRACKS+2 and held[y]==1 then
        first[y] = x
        local cut = x-1
        --print("pos > "..cut)
        e = {} e.t = eCUT e.i = i e.pos = cut
        event(e)
      elseif y<TRACKS+2 and held[y]==2 then
        second[y] = x
      end
    elseif z==0 then
      if y<TRACKS+2 and held[y] == 1 and heldmax[y]==2 then
        e = {}
        e.t = eLOOP
        e.i = i
        e.loop = 1
        e.loop_start = math.min(first[y],second[y])
        e.loop_end = math.max(first[y],second[y])
        event(e)
      end
    end
  end
end

v.gridredraw[vCUT] = function()
  g:all(0)
  gridredraw_nav()
  for i=1,TRACKS do
    if track[i].loop == 1 then
      local start=track[i].loop_start
      local rounded_start=math.floor(start)
      local difference_start = math.floor(rounded_start-start*5)
      for x=rounded_start,track[i].loop_end do
        g:led(x,i+1,5)
      end
    end
    if track[i].play == 1 then
      g:led((track[i].pos_grid+1)%16, i+1, 15)
    end
  end
  g:refresh();
end



--------------------CLIP

clip_actions = {"load","clear","save"}
clip_action = 1
clip_sel = 1
clip_clear_mult = 3

function fileselect_callback(path, c)
  print("FILESELECT "..c)
  if path ~= "cancel" and path ~= "" then
    local ch, len = audio.file_info(path)
    if ch > 0 and len > 0 then
      print("file > "..path.." "..clip[track[c].clip].s)
      print("file length > "..len/48000)
      --softcut.buffer_read_mono(path, 0, clip[track[clip_sel].clip].s, len/48000, 1, 1)
      softcut.buffer_read_mono(path, 0, clip[track[c].clip].s, CLIP_LEN_SEC, 1, 1)
      local l = math.min(len/48000, CLIP_LEN_SEC)
      set_clip_length(track[c].clip, l)
      clip[track[c].clip].name = path:match("[^/]*$")
      -- TODO: STRIP extension
      set_clip(c,track[c].clip)
      update_rate(c)
      params:set(c.."file",path)
    else
      print("not a sound file")
    end

    -- TODO re-set_clip any tracks with this clip loaded
    screenredrawtimer:start()
    redraw()
  end
end

function textentry_callback(txt)
  if txt then
    local c_start = clip[track[clip_sel].clip].s
    local c_len = clip[track[clip_sel].clip].l
    print("SAVE " .. _path.audio .. "mlr/" .. txt .. ".wav", c_start, c_len)
    util.make_dir(_path.audio .. "mlr")
    softcut.buffer_write_mono(_path.audio.."mlr/"..txt..".wav",c_start,c_len,1)
    clip[track[clip_sel].clip].name = txt
  else
    print("save cancel")
  end
  screenredrawtimer:start()
  redraw()
end

v.key[vCLIP] = function(n,z)
  if n==2 and z==0 then
    if clip_actions[clip_action] == "load" then
      screenredrawtimer:stop()
      fileselect.enter(os.getenv("HOME").."/dust/audio",
        function(n) fileselect_callback(n,clip_sel) end)
    elseif clip_actions[clip_action] == "clear" then
      local c_start = clip[track[clip_sel].clip].s * 48000
      print("clear_start: " .. c_start)
      --softcut.clear_range(c_start, CLIP_LEN_SEC * 48000) -- two minutes
      clip[track[clip_sel].clip].name = '-'
      redraw()
    elseif clip_actions[clip_action] == "save" then
      screenredrawtimer:stop()
      textentry.enter(textentry_callback, "mlr-" .. (math.random(9000)+1000))
    end
  elseif n==3 and z==1 then
    clip_reset(clip_sel,60/params:get("clock_tempo")*(2^(clip_clear_mult-2)))
    set_clip(clip_sel,track[clip_sel].clip)
    update_rate(clip_sel)
  end
end

v.enc[vCLIP] = function(n,d)
  if n==2 then
    clip_action = util.clamp(clip_action + d, 1, 3)
  elseif n==3 then
    clip_clear_mult = util.clamp(clip_clear_mult+d,1,6)
  end
  redraw()
  dirtygrid=true
end

local function truncateMiddle (str, maxLength, separator)
  maxLength = maxLength or 30
  separator = separator or "..."

  if (maxLength < 1) then return str end
  if (string.len(str) <= maxLength) then return str end
  if (maxLength == 1) then return string.sub(str, 1, 1) .. separator end

  midpoint = math.ceil(string.len(str) / 2)
  toremove = string.len(str) - maxLength
  lstrip = math.ceil(toremove / 2)
  rstrip = toremove - lstrip

  return string.sub(str, 1, midpoint - lstrip) .. separator .. string.sub(str, 1 + midpoint + rstrip)
end

v.redraw[vCLIP] = function()
  screen.clear()
  screen.level(15)
  screen.move(10,16)
  screen.text("CLIP > TRACK "..clip_sel)

  screen.move(10,52)
  screen.text(truncateMiddle(clip[track[clip_sel].clip].name, 18))
  screen.level(3)
  screen.move(10,60)
  screen.text("clip "..track[clip_sel].clip .. " " .. clip_actions[clip_action])

  screen.move(100,52)
  screen.text(2^(clip_clear_mult-2))
  screen.level(3)
  screen.move(100,60)
  screen.text("resize")

  screen.update()
end

v.gridkey[vCLIP] = function(x, y, z)
  if y == 8 then gridkey_arc(x,z) end
  if y == 1 then gridkey_nav(x,z)
  elseif z == 1 and y < TRACKS+2 and x < MAX_CLIPS+1 then
    clip_sel = y-1
    if x ~= track[clip_sel].clip then
      set_clip(clip_sel,x)
    end
    redraw()
    dirtygrid=true
  end
end

v.gridredraw[vCLIP] = function()
  g:all(0)
  gridredraw_nav()
  for i=1,16 do g:led(i,clip_sel+1,4) end
  for i=1,TRACKS do g:led(track[i].clip,i+1,10) end
  g:refresh();
end




--------------------TIME
v.key[vTIME] = function(n,z)
  print("TIME key")
end

v.enc[vTIME] = function(n,d)
  if n==2 then
    params:delta("clock_tempo",d)
  elseif n==3 then
    params:delta("quant_div",d)
  end
  redraw()
end

v.redraw[vTIME] = function()
  screen.clear()
  screen.level(15)
  screen.move(10,30)
  screen.text("TIME")
  if viewinfo[vTIME] == 0 then
    screen.move(10,50)
    screen.text(params:get("clock_tempo"))
    screen.move(70,50)
    screen.text(params:get("quant_div"))
    screen.level(3)
    screen.move(10,60)
    screen.text("tempo")
    screen.move(70,60)
    screen.text("quant div")
  end
  screen.update()
end

v.gridkey[vTIME] = function(x, y, z)
  if y == 1 then gridkey_nav(x,z) end
end

v.gridredraw[vTIME] = function()
  g:all(0)
  gridredraw_nav()
  g:refresh();
end

function draw_grid_connected()
  dirtygrid=true
  gridredraw()
end

function cleanup()
  for i=1,4 do
    pattern[i]:stop()
    pattern[i] = nil
  end

  grid.add = function() end
end






------ arc
function a.delta(n, d)
  --FIRST ENCODER
  if n == 1 then
    -- ADJUST LOOP
    if track[focus].loop == 1 then
      if alt_mode_active[1] == false then
        local new_loop_start = track[focus].loop_start+(d/encoder_loop_sens)
        if math.abs(new_loop_start)-1 <= track[focus].loop_end then
          track[focus].loop_start=new_loop_start  
        end
      else
        local new_loop_end = track[focus].loop_end+(d/encoder_loop_sens)
          if math.abs(new_loop_end)+1 >= track[focus].loop_start then
            track[focus].loop_end=new_loop_end  
          end  
      end  
      local lstart = clip[track[focus].clip].s + (track[focus].loop_start-1)/16*clip[track[focus].clip].l
      local lend = clip[track[focus].clip].s + (track[focus].loop_end)/16*clip[track[focus].clip].l
      softcut.loop_start(focus,lstart)
      softcut.loop_end(focus,lend)
    else
      --SCRUB
      if alt_mode_active[1] == false then
        local new_position = (track[focus].pos_arc+d/encoder_scrub_sens)
        local cut = 0
        if new_position > 0 then
          cut = (new_position)*clip[track[focus].clip].l + clip[track[focus].clip].s
        else
          cut = clip[track[focus].clip].e + (new_position)*clip[track[focus].clip].l
        end
        if cut > clip[track[focus].clip].e then
          cut = cut - clip[track[focus].clip].l
        end 
        softcut.position(focus,cut)
        if track[focus].play == 0 then
          track[focus].play = 1
          ch_toggle(focus,1)
          if d<0 then
            print("d"..d)
            track[focus].rev = 1
          else
            track[focus].rev = 0
          end
          update_rate(focus)
          dirtygrid=true

        end
      else
        if d>0 then              
          track[focus].play = 1
          ch_toggle(focus,1)
   
        else
          track[focus].play = 0
          ch_toggle(focus,0)
  
        end
      end
      local q = calc_quant(focus)
      local off = calc_quant_off(focus, q)
      set_phase_quant(focus, q, focus)
    end
  --SECOND ENCODER
  --adjust Speed
  elseif n == 2 then
    --update Speed
    if not alt_mode_active[2] then
      track[focus].speed_no_normalize = track[focus].speed_no_normalize + d/encoder_speed_sens
      local new_speed = math.floor(track[focus].speed_no_normalize)
      if new_speed < 4 and new_speed > -4 then
        track[focus].speed = new_speed
        update_rate(focus)
        dirtygrid=true
      end
    else
      --update Direction
      track[focus].rev_no_normalize = track[focus].rev_no_normalize - d/encoder_speed_sens
      local new_direction = math.floor(track[focus].rev_no_normalize)
      if new_direction < 2 and new_direction > -1 then
        track[focus].rev=new_direction
        update_rate(focus)
        dirtygrid=true
      end
    end  

    --update_rate(e.i)
  -- THIRD ENCODER  
  elseif n == 3 then
    if alt_mode_active[3] == false then
      params:delta(focus.."rate_slew",d/encoder_value_sens)
    else
      params:delta(focus.."speed_mod",d/encoder_value_sens)
    end

  -- FOURTH ENCODER  
  elseif n == 4 then
    if alt_mode_active[4] == false then
      params:delta(focus.."vol",d/encoder_value_sens)
    else
      params:delta(focus.."pan",d/encoder_value_sens)
    end
  end
  dirtygrid=true
end

function arc_redraw()
  a:all(0)
    running_position = (track[focus].pos_arc)
    -- EDIT LOOP
    start_position = (math.floor(((track[focus].loop_start-1)/16)*64))
    end_position = (math.floor(((track[focus].loop_end)/16)*64))
    a:segment(1, running_position * tau, tau * running_position + 0.1, 15)
    if alt_mode_active[1] == true and track[focus].loop == 0  then
      a:segment(1, running_position * tau, tau * running_position + 0.3, 15)
    end
    
    if track[focus].loop == 1 then
      -- hightlight start
      if alt_mode_active[1] == false then
        a:led (1, start_position, 15)
        a:led (1, end_position + 1, 6)
      else
        -- hightlight end
        a:led (1, start_position, 6)
        a:led (1, end_position + 1, 15)
      end
    end


    -- EDIT SPEED
    if alt_mode_active[2] == false then
      for i=-3,3 do a:led(2, (i*5 + 1), 8) end
      a:led(2,  1, 5)
      a:led(2, (track[focus].speed*5 + 1), 15)
    else
      if track[focus].rev == 0 then
        for i=10,13 do a:led(2, (i + 1), 5) end
      else
        for i=-13,-10 do a:led(2, (i + 1), 5) end
      end
    end


    -- SHOW FOCUS TRACK
    for i=1,6 do
      if 7-i==focus then
        a:led (2, 29+i, 15)
      else  
        a:led (2, 29+i, 5)
      end  
    end


    --ADJUST SLEW
    if alt_mode_active[3] == false then
      rate_slew=math.floor(params:get(focus.."rate_slew")*64)
      a:led (3, rate_slew, 5)
      a:led (3, rate_slew+1, 15)
      a:led (3, rate_slew+2, 5)
    else
      speed_mod=(params:get(focus.."speed_mod"))
      a:led (3, 1, 15)
      a:segment(3, speed_mod/2 * tau, speed_mod/2 * tau + 0.2, 10)
    end


    -- EDIT VOLUME
    if alt_mode_active[4] == false then
      adjusted_volume=math.floor(params:get(focus.."vol")*64)
      for i=1,64 do
        if i < adjusted_volume then
          a:led (4, i, 1)
        end
      end 
      for i=0,15 do
        if adjusted_volume-i>0 then  
          a:led (4, adjusted_volume-i, 15-i)
        end
      end
    else
      adjusted_pan=math.floor(params:get(focus.."pan")*16)
      a:led (4, 1, 5)
      a:led (4, 17, 7)
      a:led (4, -15, 5)
      a:led (4, adjusted_pan + 1, 12)

    end
  a:refresh()
end

-- SUPPORT 2011 ARC click
function a.key(n, z)
  if z == 1 then
    alt_mode_active[n] = not alt_mode_active[n]
  end
  dirtygrid=true
end  


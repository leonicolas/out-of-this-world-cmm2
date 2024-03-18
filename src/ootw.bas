option explicit
option base 0

const false = 0
const true  = 1

const KEY_UP     = 1
const KEY_RIGHT  = 2
const KEY_DOWN   = 3
const KEY_LEFT   = 4
const KEY_ACTION = 5

const VAR_HERO_POS_UP_DOWN     = 0xe5
const VAR_SCROLL_Y             = 0xf9
const VAR_HERO_ACTION          = 0xfa
const VAR_HERO_POS_JUMP_DOWN   = 0xfb
const VAR_HERO_POS_LEFT_RIGHT  = 0xfc
const VAR_HERO_POS_MASK        = 0xfd
const VAR_HERO_ACTION_POS_MASK = 0xfe
const VAR_PAUSE_SLICES         = 0xff

const PALETTE_EGA(47) = (&H00,&H00,&H00,&H00,&H00,&Haa,&H00,&Haa,&H00,&H00,&Haa,&Haa,&Haa,&H00,&H00,&Haa,&H00,&Haa,&Haa,&H55,&H00,&Haa,&Haa,&Haa,&H55,&H55,&H55,&H55,&H55,&Hff,&H55,&Hff,&H55,&H55,&Hff,&Hff,&Hff,&H55,&H55,&Hff,&H55,&Hff,&Hff,&Hff,&H55,&Hff,&Hff,&Hff)

dim keyboard(5)

function is_key_pressed(keycode$)
	is_key_pressed=keyboard(keycode$)
end function

function set_key_pressed(keycode$, state$)
	if keycode$ = 37 then
		keyboard(KEY_LEFT) = state$
	else if keycode$ = 38 then
		keyboard(KEY_UP) = state$
	else if keycode$ = 39 then
		keyboard(KEY_RIGHT) = state$
	else if keycode$ = 40 then
		keyboard(KEY_DOWN) = state$
	else if keycode$ = 32 or keycode$ == 13 then
		keyboard(KEY_ACTION) = state$
	end if
end function

dim vars(255)
' 0: state | 1: next_state | 2: offset | 3: next_offset
dim tasks(63,3)
' 0: task | 1: stack values
dim stack(63,255)
' 0: task | 1: stack start and end pointers
dim stack_pointer(63,1)

sub push_stack(task_num, value)
    local ep=stack_pointer(task_num,1)
    inc ep
    if ep > bound(stack,2) then ep=0
    stack_pointer(task_num,1) = ep
    stack(task_num,ep)=value
end sub

function pop_stack(task_num)
    local sp=stack_pointer(task_num,0)
    pop_stack=stack(task_num,sp)
    inc sp
    if sp > bound(stack,2) then ep=0
    stack_pointer(task_num,0) = sp
end function

sub clear_stack(task_num)
    stack_pointer(task_num,0)=0
    stack_pointer(task_num,1)=-1
end sub

sub panic(msg)
    cls
    print "PANIC! " + msg
    end
end sub

dim bytecode(1)
dim palette(1)
dim polygons1(1)
dim polygons2(1)

dim bytecode_offset
dim task_num
dim task_paused

dim next_part

dim delay = 0
dim timestamp

function read_byte()
	read_byte = bytecode(bytecode_offset)
	inc bytecode_offset
end function

function read_word()
	read_word = (bytecode(bytecode_offset) << 8) or bytecode(bytecode_offset + 1)
	inc bytecode_offset, 2
end function

function to_signed(value, bits)
	local mask = 1 << (bits - 1)
	to_signed = value - ((value and mask) << 1)
end function

sub run_opcode(opcode$)
    select case opcode$
        case &H00
            vars(read_byte()) = to_signed(read_word(), 16)
        case &H01
            vars(read_byte()) = vars(read_byte())
        case &H02
            inc vars(read_byte()), vars(read_byte())
        case &H03
            inc vars(read_byte()), to_signed(read_word(), 16)
        case &H04 ' call
            local addr = read_word()
            push_stack(task_num, bytecode_offset)
            bytecode_offset = addr
        case &H05 ' ret
            bytecode_offset = pop_stack(task_num)
        case &H06 ' yield
            task_paused = true
        case &H07 ' jmp
            bytecode_offset = read_word()
        case &H08 ' install_task
            tasks(read_byte(), 3) = read_word()
        case &H09 ' jmp_nz
            local num = read_byte()
            inc vars(num), -1
            if vars(num) <> 0 then bytecode_offset = read_word()
        case &H0a ' jmp_cond
            local op = read_byte()
            local lhs = vars(read_byte())
            local rhs
            if op and &H80 then
                rhs = vars(read_byte())
            else if op and &H40 then
                rhs = to_signed(read_word(), 16)
            else
                rhs = read_byte()
            end if
            local addr = read_word()
            select case op and 7
				case 0:
					if lhs = rhs then bytecode_offset = addr
				case 1:
					if lhs <> rhs then bytecode_offset = addr
				case 2:
					if lhs > rhs then bytecode_offset = addr
				case 3:
					if lhs >= rhs then bytecode_offset = addr
				case 4:
					if lhs < rhs then bytecode_offset = addr
				case 5:
					if lhs <= rhs then bytecode_offset = addr
            end select
        case &H0b ' set_palette
            next_palette = read_word() >> 8
        case &H0c ' change_tasks_state
            local s_task = read_byte()
            local e_task = read_byte()
            local state = read_byte()
			local i
            if state = 2 then
                for i = s_task to e_task
					tasks(i,3) = -2
                next
        	else
				for i = s_task to e_task
                    tasks(i,1) = state
                next
            end if
        case &H0d ' select_page
            select_page(read_byte())
        case &H0e ' fill_page
            fill_page(read_byte(), read_byte())
        case &H0f ' copy_page
            copy_page(read_byte(), read_byte(), vars(VAR_SCROLL_Y))
        case &H10 ' update_display
            inc delay, vars(VAR_PAUSE_SLICES) * 1000 / 50
            vars(&Hf7) = 0
            update_display(read_byte())
        case &H11 ' remove_task
            bytecode_offset = -1
            task_paused = true
        case &H12 ' draw_string
            draw_string(read_word(), read_byte(), read_byte(), read_byte())
        case &H13 ' sub
            inc vars(read_byte()), -vars(read_byte())
        case &H14 ' and
            local num = read_byte()
            vars(num) = to_signed((vars(num) and read_word()) and &Hffff, 16)
        case &H15 ' or
            local num = read_byte()
            vars(num) = to_signed((vars(num) or read_word()) and &Hffff, 16)
        case &H16 ' shl
            const num = read_byte()
            vars(num) = to_signed((vars(num) << (read_word() and 15)) and &Hffff, 16)
        case &H17 ' shr
            local num = read_byte()
            vars(num) = to_signed((vars(num) and &Hffff) >> (read_word() and 15), 16)
        case &H18 ' play_sound
			' FIXME: Implement play sound
            local num     = read_word()
            local freq    = read_byte()
            local volume  = read_byte()
            local channel = read_byte()
        case &H19 ' load_resource
            local num = read_word()
            if num > 16000 then
                next_part = num
            else if num in bitmaps then ' FIXME: Implement IN
                if num >= 3000 then
                    ' FIXME: Implement buffer
                    set_palette_bmp(load(bitmaps[num][0], 256 * 3))
                    buffer8.set(load(bitmaps[num][1], SCREEN_W * SCREEN_H))
                else
                    draw_bitmap(num)
                end if
            end if
        case &H1a ' play_music
			' FIXME: Implement play music
            local num      = read_word()
            local period   = read_word()
            local position = read_byte()
	end select
end sub

sub execute_task()
	local opcode, x, y, h, p, z
	do while not task_paused
		opcode = read_byte()
		if opcode and &H80 then
			offset = (((opcode << 8) or read_byte()) << 1) and &Hfffe
			x = read_byte()
			y = read_byte()
			h = y - 199
			if h > 0 then
				y = 199
				inc x, h
			end if
			draw_shape(polygons1(), offset, &Hff, 64, x, y)

		else if opcode and &H40 then
			offset = (read_word() << 1) and &Hfffe
			x = read_byte()
			if opcode and &H20 = 0 then
				if opcode and &H10 = 0 then
					x = (x << 8) and read_byte()
				else
					x = vars(x)
				end if
			else
				if opcode and &H10 then inc x, 256
			end if
			y = read_byte()
			if opcode and 8 = 0 then
				if opcode and 4 = 0 then
					y = (y << 8) or read_byte()
				else
					y = vars(y)
				end if
            end if
            math add polygons1(), 0, polygons()
			zoom = 64
			if opcode and 2 = 0 then
				if opcode and 1 = 1 then zoom = vars(read_byte())
			else
				if opcode and 1 = 1 then
                    math add polygons2(), 0, polygons()
                else
                    zoom = read_byte()
                end if
			end if
			draw_shape(polygons(), offset, &Hff, zoom, x, y)
		else
			run_opcode(opcode)
		end if
	loop
end sub

' FIXME: Implement keyinput!!!
sub update_input
	local mask = 0
	if is_key_pressed(KEY_RIGHT) then
		vars(VAR_HERO_POS_LEFT_RIGHT) = 1
		mask = mask or 1
	else if is_key_pressed(KEY_LEFT) then
		vars(VAR_HERO_POS_LEFT_RIGHT) = -1
		mask = mask or 2
	else
		vars(VAR_HERO_POS_LEFT_RIGHT) = 0
	end if
	if is_key_pressed(KEY_DOWN) then
		vars(VAR_HERO_POS_JUMP_DOWN) = 1
		vars(VAR_HERO_POS_UP_DOWN) = 1
		mask = mask or 4
	else if is_key_pressed(KEY_UP) then
		vars(VAR_HERO_POS_JUMP_DOWN) = -1
		vars(VAR_HERO_POS_UP_DOWN) = -1
		mask = mask or 8
	else
		vars(VAR_HERO_POS_JUMP_DOWN) = 0
		vars(VAR_HERO_POS_UP_DOWN) = 0
	end if
	vars(VAR_HERO_POS_MASK) = mask
	if is_key_pressed(KEY_ACTION) then
		vars(VAR_HERO_ACTION) = 1
		mask = mask or 0x80
	else
		vars(VAR_HERO_ACTION) = 0
	end if
	vars(VAR_HERO_ACTION_POS_MASK) = mask
end sub

sub run_tasks()
	local i, offset
	if next_part <> 0 then
		restart(next_part)
		next_part = 0
	end if
	for i = 0 to bound(tasks())
		tasks(i, 0) = tasks(i, 1)
		offset = tasks(i, 3)
		if offset <> -1 then
			tasks(i, 2) = choice(offset = -2, -1, offset)
			tasks(i, 3) = -1
		end if
	next
	update_input()
	for i = 0 to bound(tasks())
		if tasks(i, 0) = 0 then
			offset = tasks(i, 1)
			if offset <> -1 then
				bytecode_offset = offset
				clear_stack(i)
				task_num = i
				task_paused = false
				execute_task()
				tasks(i, 1) = bytecode_offset
			end if
		end if
	next
end sub

sub load(data, size, buffer())
	' FIXME: Replace base64 atob func
	local i
	data = atob(data)
	if bound(data()) <> size then
		' FIXME: Implement inflate
		buffer = pako.inflate(data)
	else
		' FIXME: charCodeAt
		for i = 0 to size
			buffer(i) = data.charCodeAt(i) and 0xff
		next
	end if
end sub

sub resize_global_arrays(palette_sz, bytecode_sz, polygons1_sz, polygons2_sz)
    erase palette(): dim palette(palette_sz)
    erase bytecode(): dim bytecode(bytecode_sz)
    erase polygons1(): dim polygons1(polygons1_sz)
    erase polygons2(): dim polygons2(polygons2_sz)
end sub

sub restart(part)
	local i
	if part = 16000 then ' protection
        resize_global_arrays(size14, size15, size16, size16)
		palette   = load(data14, size14)
		bytecode  = load(data15, size15)
		polygons1 = load(data16, size16)
	else if part = 16001 then ' introduction
        resize_global_arrays(size17, size18, size19, size19)
		palette   = load(data17, size17)
		bytecode  = load(data18, size18)
		polygons1 = load(data19, size19)
	else if part = 16002 then ' water
        resize_global_arrays(size1a, size1b, size1c, size11)
		palette   = load(data1a, size1a)
		bytecode  = load(data1b, size1b)
		polygons1 = load(data1c, size1c)
		polygons2 = load(data11, size11)
	else if part = 16003 then ' jail
        resize_global_arrays(size1d, size1e, size1f, size11)
		palette   = load(data1d, size1d)
		bytecode  = load(data1e, size1e)
		polygons1 = load(data1f, size1f)
		polygons2 = load(data11, size11)
	else if part = 16004 then ' 'cite'
        resize_global_arrays(size20, size21, size22, size11)
		palette   = load(data20, size20)
		bytecode  = load(data21, size21)
		polygons1 = load(data22, size22)
		polygons2 = load(data11, size11)
	else if part = 16005 then ' 'arene'
        resize_global_arrays(size23, size24, size25, size11)
		palette   = load(data23, size23)
		bytecode  = load(data24, size24)
		polygons1 = load(data25, size25)
		polygons2 = load(data11, size11)
	else if part = 16006 then ' 'luxe'
        resize_global_arrays(size26, size27, size28, size11)
		palette   = load(data26, size26)
		bytecode  = load(data27, size27)
		polygons1 = load(data28, size28)
		polygons2 = load(data11, size11)
	else if part = 16007 then ' 'final'
        resize_global_arrays(size29, size2a, size2b, size11)
		palette   = load(data29, size29)
		bytecode  = load(data2a, size2a)
		polygons1 = load(data2b, size2b)
		polygons2 = load(data11, size11)
	else if part = 16008 then ' password screen
        resize_global_arrays(size7d, size7e, size7f, size7f)
		palette   = load(data7d, size7d)
		bytecode  = load(data7e, size7e)
		polygons1 = load(data7f, size7f)
		polygons2 = 0
	end if
	for i = 0 to bound(tasks())
		tasks(i,0) = 0  ' State
        tasks(i,1) = 0  ' Next state
        tasks(i,2) = -1 ' Offset
        tasks(i,3) = -1 ' Next offset
		clear_stack(i)
	next
	tasks(0,2) = 0
end sub

const SCALE = 2
const SCREEN_W = 320 * SCALE
const SCREEN_H = 200 * SCALE
const PAGE_SIZE = SCREEN_W * SCREEN_H

dim buffer8(4 * PAGE_SIZE)
dim palette32(16 * 3)
dim current_page0 ' current
dim current_page1 ' front
dim current_page2 ' back
dim next_palette = -1

const PALETTE_TYPE_AMIGA = 0
const PALETTE_TYPE_EGA = 1
const PALETTE_TYPE_VGA = 2

dim palette_type = PALETTE_TYPE_AMIGA
dim is_1991 ' 320x200
dim palette_bmp(256 * 3) ' 15th edition backgrounds

function get_page(num)
	if num = &Hff then
		get_page = current_page2
	else if num = &Hfe then
		get_page = current_page1
	else
		get_page = num
	end if
end function

sub select_page(num)
	current_page0 = get_page(num)
end sub

sub fill_page(num, color)
	num = get_page(num)
	' FIXME: Buffer!!!
	buffer8.fill(color, num * PAGE_SIZE, (num + 1) * PAGE_SIZE)
end sub

sub copy_page(src, dst, vscroll)
	dst = get_page(dst)
	if src >= &Hfe then
		src = get_page(src)
		' FIXME: Buffer!!!
		buffer8.set(buffer8.subarray(src * PAGE_SIZE, (src + 1) * PAGE_SIZE), dst * PAGE_SIZE)
	else
		if src and &H80 = 0 then vscroll = 0

		src = get_page(src and 3)
		if dst = src then exit sub
		local dst_offset = dst * PAGE_SIZE
		local src_offset = src * PAGE_SIZE

		if vscroll = 0 then
			' FIXME: Buffer!!!
			buffer8.set(buffer8.subarray(src_offset, src_offset + PAGE_SIZE), dst_offset)
		else
			vscroll = vscroll * SCALE
			if vscroll > -SCREEN_W and vscroll < SCREEN_W then
				local h = vscroll * SCREEN_W
				' FIXME: Buffer!!!
				if vscroll < 0 then
					buffer8.set(buffer8.subarray(src_offset - h, src_offset + PAGE_SIZE), dst_offset)
				else
					buffer8.set(buffer8.subarray(src_offset, src_offset + PAGE_SIZE - h), dst_offset + h)
				end if
			end if
		end if
	end if
end sub

sub draw_point(page, color, x, y)
	if x < 0 or x >= SCREEN_W or y < 0 or y >= SCREEN_H then exit sub

	local offset = page * PAGE_SIZE + y * SCREEN_W + x
	if color = 0x11 then
		buffer8(offset) = buffer8(y * SCREEN_W + x)
	else if color = 0x10 then
		buffer8(offset) = buffer8(offset) or 8
	else
		buffer8(offset) = color
	end if
end sub

' FIXME: Review!!!
sub draw_line(page, color, y, x1, x2)
	if x1 > x2 then
		local tmp = x1
		x1 = x2
		x2 = tmp
	end if
	if x1 >= SCREEN_W or x2 < 0 then exit sub

	if x1 < 0 then x1 = 0
	if x2 >= SCREEN_W then x2 = SCREEN_W - 1

	local offset = page * PAGE_SIZE + y * SCREEN_W
	if color = 0x11 then
		' FIXME: Buffer!!!
		buffer8.set(buffer8.subarray(y * SCREEN_W + x1, y * SCREEN_W + x2 + 1), offset + x1)
	else if color = 0x10 then
		local i
		for i = x1 to x2
			buffer8[offset + i] = buffer8[offset + i] or 8
		next
	else
		buffer8.fill(color, offset + x1, offset + x2 + 1)
	end if
end sub

' FIXME: Review!!!!
sub draw_polygon(page, color, vertices())
	' scanline fill
	local i = 0
	local j = bound(vertices()) - 1
	local scanline = min(vertices(i, 1), vertices(j, 1))
	local f2 = vertices(i, 0) << 16
	local f1 = vertices(j, 0) << 16
	inc i: inc j, -1

	local count = bound(vertices()) - 2
	local h1, step1, h2, step2
	do while count != 0
		inc count, -2
		h1 = vertices(j, 1) - vertices(j + 1, 1)
		step1 = (((vertices(j, 0) - vertices(j + 1, 0)) << 16) / choice(h1 = 0, 1, h1)) >> 0
		inc j, -1
		h2 = vertices(i, 1) - vertices(i - 1, 1)
		step2 = (((vertices(i, 0) - vertices(i - 1, 0)) << 16) / choice(h2 = 0, 1, h2)) >> 0
		inc i
		f1 = (f1 and &Hffff0000) or &H7fff
		f2 = (f2 and &Hffff0000) or &H8000
		if h2 = 0 then
			inc f1, step1
			inc f2, step2
		else
			local k
			for k = 0 to h2 - 1
				if scanline >= 0 then draw_line(page, color, scanline, f1 >> 16, f2 >> 16)
				inc f1, step1
				inc f2, step2
				inc scanline
				if scanline >= SCREEN_H then exit sub
			next
		end if
	loop
end sub

' FIXME: Review!!!
sub fill_polygon(data(), offset, color, zoom, x, y)
	local w = (data(offset) * zoom / 64) >> 0
	inc offset
	local h = (data(offset) * zoom / 64) >> 0
	inc offset
	local x1 = (x * SCALE - w * SCALE / 2) >> 0
	local x2 = (x * SCALE + w * SCALE / 2) >> 0
	local y1 = (y * SCALE - h * SCALE / 2) >> 0
	local y2 = (y * SCALE + h * SCALE / 2) >> 0
	if x1 >= SCREEN_W or x2 < 0 or y1 >= SCREEN_H or y2 < 0 then exit sub

	local count = data(offset++)
	local vertices(count-1,1)
	local i
	for i = 0 to count - 1
		vertices(i,0) = x1 + ((data(offset) * zoom / 64) >> 0) * SCALE
        inc offset
        vertices(i,1) = y1 + ((data(offset) * zoom / 64) >> 0) * SCALE
        inc offset
	next
	if count = 4 and w = 0 and h <= 1 then
		draw_point(current_page0, color, x1, y1)
	else
		draw_polygon(current_page0, color, vertices())
	end if
end sub

' FIXME: Review!!!
sub draw_shape_parts(data(), offset, zoom, x, y)
	local x0 = x - (data(offset) * zoom / 64) >> 0
    inc offset
	local y0 = y - (data(offset) * zoom / 64) >> 0
    inc offset
	local count = data(offset)
    inc offset
	local i, addr, x1, y1, color
	for i = 0 to count
		addr = (data(offset) << 8) or data(offset + 1)
		inc offset, 2
		x1 = x0 + (data(offset) * zoom / 64) >> 0
        inc offset
		y1 = y0 + (data(offset) * zoom / 64) >> 0
        inc offset
		color = &Hff
		if (addr and &H8000) <> 0 then
			color = data(offset) and &H7f
			inc offset, 2
		end if
		draw_shape(data(), ((addr << 1) and &Hfffe), color, zoom, x1, y1)
	next
end sub

' FIXME: Review!!!
sub draw_shape(data(), offset, color, zoom, x, y)
	local code = data(offset)
    inc offset
	if code >= &Hc0 then
		if color and &H80 then color = code and &H3f
		fill_polygon(data(), offset, color, zoom, x, y)
	else if (code and &H3f) = 2 then
        draw_shape_parts(data(), offset, zoom, x, y)
	end if
end sub

' FIXME: Review!!!
sub put_pixel(page, x, y, color)
	local j, offset = page * PAGE_SIZE + (y * SCREEN_W + x) * SCALE
	for j = 0 to SCALE - 1
        ' FIXME: Buffer!!!
		buffer8.fill(color, offset, offset + SCALE)
		inc offset, SCREEN_W
	next
end sub

' FIXME: Review!!!
sub draw_char(page, chr, color, x, y)
	if x < (320 / 8) and y < (200 - 8) then
        local i, j, mask
		for j = 0 to 7
			mask = font((chr - 32) * 8 + j)
			for i = 0 to 7
				if (mask and (1 << (7 - i))) <> 0 then put_pixel(page, x * 8 + i, y + j, color)
			next
		next
	end if
end sub

const STRINGS_LANGUAGE_EN = 0
dim strings_language = STRINGS_LANGUAGE_EN

' FIXME: Review!!!
sub draw_string(num, x, y, color)
	if num in strings_en then
		local i, x0 = x, str = strings(num)
		for i = 1 to len(str)
			chr = asc(mid$(str, i, 1))
			if chr = 10 then
				inc y, 8
				x = x0
		    else
				draw_char(current_page0, chr, color, x, y)
				inc x
			end if
		next
	end if
end sub

' FIXME: Review!!!
sub draw_bitmap(num)
	local size = bitmaps(num, 1)
	local buf = load(bitmaps(num, 0), size)
	var offset = 0, y, x, b, p, mask, color
	for y = 0 to 199
		for x = 0 to 319 step 8
			for b = 0 to 7
				mask = 1 << (7 - b)
				color = 0
				for p = 0 to 3
					if buf(offset + p * 8000) and mask <> 0 then color = color or (1 << p)
				next
				put_pixel(0, x + b, y, color)
			next
			inc offset
		next
	next
end sub

sub set_palette_bmp(data)
	local i, color = 0
	for i = 0 to 257
		palette_bmp(i) = 0xff000000 or (data(color + 2) << 16) or (data(color + 1) << 8) or data(color)
		inc color, 3
	next
end sub

sub update_display(num)
	if num <> &Hfe then
		if num = &Hff then
			local tmp = current_page1
			current_page1 = current_page2
			current_page2 = tmp
		else
			current_page1 = get_page(num)
		end if
	end if
	if next_palette <> -1 then
		local offset = next_palette * 32
		set_palette_444(offset, PALETTE_TYPE_AMIGA)
		set_palette_ega(offset + 1024)
		set_palette_444(offset + 1024, PALETTE_TYPE_VGA)
		next_palette = -1
	end if
	update_screen(current_page1 * PAGE_SIZE)
end sub

sub reset()
    local i
	current_page2 = 1
	current_page1 = 2
	current_page0 = get_page(&Hfe)
	math set 0, buffer8()
	next_palette = -1
	math set 0, vars()
	vars[&Hbc] = &H10
	vars[&Hc6] = &H80
	vars[&Hf2] = 6000 ' 4000 for Amiga bytecode
	vars[&Hdc] = 33
	vars[&He4] = 20
	next_part = 16001
    for i=0 to bound(tasks())
        clear_stack(i)
    next
    timestamp = timer
end sub

sub tick()
	const current = timer
	inc delay, -(current - timestamp)
	do while delay <= 0
		run_tasks()
	loop
	timestamp = current
end sub

const INTERVAL = 50
' FIXME: Review
var canvas
var timer

sub init(name)
	canvas = document.getElementById(name)
	document.onkeydown = function(e) { set_key_pressed(e.keyCode, 1) }
	document.onkeyup   = function(e) { set_key_pressed(e.keyCode, 0) }
	reset()
	if (timer) {
		clearInterval(timer)
	}
	timer = setInterval(tick, INTERVAL)
end sub

function pause() {
	if (timer) {
		clearInterval(timer)
		timer = null
		return true
	}
	timer = setInterval(tick, INTERVAL)
	return false
}

sub change_palette(num)
	palette_type = num
end sub

sub change_part(num)
	reset()
	next_part = 16001 + num
end sub

sub set_1991_resolution(low)
	is_1991 = low
end sub

sub update_screen(offset)
	var context = canvas.getContext('2d')
	var data = context.getImageData(0, 0, SCREEN_W, SCREEN_H)
	var rgba = new Uint32Array(data.data.buffer)
	if (is_1991) {
		var rgba_offset = 0
		for (var y = 0 y < SCREEN_H y += SCALE) {
			for (var x = 0 x < SCREEN_W x += SCALE) {
				const color = palette32[palette_type * 16 + buffer8[offset + x]]
				for (var j = 0 j < SCALE ++j) {
					rgba.fill(color, rgba_offset + j * SCREEN_W + x, rgba_offset + j * SCREEN_W + x + SCALE)
				}
			}
			rgba_offset += SCREEN_W * SCALE
			offset += SCREEN_W * SCALE
		}
	} else {
		for (var i = 0 i < SCREEN_W * SCREEN_H ++i) {
			const color = buffer8[offset + i]
			if (color < 16) {
				rgba[i] = palette32[palette_type * 16 + color]
			} else {
				rgba[i] = palette_bmp[color - 16]
			}
		}
	}
	context.putImageData(data, 0, 0)
end sub

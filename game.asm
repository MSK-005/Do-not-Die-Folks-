; Abdullah Nukhbat 24L-0890
; Moazzam Shazad 24L-0673
; Prjoct Phase 1 Coal

org 0100h       ; COM program start
jmp start

; Player car position variables
player_row db 15        ; player car row position
player_col db 36        ; player car column position
player_color db 10      ; player car color (light green)

; Obstacle car tracking (up to 2 cars)
obstacle1_active db 0  ; 0 = inactive, 1 = active
obstacle1_row db 0     ; current row position
obstacle1_lane db 0    ; lane number (0, 1, or 2)
obstacle2_active db 0  ; 0 = inactive, 1 = active
obstacle2_row db 0     ; current row position
obstacle2_lane db 0    ; lane number (0, 1, or 2)
rand_seed db 137       ; PRNG seed for lane selection
coin_active db 0
coin_row db 0
coin_lane db 0
fuel_active db 0
fuel_row db 0
fuel_lane db 0
coins_score dw 0
fuel_level db 20
fuel_max db 20
last_tick db 0
fuel_msg db "Out of fuel! ESC to exit or 1 to replay", 0
coin_cooldown db 0
fuel_cooldown db 0
delay_outer dw 300
delay_inner dw 500
delay_min_outer dw 60
delay_min_inner dw 90
obstacle_spawn_cd db 0
paused db 0
name_len db 0
name_buf times 32 db 0

start:
    call clear_screen

    ; Set text mode 3 (80x25)
    mov ax, 0003h
    int 10h

    ; Set ES = video memory
    mov ax, 0B800h
    mov es, ax

    ; Interface drawing deferred until after instructions (via restart_game)

    ; Show intro and instruction screens, then ask name
    call show_intro
    call show_instructions
    call enter_name
    call wait_press_any_key
    call clear_screen
    call restart_game
    jmp game_loop

    ; Main game loop
game_loop:
    ; Load player car position
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]

    ; Draw player car
    call draw_car
    call draw_hud

    ; Check for keyboard input (non-blocking)
    mov ah, 01h          ; check if key is available
    int 16h
    jnz handle_key_input ; key pressed, handle it
    jmp no_key_press

handle_key_input:
    mov ah, 00h
    int 16h
    cmp ah, 01h
    jne check_keys
    jmp exit_game
check_keys:
    cmp ah, 4Bh
    jne check_right
    jmp move_left
check_right:
    cmp ah, 4Dh
    jne check_up
    jmp move_right
check_up:
    cmp ah, 48h
    jne check_down
    jmp move_up
check_down:
    cmp ah, 50h
    jne check_p
    jmp move_down
check_p:
    cmp al, 'P'
    jne check_a
    cmp byte [paused], 0
    jne unpause
    mov byte [paused], 1
    jmp pause_wait
unpause:
    mov byte [paused], 0
    mov dh, 12
    mov dl, 20
    mov cx, 50
pw_clear_pause:
    mov al, 0DBh
    mov ah, 07h
    call draw_pixel
    inc dl
    loop pw_clear_pause
    jmp no_key_press
check_a:
    cmp al, 'a'
    jne check_A
    jmp move_left
check_A:
    cmp al, 'A'
    jne check_d
    jmp move_left
check_d:
    cmp al, 'd'
    jne check_D
    jmp move_right
check_D:
    cmp al, 'D'
    jne check_R
    jmp move_right
check_R:
    cmp al, 'R'
    jne done_keys
    call clear_screen
    call restart_game
    jmp game_loop
done_keys:
    jmp no_key_press

move_left:
    ; Load current position
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    ; Clear player car at current position
    call clear_car
    ; Move left to previous lane (but stay within road bounds)
    cmp dl, 16           ; check if at leftmost lane
    jle no_key_press     ; already at left boundary
    cmp dl, 36           ; check if at middle lane
    je move_to_left_lane
    ; Must be at right lane (56), move to middle
    mov dl, 36
    mov [player_col], dl
    jmp fast_redraw
move_to_left_lane:
    mov dl, 16           ; move to left lane
    mov [player_col], dl
    jmp fast_redraw

move_right:
    ; Load current position
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    ; Clear player car at current position
    call clear_car
    ; Move right to next lane (but stay within road bounds)
    cmp dl, 56           ; check if at rightmost lane
    jge no_key_press     ; already at right boundary
    cmp dl, 16           ; check if at left lane
    je move_to_middle_lane
    ; Must be at middle lane (36), move to right
    mov dl, 56
    mov [player_col], dl
    jmp fast_redraw
move_to_middle_lane:
    mov dl, 36           ; move to middle lane
    mov [player_col], dl
    jmp fast_redraw

move_up:
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    call clear_car
    mov al, [player_row]
    cmp al, 2
    jle no_key_press
    dec al
    mov [player_row], al
    jmp fast_redraw

move_down:
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    call clear_car
    mov al, [player_row]
    cmp al, 18
    jge no_key_press
    inc al
    mov [player_row], al
    jmp fast_redraw

no_key_press:
    cmp byte [paused], 1
    je pause_wait
    call update_obstacle_cars
    call update_collectibles
    call update_fuel
    call delay
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    call draw_car
    call check_collision
    jmp game_loop

fast_redraw:
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    call draw_car
    call draw_hud
    call check_collision
    jmp game_loop

pause_wait:
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 20
    int 10h
    mov si, paused_msg
    call print_string
pw_loop:
    mov ah, 01h
    int 16h
    jz pw_loop
    mov ah, 00h
    int 16h
    cmp al, 'P'
    je unpause
    cmp al, 'R'
    je pw_replay
    cmp ah, 01h
    je exit_game
    jmp pw_loop
pw_replay:
    call clear_screen
    call restart_game
    jmp game_loop

exit_game:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov si, end_msg
    call print_string
    mov ah, 02h
    mov dh, 14
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov si, score_prefix
    call print_string
    mov si, name_buf
    call print_string
    mov ah, 0Eh
    mov si, score_suffix
    call print_string
    mov ax, [coins_score]
    call print_number
    call wait_for_enter
    mov ax, 4C00h
    int 21h

; --------------------------
; Subroutine: draw_square
; Parameters pushed in order (all 16-bit):
; [SP+0] = top-left offset
; [SP+2] = rows
; [SP+4] = columns
; [SP+6] = color one (SI)
; [SP+8] = color two (DI)
; --------------------------
draw_square:

    push bp
    mov bp, sp

    ; retrieve parameters from stack
    mov bx, [bp+4]    ; top-left offset
    mov cx, [bp+6]    ; rows
    mov dx, [bp+8]    ; columns
    mov si, [bp+10]   ; color one
    mov di, [bp+12]   ; color two

row_loop:
    cmp cx, 0
    je done_square

    push bx           ; save row start offset

    mov bp, dx        ; column counter
    mov ax, si        ; current color (low byte AL will be written)
draw_col:
    cmp bp, 0
    je next_row
    mov [es:bx], byte 219   ; write character
    inc bx
    mov [es:bx], al         ; write attribute (low byte of AX = color)
    inc bx
    dec bp
    jmp draw_col

next_row:
    pop bx
    add bx, 160       ; move to next row
    dec cx

    xchg si, di       ; swap colors for alternating
    jmp row_loop

done_square:
    pop bp
    ret



; --------------------------
; Subroutine: clear_screen
; Fills screen with spaces (0x20) and attribute 0x07
; --------------------------
clear_screen:
    push ax
    push bx
    push cx
    push di

    mov ax, 0B800h
    mov es, ax

    xor bx, bx        ; offset = 0
    mov cx, 2000      ; 80*25 = 2000 characters
    mov al, 20h       ; space character
    mov ah, 07h       ; attribute

clear_loop:
    mov [es:bx], al
    inc bx
    mov [es:bx], ah
    inc bx
    loop clear_loop

    pop di
    pop cx
    pop bx
    pop ax
    ret

; --------------------------
; Subroutine: delay
; Simple busy-wait delay
; --------------------------
; --------------------------
; Subroutine: delay
; Simple busy-wait delay using nested DEC/JNZ
; --------------------------
delay:
    push cx
    push dx

    mov cx, [delay_outer]
outer_loop:
    mov dx, [delay_inner]
inner_loop:
    dec dx
    jnz inner_loop
    dec cx
    jnz outer_loop

    pop dx
    pop cx
    ret

; ============================================
; draw_car
; parameters:
;   dh = top row position
;   dl = left column position
;   bl = main car body color (0-15)
; car size: 7 columns x 9 rows (rectangular)
; ============================================
draw_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; save parameters
    mov ch, dh          ; ch = start row
    mov cl, dl          ; cl = start column
    mov bh, bl          ; bh = main car color

    ; row 0: front tires + headlights (two-column gap)
    mov dh, ch
    mov dl, cl
    mov al, 0dbh
    mov ah, 0           ; tire left
    call draw_pixel

    inc dl
    mov ah, 0eh         ; headlight left
    call draw_pixel
    inc dl
    mov ah, bh          ; body center
    call draw_pixel
    inc dl
    mov ah, bh          ; body center (second gap column)
    call draw_pixel
    inc dl
    mov ah, 0eh         ; headlight right
    call draw_pixel
    inc dl
    mov ah, 0           ; tire right
    call draw_pixel

    ; row 1: front windshield (width = 6)
    inc dh
    mov dl, cl
    mov al, 0dbh
    mov ah, bh          ; left edge
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan (extra for width 6)
    call draw_pixel
    inc dl
    mov ah, bh          ; right edge
    call draw_pixel

    mov si, 1
body_loop:
    inc dh
    mov dl, cl
    mov al, 0dbh
    mov ah, bh          ; left edge
    call draw_pixel
    inc dl
    mov ah, bh          ; center
    call draw_pixel
    inc dl
    mov ah, bh          ; center
    call draw_pixel
    inc dl
    mov ah, bh          ; center
    call draw_pixel
    inc dl
    mov ah, bh          ; center (extra for width 6)
    call draw_pixel
    inc dl
    mov ah, bh          ; right edge
    call draw_pixel

    dec si
    jnz body_loop

    ; row 2: rear windshield (width = 6)
    inc dh
    mov dl, cl
    mov al, 0dbh
    mov ah, bh          ; left edge
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan
    call draw_pixel
    inc dl
    mov ah, 3           ; cyan (extra for width 6)
    call draw_pixel
    inc dl
    mov ah, bh          ; right edge
    call draw_pixel

    ; row 3: rear tires + tail lights (width = 5)
    inc dh
    mov dl, cl
    mov al, 0dbh
    mov ah, 0           ; tire left
    call draw_pixel
    inc dl
    mov ah, 4           ; tail light left
    call draw_pixel
    inc dl
    mov ah, bh          ; body center
    call draw_pixel
    inc dl
    mov ah, bh          ; body center (second gap column)
    call draw_pixel
    inc dl
    mov ah, 4           ; tail light right
    call draw_pixel
    inc dl
    mov ah, 0           ; tire right
    call draw_pixel

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; draw_pixel
; parameters:
;   dh = row
;   dl = column
;   al = character
;   ah = attribute (color)
; ============================================
draw_pixel:
    push ax
    push bx
    push dx
    push di

    ; calculate offset: (row * 160) + (col * 2)
    push ax
    mov al, dh
    mov bl, 160
    mul bl
    mov di, ax
    mov al, dl
    xor ah, ah
    shl ax, 1
    add di, ax
    pop ax

    ; write character and attribute
    mov [es:di], ax

    pop di
    pop dx
    pop bx
    pop ax
    ret

; ============================================
; clear_car
; Erases a car at the specified position by drawing spaces
; parameters:
;   dh = top row position
;   dl = left column position
; car size: 7 columns x 9 rows
; ============================================
clear_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; save parameters
    mov bh, dh          ; bh = start row (will be modified)
    mov bl, dl          ; bl = start column

    mov si, 5
clear_car_loop:
    mov dh, bh          ; current row
    mov dl, bl          ; current column
    mov cx, 6           ; clear width 6 to match car

clear_row_loop:
    mov al, 0DBh        ; full block character to restore road
    mov ah, 07h         ; match road attribute
    call draw_pixel
    inc dl
    loop clear_row_loop

    inc bh              ; move to next row
    dec si
    jnz clear_car_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; draw_obstacle_rect_clipped
; Draws a 7x9 red rectangle clipped to screen rows [0..24]
; parameters:
;   dh = top row
;   dl = left column
;   bl = attribute (use 04h for red)
; ============================================
draw_obstacle_rect_clipped:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si, 9           ; height
    mov bh, dh          ; current row
    mov cl, dl          ; base left column (8-bit)
draw_obs_row:
    mov dh, bh
    cmp dh, 0
    jl obs_skip_row
    cmp dh, 25
    jge obs_skip_row
    mov cx, 7           ; width
    mov al, 0DBh        ; full block
    mov ah, bl          ; color
    mov dl, cl          ; reset left column for this row
obs_row_draw_loop:
    call draw_pixel
    inc dl
    loop obs_row_draw_loop
obs_skip_row:
    inc bh
    dec si
    jnz draw_obs_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; clear_rect_clipped
; Clears a 7x9 area using road block (219) with attribute 07h
; parameters:
;   dh = top row
;   dl = left column
; ============================================
clear_rect_clipped:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si, 9
    mov bh, dh
    mov cl, dl
clr_row:
    mov dh, bh
    cmp dh, 0
    jl clr_skip_row
    cmp dh, 25
    jge clr_skip_row
    mov cx, 7
    mov al, 0DBh
    mov ah, 07h
    mov dl, cl
clr_row_draw:
    call draw_pixel
    inc dl
    loop clr_row_draw
clr_skip_row:
    inc bh
    dec si
    jnz clr_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; update_obstacle_cars
; Moves all active obstacle cars down one row
; ============================================
update_obstacle_cars:
    push ax
    push bx
    push cx
    push dx

    ; handle inactive obstacle spawn cooldown
    cmp byte [obstacle1_active], 1
    je o1_active_path
    cmp byte [obstacle_spawn_cd], 0
    je o1_try_spawn
    dec byte [obstacle_spawn_cd]
    jmp upd_done
o1_try_spawn:
    mov byte [obstacle1_row], 0
    mov ah, 00h
    int 1Ah
    mov al, [rand_seed]
    mov bl, 37
    mul bl
    add al, dl
    mov [rand_seed], al
    xor ax, ax
    mov al, [rand_seed]
    mov bl, 3
    div bl
    mov al, ah
    ; avoid conflicts: coin lane, fuel lane
    cmp byte [coin_active], 1
    jne o1_chk_fuel
    cmp al, [coin_lane]
    je o1_delay_spawn
o1_chk_fuel:
    cmp byte [fuel_active], 1
    jne o1_lane_ok
    cmp al, [fuel_lane]
    je o1_delay_spawn
o1_lane_ok:
    mov [obstacle1_lane], al
    mov byte [obstacle1_active], 1
    jmp o1_active_path
o1_delay_spawn:
    mov byte [obstacle_spawn_cd], 36
    jmp upd_done

o1_active_path:
    ; single obstacle car using car sprite
    cmp byte [obstacle1_active], 1
    je o1_active_continue
    jmp upd_done
o1_active_continue:

    ; clear current car position with road background
    mov dh, [obstacle1_row]
    mov al, [obstacle1_lane]
    call get_lane_column
    mov dl, al
    call clear_car

    ; advance one row
    inc byte [obstacle1_row]
    mov dh, [obstacle1_row]

    ; respawn at top with random lane when reaching bottom
    cmp dh, 25
    jl draw_obst_car
    mov byte [obstacle1_row], 0
    mov ax, [delay_outer]
    cmp ax, [delay_min_outer]
    jle o1_no_outer_dec
    sub ax, 2
    mov [delay_outer], ax
o1_no_outer_dec:
    mov ax, [delay_inner]
    cmp ax, [delay_min_inner]
    jle o1_no_inner_dec
    sub ax, 3
    mov [delay_inner], ax
o1_no_inner_dec:
    mov ah, 00h
    int 1Ah
    mov al, [rand_seed]
    mov bl, 37
    mul bl                 ; AX = AL*BL, new seed in AL
    add al, dl             ; add timer low byte for entropy
    mov [rand_seed], al
    xor ax, ax
    mov al, [rand_seed]
    mov bl, 3
    div bl                 ; quotient AL, remainder AH (0..2)
    mov al, ah             ; use remainder as lane
    ; choose lane and avoid immediate conflicts; if conflict, delay spawn
    ; map player col to lane
    cmp byte [coin_active], 1
    jne o1_chk_fuel2
    cmp al, [coin_lane]
    je o1_set_delay
o1_chk_fuel2:
    cmp byte [fuel_active], 1
    jne o1_set_lane
    cmp al, [fuel_lane]
    je o1_set_delay
o1_set_lane:
    mov [obstacle1_lane], al
    mov dh, [obstacle1_row]
    jmp draw_obst_car
o1_set_delay:
    mov byte [obstacle_spawn_cd], 36
    mov byte [obstacle1_active], 0
    jmp upd_done
    mov dh, [obstacle1_row]

draw_obst_car:
    mov al, [obstacle1_lane]
    call get_lane_column
    mov dl, al
    mov bl, 04h
    call draw_car

upd_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; get_lane_column
; Converts lane number to column position
; parameters: al = lane number (0, 1, or 2)
; returns: al = column position (16, 36, or 56)
; ============================================
get_lane_column:
    cmp al, 0
    jne glc_chk1
    mov al, 16
    ret
glc_chk1:
    cmp al, 1
    jne glc_lane2
    mov al, 36
    ret
glc_lane2:
    mov al, 56
    ret

; get_lane_from_col
; parameters: al = column (16,36,56)
; returns: al = lane (0,1,2)
get_lane_from_col:
    cmp al, 16
    jne glfc_chk36
    mov al, 0
    ret
glfc_chk36:
    cmp al, 36
    jne glfc_lane2
    mov al, 1
    ret
glfc_lane2:
    mov al, 2
    ret

; ============================================
; draw_coin_glyph: 3x3 yellow square with black center
; parameters: dh=row (center), dl=column (center)
; ============================================
draw_coin_glyph:
    push ax
    push bx
    push cx
    push dx
    mov bh, dh
    mov bl, dl
    ; top row (bh-1): Y Y Y
    mov dh, bh
    dec dh
    cmp dh, 0
    jl dc_skip_top
    cmp dh, 25
    jge dc_skip_top
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
dc_skip_top:
    ; middle row (bh): Y B Y
    mov dh, bh
    cmp dh, 25
    jge dc_skip_mid
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 00h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
dc_skip_mid:
    ; bottom row (bh+1): Y Y Y
    mov dh, bh
    inc dh
    cmp dh, 25
    jge dc_done
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 0Eh
    call draw_pixel
dc_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; clear_coin_glyph: restores 3x3 area to road
; parameters: dh=row (center), dl=column (center)
; ============================================
clear_coin_glyph:
    push ax
    push bx
    push cx
    push dx
    mov bh, dh
    mov bl, dl
    ; top
    mov dh, bh
    dec dh
    cmp dh, 0
    jl cc_skip_top
    cmp dh, 25
    jge cc_skip_top
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cc_skip_top:
    ; middle
    mov dh, bh
    cmp dh, 25
    jge cc_skip_mid
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cc_skip_mid:
    ; bottom
    mov dh, bh
    inc dh
    cmp dh, 25
    jge cc_done
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cc_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
draw_fuel_glyph:
    push ax
    push bx
    push cx
    push dx
    mov bh, dh
    mov bl, dl
    ; top row: R R R
    mov dh, bh
    dec dh
    cmp dh, 0
    jl df_skip_top
    cmp dh, 25
    jge df_skip_top
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
df_skip_top:
    ; middle row: R B R
    mov dh, bh
    cmp dh, 25
    jge df_skip_mid
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 00h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
df_skip_mid:
    ; bottom row: R R R
    mov dh, bh
    inc dh
    cmp dh, 25
    jge df_done
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 04h
    call draw_pixel
df_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

clear_fuel_glyph:
    push ax
    push bx
    push cx
    push dx
    mov bh, dh
    mov bl, dl
    ; top
    mov dh, bh
    dec dh
    cmp dh, 0
    jl cf_skip_top
    cmp dh, 25
    jge cf_skip_top
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cf_skip_top:
    ; middle
    mov dh, bh
    cmp dh, 25
    jge cf_skip_mid
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cf_skip_mid:
    ; bottom
    mov dh, bh
    inc dh
    cmp dh, 25
    jge cf_done
    mov dl, bl
    dec dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
    inc dl
    mov al, 219
    mov ah, 07h
    call draw_pixel
cf_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
; ============================================
; draw_hud
; Draws fuel bar and coins counter at top-left
; ============================================
draw_hud:
    push ax
    push bx
    push cx
    push dx

    ; print "Fuel: " at row 0, col 0
    mov ah, 02h
    mov bh, 0
    mov dh, 0
    mov dl, 0
    int 10h
    mov ah, 0Eh
    mov al, 'F'
    int 10h
    mov al, 'u'
    int 10h
    mov al, 'e'
    int 10h
    mov al, 'l'
    int 10h
    mov al, ':'
    int 10h
    mov al, ' '
    int 10h

    ; clear fuel bar area (print spaces up to fuel_max)
    mov ah, 02h
    mov bh, 0
    mov dh, 0
    mov dl, 6
    int 10h
    mov cl, [fuel_max]
clear_bar_loop:
    cmp cl, 0
    je draw_bar_start
    mov ah, 0Eh
    mov al, ' '
    int 10h
    dec cl
    jmp clear_bar_loop
draw_bar_start:
    ; draw fuel bar as pipes '|' up to fuel_level
    mov ah, 02h
    mov bh, 0
    mov dh, 0
    mov dl, 6
    int 10h
    mov cl, [fuel_level]
draw_bar_loop:
    cmp cl, 0
    je draw_bar_done
    mov ah, 0Eh
    mov al, '|'
    int 10h
    dec cl
    jmp draw_bar_loop
draw_bar_done:

    ; print "Score of <name> is: " and number at row 1
    mov ah, 02h
    mov bh, 0
    mov dh, 1
    mov dl, 0
    int 10h
    mov ah, 0Eh
    mov al, 'S'
    int 10h
    mov al, 'c'
    int 10h
    mov al, 'o'
    int 10h
    mov al, 'r'
    int 10h
    mov al, 'e'
    int 10h
    mov al, ' '
    int 10h
    mov al, 'o'
    int 10h
    mov al, 'f'
    int 10h
    mov al, ' '
    int 10h
    ; print name
    mov si, name_buf
    call print_string
    mov ah, 0Eh
    mov al, ' '
    int 10h
    mov al, 'i'
    int 10h
    mov al, 's'
    int 10h
    mov al, ':'
    int 10h
    mov al, ' '
    int 10h
    ; print number (coins_score)
    mov ax, [coins_score]
    call print_number

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; print_number: prints AX as decimal at current cursor
print_number:
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    mov cx, 0
pn_div_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne pn_div_loop
pn_print:
    mov ah, 0Eh
    pop dx
    add dl, '0'
    mov al, dl
    int 10h
    loop pn_print
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; update_fuel: slowly decreases fuel, ends game at zero
; ============================================
update_fuel:
    push ax
    push bx
    push cx
    push dx
    mov ah, 00h
    int 1Ah
    mov al, dl
    mov bl, [last_tick]
    cmp al, bl
    je uf_done
    mov [last_tick], al
    ; decrease roughly every 8 ticks
    test al, 7
    jnz uf_done
    cmp byte [fuel_level], 0
    je uf_game_over
    dec byte [fuel_level]
    jmp uf_done
uf_game_over:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 10
    int 10h
    mov si, fuel_msg
    call print_string
wait_fuel_over:
    mov ah, 01h
    int 16h
    jz wait_fuel_over
    mov ah, 00h
    int 16h
    cmp ah, 01h
    je exit_game
    cmp al, '1'
    jne wait_fuel_over
    call clear_screen
    call restart_game
    jmp game_loop
uf_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; print_string: prints ASCIIZ at SI
print_string:
    push ax
    push dx
ps_loop:
    lodsb
    cmp al, 0
    je ps_done
    mov ah, 0Eh
    int 10h
    jmp ps_loop
ps_done:
    pop dx
    pop ax
    ret

; ============================================
; update_collectibles: coins and fuel spawn and scroll
; ============================================
update_collectibles:
    push ax
    push bx
    push cx
    push dx

    ; ----- coins -----
    cmp byte [coin_active], 1
    jne maybe_spawn_coin
    ; clear coin (3x3)
    mov dh, [coin_row]
    mov al, [coin_lane]
    call get_lane_column
    mov dl, al
    call clear_coin_glyph
    ; advance
    inc byte [coin_row]
    mov dh, [coin_row]
    cmp dh, 25
    jl draw_coin
    mov byte [coin_active], 0
    jmp coins_done
draw_coin:
    mov al, [coin_lane]
    call get_lane_column
    mov dl, al
    ; draw 3x3 coin glyph
    call draw_coin_glyph
coins_done:

maybe_spawn_coin:
    cmp byte [coin_active], 0
    jne fuel_section
    cmp byte [coin_cooldown], 0
    je coin_cool_ok
    dec byte [coin_cooldown]
    jmp fuel_section
coin_cool_ok:
    mov ah, 00h
    int 1Ah
    test dl, 1
    jnz fuel_section
    ; choose lane
    xor ax, ax
    mov al, [rand_seed]
    mov bl, 3
    div bl
    mov al, ah
    ; rotate to a free lane if conflicts with obstacles or fuel
    mov cl, 0
coin_try_lane:
    cmp byte [obstacle1_active], 1
    jne coin_chk_obst2
    cmp al, [obstacle1_lane]
    jne coin_chk_obst2
    jmp coin_next_lane
coin_chk_obst2:
    cmp byte [obstacle2_active], 1
    jne coin_chk_fuel
    cmp al, [obstacle2_lane]
    jne coin_chk_fuel
    jmp coin_next_lane
coin_chk_fuel:
    ; avoid conflict with active fuel item lane
    cmp byte [fuel_active], 1
    jne coin_lane_ok
    cmp al, [fuel_lane]
    jne coin_lane_ok
    jmp coin_next_lane

coin_next_lane:
    inc cl
    cmp cl, 3
    jge coin_skip_frame      ; all lanes taken, skip and delay
    inc al
    cmp al, 3
    jl coin_try_lane
    mov al, 0
    jmp coin_try_lane
coin_lane_ok:
    mov [coin_lane], al
    mov byte [coin_row], 0
    mov byte [coin_active], 1
    jmp coins_done
coin_skip_frame:
    mov byte [coin_cooldown], 36

fuel_section:
    cmp byte [fuel_active], 1
    jne maybe_spawn_fuel
    mov dh, [fuel_row]
    mov al, [fuel_lane]
    call get_lane_column
    mov dl, al
    call clear_fuel_glyph
    ; advance
    inc byte [fuel_row]
    mov dh, [fuel_row]
    cmp dh, 25
    jl draw_fuel
    mov byte [fuel_active], 0
    jmp collectibles_done
draw_fuel:
    mov al, [fuel_lane]
    call get_lane_column
    mov dl, al
    call draw_fuel_glyph

maybe_spawn_fuel:
    cmp byte [fuel_active], 0
    jne collectibles_done
    cmp byte [fuel_cooldown], 0
    je fuel_cool_ok
    dec byte [fuel_cooldown]
    jmp collectibles_done
fuel_cool_ok:
    mov ah, 00h
    int 1Ah
    ; rarer spawn: require (dl & 7)==0
    test dl, 7
    jnz collectibles_done
    ; choose lane avoiding coin lane if active
    xor ax, ax
    mov al, [rand_seed]
    mov bl, 3
    div bl
    mov al, ah
    ; rotate to a free lane if conflicts with obstacles or coin
    mov cl, 0
fuel_try_lane:
    cmp byte [obstacle1_active], 1
    jne fuel_chk_obst2
    cmp al, [obstacle1_lane]
    jne fuel_chk_obst2
    jmp fuel_next_lane
fuel_chk_obst2:
    cmp byte [obstacle2_active], 1
    jne fuel_chk_coin
    cmp al, [obstacle2_lane]
    jne fuel_chk_coin
    jmp fuel_next_lane
fuel_chk_coin:
    cmp byte [coin_active], 1
    jne fuel_lane_ok
    cmp al, [coin_lane]
    jne fuel_lane_ok
    jmp fuel_next_lane
fuel_next_lane:
    inc cl
    cmp cl, 3
    jge fuel_skip_frame ; all lanes taken, skip and delay
    inc al
    cmp al, 3
    jl fuel_try_lane
    mov al, 0
    jmp fuel_try_lane
fuel_lane_ok:
    mov [fuel_lane], al
    mov byte [fuel_row], 0
    mov byte [fuel_active], 1
    jmp collectibles_done
fuel_skip_frame:
    mov byte [fuel_cooldown], 54

collectibles_done:
    ; check pickups (player vs coin/fuel)
    ; coin pickup
    cmp byte [coin_active], 1
    jne check_fuel_pick
    mov al, [coin_lane]
    call get_lane_column
    mov bl, al
    mov al, [player_col]
    cmp al, bl
    jne check_fuel_pick
    mov al, [player_row]
    mov bl, [coin_row]
    mov cl, al
    add cl, 4
    mov bh, bl
    add bh, 2
    cmp al, bh
    ja check_fuel_pick
    cmp bl, cl
    ja check_fuel_pick
    ; collect coin
    ; clear coin on pickup and add score
    mov dh, [coin_row]
    mov al, [coin_lane]
    call get_lane_column
    mov dl, al
    call clear_coin_glyph
    mov byte [coin_active], 0
    mov ax, [coins_score]
    add ax, 5
    mov [coins_score], ax

check_fuel_pick:
    cmp byte [fuel_active], 1
    jne uc_done
    mov al, [fuel_lane]
    call get_lane_column
    mov bl, al
    mov al, [player_col]
    cmp al, bl
    jne uc_done
    mov al, [player_row]
    mov bl, [fuel_row]
    mov cl, al
    add cl, 4
    mov bh, bl
    add bh, 2
    cmp al, bh
    ja uc_done
    cmp bl, cl
    ja uc_done
    mov dh, [fuel_row]
    mov al, [fuel_lane]
    call get_lane_column
    mov dl, al
    call clear_fuel_glyph
    mov byte [fuel_active], 0
    mov al, [fuel_max]
    mov [fuel_level], al

uc_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
; legacy labels removed by inlining

check_collision:
    push ax
    push bx
    push cx
    push dx

    cmp [obstacle1_active], byte 1
    jne coll_done
    mov al, [obstacle1_lane]
    call get_lane_column
    mov bl, al
    mov al, [player_col]
    cmp al, bl
    jne coll_done
    mov al, [player_row]
    mov bl, [obstacle1_row]
    mov cl, al
    add cl, 4
    mov bh, bl
    add bh, 4
    cmp al, bh
    ja coll_done
    cmp bl, cl
    ja coll_done
    jmp game_over

coll_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

game_over:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov al, 'G'
    int 10h
    mov al, 'a'
    int 10h
    mov al, 'm'
    int 10h
    mov al, 'e'
    int 10h
    mov al, ' '
    int 10h
    mov al, 'O'
    int 10h
    mov al, 'v'
    int 10h
    mov al, 'e'
    int 10h
    mov al, 'r'
    int 10h
    mov al, ','
    int 10h
    mov al, ' '
    int 10h
    mov al, 'E'
    int 10h
    mov al, 'S'
    int 10h
    mov al, 'C'
    int 10h
    mov al, ' '
    int 10h
    mov al, 't'
    int 10h
    mov al, 'o'
    int 10h
    mov al, ' '
    int 10h
    mov al, 'e'
    int 10h
    mov al, 'x'
    int 10h
    mov al, 'i'
    int 10h
    mov al, 't'
    int 10h
    mov al, ','
    int 10h
    mov al, ' '
    int 10h
    mov al, '1'
    int 10h
    mov al, ' '
    int 10h
    mov al, 't'
    int 10h
    mov al, 'o'
    int 10h
    mov al, ' '
    int 10h
    mov al, 'r'
    int 10h
    mov al, 'e'
    int 10h
    mov al, 'p'
    int 10h
    mov al, 'l'
    int 10h
    mov al, 'a'
    int 10h
    mov al, 'y'
    int 10h

wait_game_over:
    mov ah, 01h
    int 16h
    jz wait_game_over
    mov ah, 00h
    int 16h
    cmp ah, 01h
    je exit_game
    cmp al, '1'
    jne wait_game_over
    call clear_screen
    call restart_game
    jmp game_loop

; ============================================
; try_spawn_obstacle
; Tries to spawn a new obstacle car in an available lane
; Only spawns if there are less than 2 active cars and lane is available
; ============================================
try_spawn_obstacle:
    push ax
    push bx
    push cx
    push dx

    ; Count active obstacles
    mov cl, 0
    cmp [obstacle1_active], byte 1
    jne check_obst2_count
    inc cl
check_obst2_count:
    cmp [obstacle2_active], byte 1
    jne check_spawn_count
    inc cl

check_spawn_count:
    ; If 2 obstacles are active, don't spawn
    cmp cl, 2
    jge spawn_done

    ; Generate random number for lane selection
    mov ah, 00h
    int 1ah
    mov ax, dx
    mov dx, 0
    mov bx, 3
    div bx              ; remainder in dx (0, 1, or 2)

    ; Try to find an available lane
    mov ch, 3           ; try up to 3 times
try_lane:
    mov al, dl          ; al = lane number to try

    ; Check if this lane is already occupied
    cmp [obstacle1_active], byte 1
    jne check_obst2_lane
    cmp [obstacle1_lane], al
    je next_lane_try
check_obst2_lane:
    cmp [obstacle2_active], byte 1
    jne spawn_in_lane
    cmp [obstacle2_lane], al
    je next_lane_try

spawn_in_lane:
    ; This lane is available, spawn obstacle here
    ; Find which obstacle slot to use
    cmp [obstacle1_active], byte 0
    je use_obstacle1
    ; Use obstacle 2
    mov [obstacle2_active], byte 1
    mov [obstacle2_row], byte 0
    mov [obstacle2_lane], al
    ; Draw the new obstacle car
    mov dh, 0
    call get_lane_column
    mov dl, al
    mov bl, 4
    call draw_car
    jmp spawn_done

use_obstacle1:
    mov [obstacle1_active], byte 1
    mov [obstacle1_row], byte 0
    mov [obstacle1_lane], al
    ; Draw the new obstacle car
    mov dh, 0
    call get_lane_column
    mov dl, al
    mov bl, 4
    call draw_car
    jmp spawn_done

next_lane_try:
    ; Try next lane
    inc dl
    cmp dl, 3
    jl wrap_lane
    mov dl, 0
wrap_lane:
    dec ch
    jnz try_lane

spawn_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
; wait_seconds: waits AL seconds using BIOS timer ticks (~18.2Hz)
wait_seconds:
    push ax
    push bx
    push cx
    push dx
    mov ah, 00h
    int 1Ah
    mov bl, dl          ; start tick
    mov cl, al          ; seconds
    mov bh, 18          ; ticks per second (approx)
ws_outer:
    mov ah, 00h
    int 1Ah
    mov al, dl
    sub al, bl
    cmp al, bh
    jb ws_outer
    mov ah, 00h
    int 1Ah
    mov bl, dl
    dec cl
    jnz ws_outer
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; wait_for_enter: blocks until Enter key pressed
wait_for_enter:
    push ax
wf_loop:
    mov ah, 01h
    int 16h
    jz wf_loop
    mov ah, 00h
    int 16h
    cmp al, 0Dh
    jne wf_loop
    pop ax
    ret

; show_intro: clear and print centered title for 5 seconds
show_intro:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 10
    mov dl, 25
    int 10h
    mov bl, 07h
    mov ah, 0Eh
    mov si, intro_line1
    call print_string
    mov ah, 02h
    mov dh, 12
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov si, intro_line2
    call print_string
    mov ah, 02h
    mov dh, 13
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov si, intro_line3
    call print_string
    call wait_for_enter
    ret

intro_line1 db " The Car Game ",0
intro_line2 db " Abdullah Nukhbat 24L-0890 ",0
intro_line3 db " Moazzam Shazad  24L-0673 ",0

; show_instructions: prints numbered instructions for 5 seconds
show_instructions:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 8
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov si, instr1
    call print_string
    mov ah, 02h
    mov dh, 10
    mov dl, 10
    int 10h
    mov si, instr2
    call print_string
    mov ah, 02h
    mov dh, 12
    mov dl, 10
    int 10h
    mov si, instr3
    call print_string
    mov ah, 02h
    mov dh, 14
    mov dl, 10
    int 10h
    mov si, instr4
    call print_string
    call wait_for_enter
    ret

instr1 db "1. Arrow/A,D to move lanes; Up/Down to move rows",0
instr2 db "2. Collect coins, avoid collisions; ESC ends",0
instr3 db "3. R to replay; P to pause/resume",0
instr4 db "4. Fuel drains; collect fuel to refill",0

; enter_name: prompt and read name until Enter
enter_name:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov si, name_prompt
    call print_string
    mov byte [name_len], 0
    mov ah, 02h
    mov dh, 13
    mov dl, 10
    int 10h
en_loop:
    mov ah, 01h
    int 16h
    jz en_loop
    mov ah, 00h
    int 16h
    cmp al, 0Dh
    je en_done
    cmp al, 08h
    je en_backspace
    cmp byte [name_len], 31
    jge en_loop
    mov ah, 0Eh
    int 10h
    mov bl, [name_len]
    mov [name_buf+bx], al
    inc byte [name_len]
    jmp en_loop
en_backspace:
    cmp byte [name_len], 0
    je en_loop
    dec byte [name_len]
    mov ah, 02h
    mov bh, 0
    mov dl, 10
    mov dh, 13
    int 10h
    mov cl, [name_len]
    add dl, cl
    dec dl
    mov ah, 02h
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h
    mov ah, 02h
    int 10h
    jmp en_loop
en_done:
    mov bl, [name_len]
    mov byte [name_buf+bx], 0
    ret

name_prompt db "Enter your name and press Enter: ",0

; wait_press_any_key: blink message until a key is pressed
wait_press_any_key:
    call clear_screen
    mov ah, 02h
    mov bh, 0
    mov dh, 12
    mov dl, 20
    int 10h
    mov si, press_msg
    mov byte [last_tick], 0
wpak_loop:
    mov ah, 01h
    int 16h
    jnz wpak_done
    mov ah, 00h
    int 1Ah
    mov al, dl
    cmp al, [last_tick]
    je wpak_loop
    mov [last_tick], al
    test al, 1
    jnz wpak_hide
    mov ah, 02h
    mov dh, 12
    mov dl, 20
    int 10h
    mov si, press_msg
    call print_string
    jmp wpak_loop
wpak_hide:
    mov ah, 02h
    mov dh, 12
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov al, ' '
    mov cx, 28
wpak_clr:
    int 10h
    loop wpak_clr
    jmp wpak_loop
wpak_done:
    mov ah, 00h
    int 16h
    ret

press_msg db "Press any key to start the game",0
paused_msg db "Paused: P to resume, R to replay, ESC to exit",0
end_msg db "Game End.",0
score_prefix db " Score of ",0
score_suffix db " is: ",0
restart_game:
    mov ax, 0B800h
    mov es, ax
    mov byte [player_row], 15
    mov byte [player_col], 36
    mov byte [player_color], 10
    mov word [coins_score], 0
    mov al, [fuel_max]
    mov [fuel_level], al
    mov byte [coin_active], 0
    mov byte [fuel_active], 0
    mov byte [last_tick], 0
    mov byte [paused], 0
    mov byte [coin_cooldown], 0
    mov byte [fuel_cooldown], 0
    mov word [delay_outer], 300
    mov word [delay_inner], 500
    mov byte [obstacle1_active], 1
    mov byte [obstacle1_row], 0
    mov byte [obstacle1_lane], 0
    mov byte [obstacle2_active], 0
    mov bx, 0
    mov cx, 25
    mov dx, 12
    mov si, 0Ah
    mov di, 02h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 134
    mov cx, 25
    mov dx, 13
    mov si, 0Ah
    mov di, 02h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 20
    mov cx, 25
    mov dx, 60
    mov si, 07h
    mov di, 07h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 58
    mov cx, 25
    mov dx, 1
    mov si, 0Fh
    mov di, 00h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 20
    mov cx, 25
    mov dx, 1
    mov si, 14
    mov di, 00h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 140
    mov cx, 25
    mov dx, 1
    mov si, 14
    mov di, 0
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov bx, 98
    mov cx, 25
    mov dx, 1
    mov si, 0Fh
    mov di, 00h
    push di
    push si
    push dx
    push cx
    push bx
    call draw_square
    add sp, 10
    mov dh, [player_row]
    mov dl, [player_col]
    mov bl, [player_color]
    call draw_car
    call draw_hud
    ret

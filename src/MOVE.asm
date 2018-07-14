.nolist
#include "ti84pce.inc"

square_size     .equ 8d ; I'm making this an equate for readability, changing it without modifying other parts of the program will cause you problems.
coin_size       .equ 6d ; don't change this either

score_location  .equ pixelShadow

coin_y_location .equ pixelShadow + 2
coin_x_location .equ pixelShadow + 1 ; yummy little-endian format
coin_location   .equ pixelShadow + 1 ; for 24 byte registers.

rng_seed             .equ $71dc ; this can be anything non-zero
rng_seed_location    .equ pixelShadow + 4 ; +3 is upper byte of 24 bit register after ld <reg24>, coin_location
.list
  
  .org UserMem - 2
  .db tExtTok, tAsm84CeCmp
  
  call _RunIndicOff
  call _boot_ClearVRAM
  
; <init palette>, code came from C toolchain.
  ld	de,mpLcdPalette ; address of mmio palette
  ld	b,e ; b = 0
_paletteLoop:
  ld	a,b
  rrca
  xor	a,b
  and	a,224
  xor	a,b
  ld	(de),a
  inc	de
  ld	a,b
  rla
  rla
  rla
  ld	a,b
  rra
  ld	(de),a
  inc	de
  inc	b
  jr	nz,_paletteLoop ; loop for 256 times to fill palette
; </init palette>
  
  ld a, lcdBpp8
  ld (mpLcdCtrl), a
  
; seed rng
  ld hl, rng_seed
  ld (rng_seed_location), hl
  
  ld de, 0 ; clear upper byte
  
  ld a, 0
  ld (score_location), a
  ld (coin_location + 2), a
  
  ld d, (lcdHeight/square_size)/2 ; d holds y coord
  ld e, (lcdWidth/square_size)/2 ; e holds x coord
  
  jr _move_coin ; just for simplicity.
  
main_loop:
  ld hl, (coin_location)
  cp a, a ; thank you, jcgter <3
  sbc hl, de
  jr nz, _
  ld hl, score_location
  inc (hl)
_move_coin:
  call rng
  cp lcdWidth/square_size + 1
  jr c, __
  sub lcdWidth/square_size
__:
  ld (coin_y_location), a
  call rng
  ld a, r
  and %00000111 ; bitmask, limit to 0-7.
  add a, c
  ld (coin_x_location), a
  call draw_coin
_:
  xor a, a ; draw
  call draw
kbd_read:
  call _GetCSC
  or a
  jr z, kbd_read
  ld b, a
  cp skDel
  jr nz, kbd_end
  ld a, lcdBpp16 ; quit
  ld (mpLcdCtrl), a
  call _RunIndicOn
  ret ; quit
kbd_end:
  ld a, $ff ; erase
  call draw
; Movement code.
; input in b (getCSC code)
; moves the pixel by updating
; de (x coord) and c (y coord)
; nothing overly arcane happens
; I used to check if a was >= 5 or equal to skDel
; but my code caused bugs so I killed it (and the bugs)
chk_down:
  djnz chk_left
  inc d
  ld a, d
  cp lcdHeight/square_size
  jr c, main_loop
  ld d, lcdHeight/square_size - 1
  jr main_loop
chk_left:
  djnz chk_right
  dec e
  ld a, e
  inc a ; check for overflow (this is a pretty sweet optimization)
  jr nz, main_loop
  ld e, 0
  jr main_loop
chk_right:
  djnz chk_up
  inc e
  ld a, e
  cp lcdWidth/square_size
  jr c, main_loop
  ld e, lcdWidth/square_size - 1
  jr main_loop
chk_up:
  djnz main_loop
  dec d
  ld a, d
  inc a ; check for overflow
  jr nz, main_loop
  ld d, 0
  jr main_loop
draw:
; (whew this is a bit of work, it gave me lots of appreciation for the sprite routines :P)
; takes input in a: 00 = draw the pixel, ff = erase
  ld c, b
  ld (colorSet+1), a ; writes the color byte into the program.
  push de
    push de ; thanks, dTal, PT_, Runer and zeda for making me realize that I should never do assembly programming while extremely tired.
      ld e, lcdWidth/2
      mlt de
      ex de, hl
      add hl, hl ; this gets rid of the /2 part above
      add hl, hl ; the below stuff multiplies hl by square_size, which is 8.
      add hl, hl
      add hl, hl
      ld de, vRAM ; while we have corrupted de, let's use it to make hl point into vRAM.
      add hl, de
    pop de
    ld d, square_size
    mlt de
    add hl, de
    ld de, lcdWidth - square_size
    ld a, square_size
_loopOuter:
    ld b, square_size
_loopInner:
colorSet:
    ld (hl), $00 ; The color byte gets written in here.
    inc hl
    djnz _loopInner
    
    add hl, de
    dec a
    jr nz, _loopOuter
  pop de
  ld b, c
  ret
draw_coin:
; draws the coin! (some of this is repeated code, but I'm really concerned about speed.)
; this routine is like a tank, it destroys everything.
  push de
    ld de, $0
    ld hl, coin_y_location
    ld e, lcdWidth/2
    ld d, (hl)
    mlt de
    ex de, hl
    add hl, hl ; this gets rid of the /2 part above
    add hl, hl ; the below stuff multiplies hl by square_size, which is 8.
    add hl, hl
    add hl, hl
    ld de, vRAM+lcdWidth ; the '+lcdWidth' is to center it on the grid. The coin is 6x6 on an 8x8 grid, so we need 1 pixel of padding all around.
    add hl, de
    ld b, square_size
    ld a, (coin_x_location)
    ld c, a
    mlt bc
    add hl, bc
    inc hl
    ld de, lcdWidth - coin_size
    ld a, coin_size
_loopOuter2:
    ld b, coin_size
_loopInner2:
    ld (hl), $a4 ; gold
    inc hl
    djnz _loopInner2
    add hl, de
    dec a
    jr nz, _loopOuter2
  pop de
  ret
rng:
; generates a random number, 1-32, and stores the result in a
; destroys hl, bc
; to seed the rng (16-bit seed in hl):
; ld (rng_seed_location), hl
  ld b, 5 ; max output of rng = 2^b (0 <= b <= 7)
  ld hl, (rng_seed_location) ; seed rng with previous output
  ld c, $00 ; we'll be using c to hold the output, because we need a for other things.
_rng:
; A highly modified Galois LFSR. Nicely, the current
; example source code on wikipedia pretty much directly ports over.
  srl h ; shifts h, fills gap with 0. sets carry flag to what "fell off".
  rr l ; shifts l, fills gap with what fell off h.
  rl c ; output here, this is what's different from the wikipedia code. Carry flag (what fell off l) is pushed into bit 0 of c. I love this.
  bit 0, c
  jr nz, _
  ld a, h
  xor $B4 ; magic # from wiki article.
  ld h, a
_:
  djnz _rng
  ld (rng_seed_location), hl
  ld a, c
  ret